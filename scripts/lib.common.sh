#!/usr/bin/env bash
# dependencies: dig

function begin() {
  local _release

  if [[ -e ${RELEASE} ]]; then
    _release=" release: $(grep FullSemVer ${RELEASE} | awk -F\" '{print $4}')"
  fi

  log "$(basename ${0})${_release} start._____________________"
}

function args_required() {
  local _argument
  local    _error=88

  for _argument in ${1}; do
    if [[ ${DEBUG} ]]; then
      log "DEBUG: Checking ${_argument}..."
    fi
    _RESULT=$(eval "echo \$${_argument}")
    if [[ -z ${_RESULT} ]]; then
      log "Error ${_error}: ${_argument} not provided!"
      exit ${_error}
    elif [[ ${DEBUG} ]]; then
      log "Non-error: ${_argument} for ${_RESULT}"
    fi
  done

  if [[ ${DEBUG} ]]; then
    log 'Success: required arguments provided.'
  fi
}

function dependencies {
  local    _argument
  local       _error
  local       _index
  local         _cpe=/etc/os-release  # CPE = https://www.freedesktop.org/software/systemd/man/os-release.html
  local         _lsb=/etc/lsb-release # Linux Standards Base
  local    _os_found
  local      _jq_pkg=${JQ_REPOS[0]##*/}
  local _sshpass_pkg=${SSHPASS_REPOS[0]##*/}

  if [[ -z ${1} ]]; then
    _error=20
    log "Error ${_error}: missing install or remove verb."
    exit ${_error}
  elif [[ -z ${2} ]]; then
    _error=21
    log "Error ${_error}: missing package name."
    exit ${_error}
  fi

  if [[ -e ${_lsb} ]]; then
    _os_found="$(grep DISTRIB_ID ${_lsb} | awk -F= '{print $2}')"
  elif [[ -e ${_cpe} ]]; then
    _os_found="$(grep '^ID=' ${_cpe} | awk -F= '{print $2}')"
  fi

  case "${1}" in
    'install')
      log "Install ${2}..."
      export PATH=${PATH}:${HOME}
      if [[ -z `which ${2}` ]]; then
        case "${2}" in
          sshpass | ${_sshpass_pkg})
            if [[ ( ${_os_found} == 'Ubuntu' || ${_os_found} == 'LinuxMint' ) ]]; then
              sudo apt-get install --yes sshpass
            elif [[ ${_os_found} == '"centos"' ]]; then
              # TOFIX: assumption, probably on NTNX CVM or PCVM = CentOS7
              if [[ ! -e ${_sshpass_pkg} ]]; then
                repo_source SSHPASS_REPOS[@] ${_sshpass_pkg}
                download ${SOURCE_URL}
              fi
              sudo rpm -ivh ${_sshpass_pkg}
              if (( $? > 0 )); then
                _error=31
                log "Error ${_error}: cannot install ${2}."
                exit ${_error}
              fi
            elif [[ `uname -s` == "Darwin" ]]; then
              brew install https://raw.githubusercontent.com/kadwanev/bigboybrew/master/Library/Formula/sshpass.rb
            fi
            ;;
          jq | ${_jq_pkg} )
            if [[ ( ${_os_found} == 'Ubuntu' || ${_os_found} == 'LinuxMint' ) ]]; then
              if [[ ! -e ${_jq_pkg} ]]; then
                sudo apt-get install --yes jq
              fi
            elif [[ ${_os_found} == '"centos"' ]]; then
              if [[ ! -e ${_jq_pkg} ]]; then
                 repo_source JQ_REPOS[@] ${_jq_pkg}
                 download ${SOURCE_URL}
              fi
              chmod u+x ${_jq_pkg} && ln -s ${_jq_pkg} jq
              PATH+=:`pwd`
              export PATH
            elif [[ `uname -s` == "Darwin" ]]; then
              brew install jq
            fi
            ;;
        esac

        if (( $? > 0 )); then
          _error=98
          log "Error ${_error}: can't install ${2}."
          exit ${_error}
        fi
      else
        log "Success: found ${2}."
      fi
      ;;
    'remove')
      log "Removing ${2}..."
      if [[ ${_os_found} == '"centos"' ]]; then
        #TODO:30 assuming we're on PC or PE VM.
        case "${2}" in
          sshpass | ${_sshpass_pkg})
            sudo rpm -e sshpass
            ;;
          jq | ${_jq_pkg} )
            rm -f jq ${_jq_pkg}
            ;;
        esac
      else
        log "Feature: don't remove dependencies on Mac OS Darwin, Ubuntu, or LinuxMint."
      fi
      ;;
  esac
}

