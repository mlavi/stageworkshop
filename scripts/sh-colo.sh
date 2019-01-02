#!/usr/bin/env bash
# -x

#__main()__________

# Source Nutanix environment (PATH + aliases), then Workshop common routines + global variables
. /etc/profile.d/nutanix_env.sh
. lib.common.sh
. global.vars.sh
begin

args_required 'MY_EMAIL PE_PASSWORD PC_VERSION'

#dependencies 'install' 'jq' && ntnx_download 'PC' & #attempt at parallelization

log "Adding key to ${1} VMs..."
ssh_pubkey & # non-blocking, parallel suitable

# Some parallelization possible to critical path; not much: would require pre-requestite checks to work!

case ${1} in
  PE | pe )
    . lib.pe.sh

    args_required 'PE_HOST PC_MANIFEST'

    dependencies 'install' 'sshpass' && dependencies 'install' 'jq' \
    && pe_license \
    && pe_init \
    && network_configure \
    && authentication_source \
    && pe_auth

    if (( $? == 0 )) ; then

      # local override: pc deploy file in sh-colo, TODO: make an array of URLs
                 PC_URL=http://10.132.128.50/E%3A/share/Nutanix/PrismCentral/pc-${PC_VERSION}-deploy.tar
         PC_DEV_METAURL=http://10.132.128.50/E%3A/share/Nutanix/PrismCentral/pc-${PC_VERSION}-deploy-metadata.json
      PC_STABLE_METAURL=${PC_DEV_METAURL}

      pc_install \
      && prism_check 'PC' \
      && pc_configure \
      && dependencies 'remove' 'sshpass' && dependencies 'remove' 'jq'
      ## pc_configure

      log "PC Configuration complete: Waiting for PC deployment to complete, API is up!"
      log "PE = https://${PE_HOST}:9440"
      log "PC = https://${PC_HOST}:9440"

      finish
    else
      finish
      _error=18
      log "Error ${_error}: in main functional chain, exit!"
      exit ${_error}
    fi
  ;;
  PC | pc )
    . lib.pc.sh
    dependencies 'install' 'sshpass' && dependencies 'install' 'jq' || exit 13

    pc_passwd
    ntnx_cmd # check cli services available?

    export   NUCLEI_SERVER='localhost'
    export NUCLEI_USERNAME="${PRISM_ADMIN}"
    export NUCLEI_PASSWORD="${PE_PASSWORD}"
    # nuclei -debug -username admin -server localhost -password x vm.list

    if [[ -z ${CLUSTER_NAME} || -z "${PE_HOST}" ]]; then
      pe_determine ${1}
      . global.vars.sh # re-populate PE_HOST dependencies
    fi

    if [[ ! -z "${2}" ]]; then
      # hidden bonus
      log "Don't forget: $0 first.last@nutanixdc.local%password"
      calm_update && exit 0
    fi

    export ATTEMPTS=2
    export    SLEEP=10

    pc_init \
    && pc_dns_add \
    && pc_ui \
    && pc_auth \
    && pc_smtp

    QCOW2_IMAGES=(\
      Centos7-Base.qcow2 \
      Centos7-Update.qcow2 \
      Windows2012R2.qcow2 \
      panlm-img-52.qcow2 \
      kx_k8s_01.qcow2 \
      kx_k8s_02.qcow2 \
      kx_k8s_03.qcow2 \
    )

    ssp_auth \
    && calm_enable \
    && lcm \
    && images \
    && pc_cluster_img_import \
    && prism_check 'PC'

    # new functions, non-blocking, at the end.
    pc_project
    flow_enable
    pc_admin

    # ntnx_download 'AOS' # function in lib.common.sh

    unset NUCLEI_SERVER NUCLEI_USERNAME NUCLEI_PASSWORD

    if (( $? == 0 )); then
      #dependencies 'remove' 'sshpass' && dependencies 'remove' 'jq' \
      #&&
      log "PC = https://${PC_HOST}:9440"
      finish
    else
      _error=19
      log "Error ${_error}: failed to reach PC!"
      exit ${_error}
    fi
  ;;
esac
