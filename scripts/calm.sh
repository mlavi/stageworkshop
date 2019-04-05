#!/usr/bin/env bash
# -x

#__main()__________

# Source Nutanix environment (PATH + aliases), then common routines + global variables
. /etc/profile.d/nutanix_env.sh
. lib.common.sh
. global.vars.sh
begin

args_required 'EMAIL PE_PASSWORD PC_VERSION'

#dependencies 'install' 'jq' && ntnx_download 'PC' & #attempt at parallelization
# Some parallelization possible to critical path; not much: would require pre-requestite checks to work!

case ${1} in
  PE | pe )
    . lib.pe.sh

    args_required 'PE_HOST PC_LAUNCH'
    ssh_pubkey & # non-blocking, parallel suitable

    dependencies 'install' 'sshpass' && dependencies 'install' 'jq' \
    && pe_license \
    && pe_init \
    && network_configure \
    && authentication_source \
    && pe_auth

    if (( $? == 0 )) ; then
      pc_install "${NW1_NAME}" \
      && prism_check 'PC' \
      && cluster_register \
      #&& dependencies 'remove' 'sshpass' && dependencies 'remove' 'jq'

      log "PC Configuration complete: Waiting for PC deployment to complete, API is up!"
      log "PE = https://${PE_HOST}:9440"
      log "PC = https://${PC_HOST}:9440"

      images &

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

    run_once

    dependencies 'install' 'jq' || exit 13

    ssh_pubkey & # non-blocking, parallel suitable

    pc_passwd
    ntnx_cmd # check cli services available?

    export   NUCLEI_SERVER='localhost'
    export NUCLEI_USERNAME="${PRISM_ADMIN}"
    export NUCLEI_PASSWORD="${PE_PASSWORD}"
    # nuclei -debug -username admin -server localhost -password x vm.list

    if [[ -z "${PE_HOST}" ]]; then # -z ${CLUSTER_NAME} || #TOFIX
      log "CLUSTER_NAME=|${CLUSTER_NAME}|, PE_HOST=|${PE_HOST}|"
      pe_determine ${1}
      . global.vars.sh # re-populate PE_HOST dependencies
    else
      CLUSTER_NAME=$(ncli --json=true multicluster get-cluster-state | \
                      jq -r .data[0].clusterDetails.clusterName)
      if [[ ${CLUSTER_NAME} != '' ]]; then
        log "INFO: ncli multicluster get-cluster-state looks good for ${CLUSTER_NAME}."
      else
        log "INFO: couldn't determine CLUSTER_NAME."
      fi
    fi

    if [[ ! -z "${2}" ]]; then # hidden bonus
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

    # if calm is enabling, lcm will failed due to epilson service failed
    # added some codes in calm_enable() to wait task complete
    ssp_auth \
    && calm_enable \
    && lcm \
    && lcm_calm

    images \
    && pc_cluster_img_import \
    && prism_check 'PC'

    log "Non-blocking functions (in development) follow."
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