function dns_check() {
  local    _dns
  local  _error
  local _lookup=${1} # REQUIRED
  local   _test

  if [[ -z ${_lookup} ]]; then
    _error=43
    log "Error ${_error}: missing lookup record!"
    exit ${_error}
  fi

   _dns=$(dig +retry=0 +time=2 +short @${AUTH_HOST} ${_lookup})
  _test=$?

  if [[ ${_dns} != "${AUTH_HOST}" ]]; then
    _error=44
    log "Error ${_error}: result was ${_test}: ${_dns}"
    return ${_error}
  fi
}

function download() {
  local           _attempts=5
  local              _error=0
  local _http_range_enabled   # TODO disabled '--continue-at -'
  local               _loop=0
  local             _output
  local              _sleep=2

  if [[ -z ${1} ]]; then
    _error=33
    log "Error ${_error}: no URL to download!"
    exit ${_error}
  fi

  while true ; do
    (( _loop++ ))
    log "${1}..."
    _output=''
    curl ${CURL_OPTS} ${_http_range_enabled} --remote-name --location ${1}
    _output=$?
    #DEBUG=1; if [[ ${DEBUG} ]]; then log "DEBUG: curl exited ${_output}."; fi

    if (( ${_output} == 0 )); then
      log "Success: ${1##*/}"
      break
    fi

    if (( ${_loop} == ${_attempts} )); then
      _error=11
      log "Error ${_error}: couldn't download from: ${1}, giving up after ${_loop} tries."
      exit ${_error}
    elif (( ${_output} == 33 )); then
      log "Web server doesn't support HTTP range command, purging and falling back."
      _http_range_enabled=''
      rm -f ${1##*/}
    else
      log "${_loop}/${_attempts}: curl=${_output} ${1##*/} sleep ${_sleep}..."
      sleep ${_sleep}
    fi
  done
}

function fileserver() {
  local    _action=${1} # REQUIRED
  local      _host=${2} # REQUIRED, TODO: default to PE?
  local      _port=${3} # OPTIONAL
  local _directory=${4} # OPTIONAL

  if [[ -z ${1} ]]; then
    _error=38
    log "Error ${_error}: start or stop action required!"
    exit ${_error}
  fi
  if [[ -z ${2} ]]; then
    _error=39
    log "Error ${_error}: host required!"
    exit ${_error}
  fi
  if [[ -z ${3} ]]; then
    _port=8181
  fi
  if [[ -z ${4} ]]; then
    _directory=cache
  fi

  case ${_action} in
    'start' )
      # Determine if on PE or PC with _host PE or PC, then _host=localhost
      # ssh -nNT -R 8181:localhost:8181 nutanix@10.21.31.31
      pushd ${_directory} || exit

      remote_exec 'ssh' ${_host} \
        "python -m SimpleHTTPServer ${_port} || python -m http.server ${_port}"

      # acli image.create AutoDC2 image_type=kDiskImage wait=true container=Images \
      # source_url=http://10.4.150.64:8181/autodc-2.0.qcow2
      #AutoDC2: pending
      #AutoDC2: UploadFailure: Could not access the URL, please check the URL and make sure the hostname is resolvable
      popd || exit
      ;;
    'stop' )
      remote_exec 'ssh' ${_host} \
        "kill -9 $(pgrep python -a | grep ${_port} | awk '{ print $1 }')" 'OPTIONAL'
      ;;
  esac
}

function finish() {
  log "${0} ran for ${SECONDS} seconds._____________________"
  echo
}

function images() {
  # https://portal.nutanix.com/#/page/docs/details?targetId=Command-Ref-AOS-v59:acl-acli-image-auto-r.html
  local         _cli='acli'
  local     _command
  local   _http_body
  local       _image
  local  _image_type
  local        _name
  local      _source='source_url'
  local        _test

  which "$_cli"
  if (( $? > 0 )); then
         _cli='nuclei'
      _source='source_uri'
  fi

  for _image in "${QCOW2_IMAGES[@]}" ; do

    # log "DEBUG: ${_image} image.create..."
    if [[ ${_cli} == 'nuclei' ]]; then
      _test=$(source /etc/profile.d/nutanix_env.sh \
        && ${_cli} image.list 2>&1 \
        | grep -i complete \
        | grep "${_image}")
    else
      _test=$(source /etc/profile.d/nutanix_env.sh \
        && ${_cli} image.list 2>&1 \
        | grep "${_image}")
    fi

    if [[ ! -z ${_test} ]]; then
      log "Skip: ${_image} already complete on cluster."
    else
      _command=''
         _name="${_image}"

      if (( $(echo "${_image}" | grep -i -e '^http' -e '^nfs' | wc --lines) )); then
        log 'Bypass multiple repo source checks...'
        SOURCE_URL="${_image}"
      else
        repo_source QCOW2_REPOS[@] "${_image}" # IMPORTANT: don't ${dereference}[array]!
      fi

      if [[ -z "${SOURCE_URL}" ]]; then
        _error=30
        log "Warning ${_error}: didn't find any sources for ${_image}, continuing..."
        # exit ${_error}
      fi

      # TODO: TOFIX: ugly override for today...
      if (( $(echo "${_image}" | grep -i 'acs-centos' | wc --lines ) > 0 )); then
        _name=acs-centos
      fi

      if [[ ${_cli} == 'acli' ]]; then
        _image_type='kDiskImage'
        if (( $(echo "${SOURCE_URL}" | grep -i -e 'iso$' | wc --lines ) > 0 )); then
          _image_type='kIsoImage'
        fi

        _command+=" ${_name} annotation=${_image} image_type=${_image_type} \
          container=${MY_IMG_CONTAINER_NAME} architecture=kX86_64 wait=true"
      else
        _command+=" name=${_name} description=\"${_image}\""
      fi

      if [[ ${_cli} == 'nuclei' ]]; then
        _http_body=$(cat <<EOF
{"action_on_failure":"CONTINUE",
"execution_order":"SEQUENTIAL",
"api_request_list":[
  {"operation":"POST",
  "path_and_params":"/api/nutanix/v3/images",
  "body":{"spec":
  {"name":"${_name}","description":"${_image}","resources":{
    "image_type":"DISK_IMAGE",
    "source_uri":"${SOURCE_URL}"}},
  "metadata":{"kind":"image"},"api_version":"3.1.0"}}],"api_version":"3.0"}
EOF
        )
        _test=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST --data "${_http_body}" \
          https://localhost:9440/api/nutanix/v3/batch)
        log "batch _test=|${_test}|"
      else

        ${_cli} "image.create ${_command}" ${_source}=${SOURCE_URL} 2>&1 &
        if (( $? != 0 )); then
          log "Warning: Image submission: $?. Continuing..."
          #exit 10
        fi

        if [[ ${_cli} == 'nuclei' ]]; then
          log "NOTE: image.uuid = RUNNING, but takes a while to show up in:"
          log "TODO: ${_cli} image.list, state = COMPLETE; image.list Name UUID State"
        fi
      fi
    fi

  done
}

function log() {
  local _caller

  _caller=$(echo -n "`caller 0 | awk '{print $2}'`")
  echo "`date '+%Y-%m-%d %H:%M:%S'`|$$|${_caller}|${1}"
}

function ntnx_cmd() {
  local _attempts=25
  local    _error=10
  local     _hold
  local     _loop=0
  local    _sleep=10
  local   _status

  while [[ true ]]; do
    (( _loop++ ))
      _hold=$(nuclei cluster.list 2>&1)
    _status=$?

    if (( $(echo "${_hold}" | grep websocket | wc --lines) > 0 )); then
      log "Warning: Zookeeper isn't up yet."
    elif (( ${_status} > 0 )); then
       log "${_status} = ${_hold}, uh oh!"
    else
      log "Cluster info via nuceli seems good: ${_status}, moving on!"
      break
    fi

    if (( ${_loop} == ${_attempts} )); then
      log "Error ${_error}: couldn't determine cluster information, giving up after ${_loop} tries."
      exit ${_error}
    else
      log "${_loop}/${_attempts}: hold=${_hold} sleep ${_sleep}..."
      sleep ${_sleep}
    fi
  done
}

function ntnx_download() {
  local   _checksum
  local   _meta_url='http://download.nutanix.com/'
  local _source_url
  local    _version

  case ${1} in
    PC | pc )
      # When adding a new PC version, update BOTH case stanzas below...
      args_required 'PC_VERSION'

      case ${PC_VERSION} in
        5.9 | 5.6.2 | 5.8.0.1 )
          _version=2
          ;;
        * )
          _version=1
          ;;
      esac

      _meta_url+="pc/one-click-pc-deployment/${PC_VERSION}/v${_version}/"

      case ${PC_VERSION} in
        5.9 )
          _meta_url+="euphrates-${PC_VERSION}-stable-prism_central_one_click_deployment_metadata.json"
          ;;
        5.6.1 | 5.6.2 | 5.9.0.1 | 5.9.1 | 5.10 )
          _meta_url+="euphrates-${PC_VERSION}-stable-prism_central_metadata.json"
          ;;
        5.7.0.1 | 5.7.1 | 5.7.1.1 )
          _meta_url+="pc-${PC_VERSION}-stable-prism_central_metadata.json"
          ;;
        5.8.0.1 | 5.8.1 | 5.8.2 )
          _meta_url+="pc_deploy-${PC_VERSION}.json"
          ;;
        * )
          _error=22
          log "Error ${_error}: unsupported PC_VERSION=${PC_VERSION}!"
          log 'Browse to https://portal.nutanix.com/#/page/releases/prismDetails'
          log " - Find ${PC_VERSION} in the Additional Releases section on the lower right side"
          log ' - Provide the metadata URL for the "PC 1-click deploy from PE" option to this function, both case stanzas.'
          exit ${_error}
        ;;
      esac
    ;;
    'NOS' | 'nos' | 'AOS' | 'aos')
      args_required 'AOS_VERSION AOS_UPGRADE'

      # When adding a new AOS version, update BOTH case stanzas below...
      case ${AOS_UPGRADE} in
        5.8.0.1 )
          _version=2
          ;;
      esac

      _meta_url+="/releases/euphrates-${AOS_UPGRADE}-metadata/"

      if (( ${_version} > 0 )); then
        _meta_url+="v${_version}/"
      fi

      case ${AOS_UPGRADE} in
        5.8.0.1 | 5.9 )
          _meta_url+="euphrates-${AOS_UPGRADE}-metadata.json"
          ;;
        * )
          _error=23
          log "Error ${_error}: unsupported AOS_UPGRADE=${AOS_UPGRADE}!"
          # TODO: correct AOS_UPGRADE URL
          log 'Browse to https://portal.nutanix.com/#/page/releases/nosDetails'
          log " - Find ${AOS_UPGRADE} in the Additional Releases section on the lower right side"
          log ' - Provide the Upgrade metadata URL to this function for both case stanzas.'
          exit ${_error}
          ;;
      esac
    ;;
    FILES | files | AFS | afs )
      # When adding a new FILES version, update BOTH case stanzas below...
      args_required 'FILES_VERSION'

      case ${FILES_VERSION} in
        TBD )
          _version='v2/'
          ;;
        2.2.3 )
          _version='v1/'
          ;;
      esac

      _meta_url+="afs/${FILES_VERSION}/${_version}"

      case ${FILES_VERSION} in
        2.2.3 | 3.1.0.1 )
          _meta_url+="afs-${FILES_VERSION}.json"
          ;;
        * )
          _error=22
          log "Error ${_error}: unsupported FILES_VERSION=${FILES_VERSION}!"
          log 'Browse to https://portal.nutanix.com/#/page/releases/afsDetails?targetVal=GA'
          log " - Find ${FILES_VERSION} in the Additional Releases section on the lower right side"
          log ' - Provide the metadata URL option to this function, both case stanzas.'
          exit ${_error}
        ;;
      esac
    ;;
  esac

  if [[ ! -e ${_meta_url##*/} ]]; then
    log "Retrieving download metadata ${_meta_url##*/} ..."
    download "${_meta_url}"
  else
    log "Warning: using cached download ${_meta_url##*/}"
  fi

  dependencies 'install' 'jq' || exit 13
  _source_url=$(cat ${_meta_url##*/} | jq -r .download_url_cdn)

  if (( `pgrep curl | wc --lines | tr -d '[:space:]'` > 0 )); then
    pkill curl
  fi
  log "Retrieving Nutanix ${1} bits..."
  download "${_source_url}"

  _checksum=$(md5sum ${_source_url##*/} | awk '{print $1}')
  if [[ `cat ${_meta_url##*/} | jq -r .hex_md5` != "${_checksum}" ]]; then
    log "Error: md5sum ${_checksum} doesn't match on: ${_source_url##*/} removing and exit!"
    rm -f ${_source_url##*/}
    exit 2
  else
    log "Success: ${1} bits downloaded and passed MD5 checksum!"
  fi

  # Set globals for next step handoff
  export   NTNX_META_URL=${_meta_url}
  export NTNX_SOURCE_URL=${_source_url}
}

function prism_check {
  # Argument ${1} = REQUIRED: PE or PC
  # Argument ${2} = OPTIONAL: number of attempts
  # Argument ${3} = OPTIONAL: number of seconds per cycle

  args_required 'ATTEMPTS PE_PASSWORD SLEEP'

  local _attempts=${ATTEMPTS}
  local    _error=77
  local     _host
  local     _loop=0
  local _password="${PE_PASSWORD}"
  local  _pw_init='Nutanix/4u'
  local    _sleep=${SLEEP}
  local     _test=0

  #shellcheck disable=2153
  if [[ ${1} == 'PC' ]]; then
    _host=${PC_HOST}
  else
    _host=${PE_HOST}
  fi
  if [[ ! -z ${2} ]]; then
    _attempts=${2}
  fi

  while true ; do
    (( _loop++ ))
    _test=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${_password} \
      -X POST --data '{ "kind": "cluster" }' \
      https://${_host}:9440/api/nutanix/v3/clusters/list \
      | tr -d \") # wonderful addition of "" around HTTP status code by cURL

    if [[ ! -z ${3} ]]; then
      _sleep=${3}
    fi

    if (( ${_test} == 401 )); then
      log "Warning: unauthorized ${1} user or password."
    fi

    if (( ${_test} == 401 )) && [[ ${1} == 'PC' && ${_password} != "${_pw_init}" ]]; then
      _password=${_pw_init}
      log "Warning @${1}: Fallback on ${_host}: try initial password next cycle..."
      _sleep=0 #break
    fi

    if (( ${_test} == 200 )); then
      log "@${1}: successful."
      return 0
    elif (( ${_loop} > ${_attempts} )); then
      log "Warning ${_error} @${1}: Giving up after ${_loop} tries."
      return ${_error}
    else
      log "@${1} ${_loop}/${_attempts}=${_test}: sleep ${_sleep} seconds..."
      sleep ${_sleep}
    fi
  done
}

function remote_exec() {
# Argument ${1} = REQUIRED: ssh or scp
# Argument ${2} = REQUIRED: PE, PC, or AUTH_SERVER
# Argument ${3} = REQUIRED: command configuration
# Argument ${4} = OPTIONAL: populated with anything = allowed to fail

  local  _account='nutanix'
  local _attempts=3
  local    _error=99
  local     _host
  local     _loop=0
  local _password="${PE_PASSWORD}"
  local   _pw_init='nutanix/4u' # TODO:140 hardcoded p/w
  local    _sleep=${SLEEP}
  local     _test=0

  # shellcheck disable=SC2153
  case ${2} in
    'PE' )
          _host=${PE_HOST}
      ;;
    'PC' )
          _host=${PC_HOST}
      _password=${_pw_init}
      ;;
    'AUTH_SERVER' )
       _account='root'
          _host=${AUTH_HOST}
      _password=${_pw_init}
         _sleep=7
      ;;
  esac

  if [[ -z ${3} ]]; then
    log 'Error ${_error}: missing third argument.'
    exit ${_error}
  fi

  if [[ ! -z ${4} ]]; then
    _attempts=1
       _sleep=0
  fi

  while true ; do
    (( _loop++ ))
    case "${1}" in
      'SSH' | 'ssh')
       #DEBUG=1; if [[ ${DEBUG} ]]; then log "_test will perform ${_account}@${_host} ${3}..."; fi
        SSHPASS="${_password}" sshpass -e ssh -x ${SSH_OPTS} ${_account}@${_host} "${3}"
        _test=$?
        ;;
      'SCP' | 'scp')
        #DEBUG=1; if [[ ${DEBUG} ]]; then log "_test will perform scp ${3} ${_account}@${_host}:"; fi
        SSHPASS="${_password}" sshpass -e scp ${SSH_OPTS} ${3} ${_account}@${_host}:
        _test=$?
        ;;
      *)
        log "Error ${_error}: improper first argument, should be ssh or scp."
        exit ${_error}
        ;;
    esac

    if (( ${_test} > 0 )) && [[ -z ${4} ]]; then
      _error=22
      log "Error ${_error}: pwd=`pwd`, _test=${_test}, _host=${_host}"
      exit ${_error}
    fi

    if (( ${_test} == 0 )); then
      if [[ ${DEBUG} ]]; then log "${3} executed properly."; fi
      return 0
    elif (( ${_loop} == ${_attempts} )); then
      if [[ -z ${4} ]]; then
        _error=11
        log "Error ${_error}: giving up after ${_loop} tries."
        exit ${_error}
      else
        log "Optional: giving up."
        break
      fi
    else
      log "${_loop}/${_attempts}: _test=$?|${_test}| ${FILENAME} SLEEP ${_sleep}..."
      sleep ${_sleep}
    fi
  done
}

function repo_source() {
  # https://stackoverflow.com/questions/1063347/passing-arrays-as-parameters-in-bash#4017175
  local _candidates=("${!1}") # REQUIRED
  local    _package="${2}"    # OPTIONAL
  local      _error=29
  local  _http_code
  local      _index=0
  local     _suffix
  local        _url

  if (( ${#_candidates[@]} == 0 )); then
    log "Error ${_error}: Missing array!"
    exit ${_error}
  # else
  #   log "DEBUG: _candidates count is ${#_candidates[@]}"
  fi

  if [[ -z ${_package} ]]; then
    _suffix=${_candidates[0]##*/}
    if (( $(echo "${_suffix}" | grep . | wc --lines) > 0)); then
      log "Convenience: omitted package argument, added package=${_package}"
      _package="${_suffix}"
    fi
  fi
  # Prepend your local HTTP cache...
  _candidates=( "http://${HTTP_CACHE_HOST}:${HTTP_CACHE_PORT}/" "${_candidates[@]}" )

  while (( ${_index} < ${#_candidates[@]} ))
  do
    unset SOURCE_URL

    # log "DEBUG: ${_index} ${_candidates[${_index}]}, OPTIONAL: _package=${_package}"
    _url=${_candidates[${_index}]}

    if [[ -z ${_package} ]]; then
      if (( $(echo "${_url}" | grep '/$' | wc --lines) == 0 )); then
        log "error ${_error}: ${_url} doesn't end in trailing slash, please correct."
        exit ${_error}
      fi
    elif (( $(echo "${_url}" | grep '/$' | wc --lines) == 1 )); then
      _url+="${_package}"
    fi

    if (( $(echo "${_url}" | grep '^nfs' | wc --lines) == 1 )); then
      log "warning: TODO: cURL can't test nfs URLs...assuming a pass!"
      export SOURCE_URL="${_url}"
      break
    fi

    _http_code=$(curl ${CURL_OPTS} --max-time 5 --write-out '%{http_code}' --head ${_url} | tail -n1)

    if [[ (( ${_http_code} == 200 )) || (( ${_http_code} == 302 )) ]]; then
      export SOURCE_URL="${_url}"
      log "Found, HTTP:${_http_code} = ${SOURCE_URL}"
      break
    fi
    log " Lost, HTTP:${_http_code} = ${_url}"
    ((_index++))
  done

  if [[ -z "${SOURCE_URL}" ]]; then
    _error=30
    log "Error ${_error}: didn't find any sources, last try was ${_url} with HTTP ${_http_code}."
    exit ${_error}
  fi
}

function ssh_pubkey() {
  local   _name=${MY_EMAIL//\./_DOT_}
  local _sshkey=${HOME}/id_rsa.pub

  _name=${_name/@/_AT_}
  if [[ -e ${_sshkey} ]]; then
    log "Note that a period and other symbols aren't allowed to be a key name."
    log "Locally adding ${_sshkey} under ${_name} label..."
    ncli cluster add-public-key name=${_name} file-path=${_sshkey} || true
  fi
}