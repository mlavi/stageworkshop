#!/usr/bin/env bash
# -x
# Dependencies: curl, ncli, nuclei, jq

###############################################################################################################################################################################
# 12th of April 2019 - Willem Essenstam
# Added a "-d" character in the flow_enable so the command would run.
# Changed the Karbon Eanable function so it also checks that Karbon has been enabled. Some small typos changed so the Karbon part should work
#
# 31-05-2019 - Willem Essenstam
# Added the download bits for the Centos Image for Karbon
###############################################################################################################################################################################



###############################################################################################################################################################################
# Routine to enable Flow
###############################################################################################################################################################################

function flow_enable() {
  local _attempts=30
  local _loops=0
  local _sleep=60
  local CURL_HTTP_OPTS=' --max-time 25 --silent --header Content-Type:application/json --header Accept:application/json  --insecure '
  local _url_flow='https://localhost:9440/api/nutanix/v3/services/microseg'

  # Create the JSON payload
  _json_data='{"state":"ENABLE"}'

  log "Enable Nutanix Flow..."

  # Enabling Flow and put the task id in a variable
  _task_id=$(curl -X POST -d $_json_data $CURL_HTTP_OPTS --user ${PRISM_ADMIN}:${PE_PASSWORD} $_url_flow | jq '.task_uuid' | tr -d \")

  # Try one more time then fail, but continue
  if [ -z $_task_id ]; then
    log "Flow not yet enabled. Will retry...."
    _task_id=$(curl -X POST $_json_data $CURL_HTTP_OPTS --user ${PRISM_ADMIN}:${PE_PASSWORD} $_url_flow)

    if [ -z $_task_id ]; then
      log "Flow still not enabled.... ***Not retrying. Please enable via UI.***"
    fi
  else
    log "Flow has been Enabled..."
  fi



}



###############################################################################################################################################################################
# Routine to start the LCM Inventory and the update.
###############################################################################################################################################################################

function lcm() {

  local _url_lcm='https://localhost:9440/PrismGateway/services/rest/v1/genesis'
  local _url_progress='https://localhost:9440/api/nutanix/v3/tasks'
  local _url_groups='https://localhost:9440/api/nutanix/v3/groups'
  local CURL_HTTP_OPTS=' --max-time 25 --silent --header Content-Type:application/json --header Accept:application/json  --insecure '

  # Reset the variables we use so we're not adding extra values to the arrays
  unset uuid_arr
  unset version_ar

  # Inventory download/run
  _task_id=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST -d '{"value":"{\".oid\":\"LifeCycleManager\",\".method\":\"lcm_framework_rpc\",\".kwargs\":{\"method_class\":\"LcmFramework\",\"method\":\"perform_inventory\",\"args\":[\"http://download.nutanix.com/lcm/2.0\"]}}"}' ${_url_lcm} | jq '.value' 2>nul | cut -d "\\" -f 4 | tr -d \")

  # If there has been a reply (task_id) then the URL has accepted by PC
  # Changed (()) to [] so it works....
  if [ -z "$_task_id" ]; then
       log "LCM Inventory start has encountered an eror..."
  else
       log "LCM Inventory started.."
       set _loops=0 # Reset the loop counter so we restart the amount of loops we need to run

       # Run the progess checker
       loop

       #################################################################
       # Grab the json from the possible to be updated UUIDs and versions and save local in reply_json.json
       #################################################################

       # Need loop so we can create the full json more dynamical

       # Issue is taht after the LCM inventory the LCM will be updated to a version 2.0 and the API call needs to change!!!
       # We need to figure out if we are running V1 or V2!
       lcm_version=$(curl $CURL_HTTP_OPTS --user $PRISM_ADMIN:$PE_PASSWORD -X POST -d '{"value":"{\".oid\":\"LifeCycleManager\",\".method\":\"lcm_framework_rpc\",\".kwargs\":{\"method_class\":\"LcmFramework\",\"method\":\"get_config\"}}"}'  ${_url_lcm} | jq '.value' | tr -d \\ | sed 's/^"\(.*\)"$/\1/' | sed 's/.return/return/g' | jq '.return.lcm_cpdb_table_def_list.entity' | tr -d \"| grep "lcm_entity_v2" | wc -l)

       if [ $lcm_version -lt 1 ]; then
              log "LCM Version 1 found.."
              # V1: Run the Curl command and save the oputput in a temp file
              curl $CURL_HTTP_OPTS --user $PRISM_ADMIN:$PE_PASSWORD -X POST -d '{"entity_type": "lcm_available_version","grouping_attribute": "entity_uuid","group_member_count": 1000,"group_member_attributes": [{"attribute": "uuid"},{"attribute": "entity_uuid"},{"attribute": "entity_class"},{"attribute": "status"},{"attribute": "version"},{"attribute": "dependencies"},{"attribute": "order"}]}'  $_url_groups > reply_json.json

              # Fill the uuid array with the correct values
              uuid_arr=($(jq '.group_results[].entity_results[].data[] | select (.name=="entity_uuid") | .values[0].values[0]' reply_json.json | sort -u | tr "\"" " " | tr -s " "))

              # Grabbing the versions of the UUID and put them in a versions array
              for uuid in "${uuid_arr[@]}"
              do
                version_ar+=($(jq --arg uuid "$uuid" '.group_results[].entity_results[] | select (.data[].values[].values[0]==$uuid) | select (.data[].name=="version") | .data[].values[].values[0]' reply_json.json | tail -4 | head -n 1 | tr -d \"))
              done
        else
              log "LCM Version 2 found.."

              #''_V2: run the other V2 API call to get the UUIDs of the to be updated software parts
              # Grab the installed version of the software first UUIDs
              curl $CURL_HTTP_OPTS --user $PRISM_ADMIN:$PE_PASSWORD -X POST -d '{"entity_type": "lcm_entity_v2","group_member_count": 500,"group_member_attributes": [{"attribute": "id"}, {"attribute": "uuid"}, {"attribute": "entity_model"}, {"attribute": "version"}, {"attribute": "location_id"}, {"attribute": "entity_class"}, {"attribute": "description"}, {"attribute": "last_updated_time_usecs"}, {"attribute": "request_version"}, {"attribute": "_master_cluster_uuid_"}, {"attribute": "entity_type"}, {"attribute": "single_group_uuid"}],"query_name": "lcm:EntityGroupModel","grouping_attribute": "location_id","filter_criteria": "entity_model!=AOS;entity_model!=NCC;entity_model!=PC;_master_cluster_uuid_==[no_val]"}' $_url_groups > reply_json_uuid.json

              # Fill the uuid array with the correct values
              uuid_arr=($(jq '.group_results[].entity_results[].data[] | select (.name=="uuid") | .values[0].values[0]' reply_json_uuid.json | sort -u | tr "\"" " " | tr -s " "))

              # Grab the available updates from the PC after LCMm has run
              curl $CURL_HTTP_OPTS --user $PRISM_ADMIN:$PE_PASSWORD -X POST -d '{"entity_type": "lcm_available_version_v2","group_member_count": 500,"group_member_attributes": [{"attribute": "uuid"},{"attribute": "entity_uuid"}, {"attribute": "entity_class"}, {"attribute": "status"}, {"attribute": "version"}, {"attribute": "dependencies"},{"attribute": "single_group_uuid"}, {"attribute": "_master_cluster_uuid_"}, {"attribute": "order"}],"query_name": "lcm:VersionModel","filter_criteria": "_master_cluster_uuid_==[no_val]"}' $_url_groups > reply_json_ver.json

              # Grabbing the versions of the UUID and put them in a versions array
              for uuid in "${uuid_arr[@]}"
                do
                  # Get the latest version from the to be updated uuid
                  version_ar+=($(jq --arg uuid "$uuid" '.group_results[].entity_results[] | select (.data[].values[].values[]==$uuid) .data[] | select (.name=="version") .values[].values[]' reply_json_ver.json | sort |tail -1 | tr -d \"))
                done
              # Copy the right info into the to be used array
        fi

       # Set the parameter to create the ugrade plan
       # Create the curl json string '-d blablablablabla' so we can call the string and not the full json data line
       # Begin of the JSON data payload
       _json_data="-d "
       _json_data+="{\"value\":\"{\\\".oid\\\":\\\"LifeCycleManager\\\",\\\".method\\\":\\\"lcm_framework_rpc\\\",\\\".kwargs\\\":{\\\"method_class\\\":\\\"LcmFramework\\\",\\\"method\\\":\\\"generate_plan\\\",\\\"args\\\":[\\\"http://download.nutanix.com/lcm/2.0\\\",["

       # Combine the two created UUID and Version arrays to the full needed data using a loop
       count=0
       while [ $count -lt ${#uuid_arr[@]} ]
       do
          if [ ! -z ${version_ar[$count]} ]; then
            _json_data+="[\\\"${uuid_arr[$count]}\\\",\\\"${version_ar[$count]}\\\"],"
            log "Found UUID ${uuid_arr[$count]} and version ${version_ar[$count]}"
          fi
          let count=count+1
        done

       # Remove the last "," as we don't need it.
       _json_data=${_json_data%?};

       # Last part of the JSON data payload
       _json_data+="]]}}\"}"

       # Run the generate plan task
       _task_id=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST $_json_data ${_url_lcm})

       # Notify the log server that the LCM has created a plan
       log "LCM Inventory has created a plan"

       # Reset the loop counter so we restart the amount of loops we need to run
       set _loops=0

       # As the new json for the perform the upgrade only needs to have "generate_plan" changed into "perform_update" we use sed...
       _json_data=$(echo $_json_data | sed -e 's/generate_plan/perform_update/g')


       # Run the upgrade to have the latest versions
       _task_id=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST $_json_data ${_url_lcm} | jq '.value' 2>nul | cut -d "\\" -f 4 | tr -d \")

       # If there has been a reply task_id then the URL has accepted by PC
        if [ -z "$_task_id" ]; then
            # There has been an error!!!
            log "LCM Upgrade has encountered an error!!!!"
        else
            # Notify the logserver that we are starting the LCM Upgrade
            log "LCM Upgrade starting...Process may take up to 45 minutes!!!"

            # Run the progess checker
            loop
        fi
  fi

  # Remove the temp json files as we don't need it anymore
       #rm -rf reply_json.json
       #rm -rf reply_json_ver.json
       #rm -rf reply_json_uuid.json

}

###############################################################################################################################################################################
# Routine to enable Karbon
###############################################################################################################################################################################

function karbon_enable() {
  local CURL_HTTP_OPTS=' --max-time 25 --silent --header Content-Type:application/json --header Accept:application/json  --insecure '
  local _loop=0
  local _json_data_set_enable="{\"value\":\"{\\\".oid\\\":\\\"ClusterManager\\\",\\\".method\\\":\\\"enable_service_with_prechecks\\\",\\\".kwargs\\\":{\\\"service_list_json\\\":\\\"{\\\\\\\"service_list\\\\\\\":[\\\\\\\"KarbonUIService\\\\\\\",\\\\\\\"KarbonCoreService\\\\\\\"]}\\\"}}\"}"
  local _json_is_enable="{\"value\":\"{\\\".oid\\\":\\\"ClusterManager\\\",\\\".method\\\":\\\"is_service_enabled\\\",\\\".kwargs\\\":{\\\"service_name\\\":\\\"KarbonUIService\\\"}}\"} "
  local _httpURL="https://localhost:9440/PrismGateway/services/rest/v1/genesis"

  # Start the enablement process
  _response=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST -d $_json_data_set_enable ${_httpURL}| grep "[true, null]" | wc -l)

  # Check if we got a "1" back (start sequence received). If not, retry. If yes, check if enabled...
  if [[ $_response -eq 1 ]]; then
    # Check if Karbon has been enabled
    _response=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST -d $_json_is_enable ${_httpURL}| grep "[true, null]" | wc -l)
    while [ $_response -ne 1 ]; do
        _response=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST -d $_json_is_enable ${_httpURL}| grep "[true, null]" | wc -l)
    done
    log "Karbon has been enabled."
  else
    log "Retrying to enable Karbon one more time."
    _response=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST -d $_json_data_set_enable ${_httpURL}| grep "[true, null]" | wc -l)
    if [[ $_response -eq 1 ]]; then
      _response=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST -d $_json_is_enable ${_httpURL}| grep "[true, null]" | wc -l)
      if [ $_response -lt 1 ]; then
        log "Karbon isn't enabled. Please use the UI to enable it."
      else
        log "Karbon has been enabled."
      fi
    fi
  fi
}

###############################################################################################################################################################################
# Download Karbon CentOS Image
###############################################################################################################################################################################

function karbon_image_download() {
  local CURL_HTTP_OPTS=' --max-time 25 --silent --header Content-Type:application/json --header Accept:application/json  --insecure '
  local _loop=0
  local _startDownload="https://localhost:7050/acs/image/download"
  local _getuuidDownload="https://localhost:7050/acs/image/list"

  # Create the Basic Authentication using base6 commands
  _auth=$(echo "admin:${PE_PASSWORD}" | base64)

  # Call the UUID URL so we have the right UUID for the image
  uuid=$(curl -X GET -H "X-NTNX-AUTH: Basic ${_auth}" https://localhost:7050/acs/image/list $CURL_HTTP_OPTS | jq '.[0].uuid' | tr -d \/\")
  log "UUID for The Karbon image is: $uuid"

  # Use the UUID to download the image
  response=$(curl -X POST ${_startDownload} -d "{\"uuid\":\"${uuid}\"}" -H "X-NTNX-AUTH: Basic ${_auth}" ${CURL_HTTP_OPTS})

  if [ -z $response ]; then
    log "Download of the CenOS image for Karbon has not been started. Trying one more time..."
    response=$(curl -X POST ${_startDownload} -d "{\"uuid\":\"${uuid}\"}" -H "X-NTNX-AUTH: Basic ${_auth}" ${CURL_HTTP_OPTS})
    if [ -z $response ]; then
      log "Download of CentOS image for Karbon failed... Please run manually."
    fi
  else
    log "Download of CentOS image for Karbon has started..."
  fi
}

###############################################################################################################################################################################
# Routine to enable Objects
###############################################################################################################################################################################

function objects_enable() {
  local CURL_HTTP_OPTS=' --max-time 25 --silent --header Content-Type:application/json --header Accept:application/json  --insecure '
  local _loops=0
  local _json_data_set_enable="{\"state\":\"ENABLE\"}"
  local _json_data_check="{\"entity_type\":\"objectstore\"}"
  local _httpURL_check="https://localhost:9440/oss/api/nutanix/v3/groups"
  local _httpURL="https://localhost:9440/api/nutanix/v3/services/oss"

  # Start the enablement process
  _response=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST -d $_json_data_set_enable ${_httpURL})
  log "Enabling Objects....."

  # The response should be a Task UUID
  if [[ ! -z $_response ]]; then
    # Check if OSS has been enabled
    _response=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST -d $_json_data_check ${_httpURL_check}| grep "objectstore" | wc -l)
    while [ $_response -ne 1 ]; do
        _response=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST -d $_json_data_check ${_httpURL_check}| grep "objectstore" | wc -l)
        if [[ $loops -ne 30 ]]; then
          sleep 10
          (( _loops++ ))
        else
          log "Objects isn't enabled. Please use the UI to enable it."
          break
        fi
    done
    log "Objects has been enabled."
  else
    log "Objects isn't enabled. Please use the UI to enable it."
  fi
}

###############################################################################################################################################################################
# Create an object store called ntnx_object.ntnxlab.local
###############################################################################################################################################################################

function object_store() {
    local _attempts=30
    local _loops=0
    local _sleep=60
    local CURL_HTTP_OPTS=' --max-time 25 --silent --header Content-Type:application/json --header Accept:application/json  --insecure '
    local _url_network='https://localhost:9440/api/nutanix/v3/subnets/list'
    local _url_oss='https://localhost:9440/oss/api/nutanix/v3/objectstores'
    local _url_oss_check='https://localhost:9440/oss/api/nutanix/v3/objectstores/list'


    # Payload for the _json_data
    _json_data='{"kind":"subnet"}'

    # Get the json data and split into CLUSTER_UUID and Primary_Network_UUID
    CLUSTER_UUID=$(curl -X POST -d $_json_data $CURL_HTTP_OPTS --user ${PRISM_ADMIN}:${PE_PASSWORD} $_url_network | jq '.entities[].spec | select (.name=="Primary") | .cluster_reference.uuid' | tr -d \")
    echo ${CLUSTER_UUID}

    PRIM_NETWORK_UUID=$(curl -X POST -d $_json_data $CURL_HTTP_OPTS --user ${PRISM_ADMIN}:${PE_PASSWORD} $_url_network | jq '.entities[] | select (.spec.name=="Primary") | .metadata.uuid' | tr -d \")
    echo ${PRIM_NETWORK_UUID}

    echo "BUCKETS_DNS_IP: ${BUCKETS_DNS_IP}, BUCKETS_VIP: ${BUCKETS_VIP}, OBJECTS_NW_START: ${OBJECTS_NW_START}, OBJECTS_NW_END: ${OBJECTS_NW_END}"
    sleep 5
    _json_data_oss='{"api_version":"3.0","metadata":{"kind":"objectstore"},"spec":{"name":"ntnx-objects","description":"NTNXLAB","resources":{"domain":"ntnxlab.local","cluster_reference":{"kind":"cluster","uuid":"'
    _json_data_oss+=${CLUSTER_UUID}
    _json_data_oss+='"},"buckets_infra_network_dns":"'
    _json_data_oss+=${BUCKETS_DNS_IP}
    _json_data_oss+='","buckets_infra_network_vip":"'
    _json_data_oss+=${BUCKETS_VIP}
    _json_data_oss+='","buckets_infra_network_reference":{"kind":"subnet","uuid":"'
    _json_data_oss+=${PRIM_NETWORK_UUID}
    _json_data_oss+='"},"client_access_network_reference":{"kind":"subnet","uuid":"'
    _json_data_oss+=${PRIM_NETWORK_UUID}
    _json_data_oss+='"},"aggregate_resources":{"total_vcpu_count":10,"total_memory_size_mib":32768,"total_capacity_gib":51200},"client_access_network_ipv4_range":{"ipv4_start":"'
    _json_data_oss+=${OBJECTS_NW_START}
    _json_data_oss+='","ipv4_end":"'
    _json_data_oss+=${OBJECTS_NW_END}
    _json_data_oss+='"}}}}'

    # Set the right VLAN dynamically so we are configuring in the right network
    _json_data_oss=${_json_data_oss//VLANX/${VLAN}}
    _json_data_oss=${_json_data_oss//NETWORKX/${NETWORK}}

    #curl -X POST -d $_json_data_oss $CURL_HTTP_OPTS --user ${PRISM_ADMIN}:${PE_PASSWORD} $_url_oss
     _createresponse=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST -d $_json_data_oss ${_url_oss})
      log "Creating Object Store....."

  # The response should be a Task UUID
  if [[ ! -z $_createresponse ]]; then
    # Check if Object store is deployed
    _response=$(curl ${CURL_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X GET ${_url_oss_check}| grep "ntnx-objects" | wc -l)
    while [ $_response -ne 1 ]; do
        log "Object Store not yet created. $_loops/$_attempts... sleeping 10 seconds"
        _response=$(curl ${CURL_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X GET ${_url_oss_check}| grep "ntnx-objects" | wc -l)
        if [[ $_loops -ne 30 ]]; then
          _createresponse=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST -d $_json_data_oss ${_url_oss})
          sleep 10
          (( _loops++ ))
        else
          log "Objects store ntnx-objects not created. Please use the UI to create it."
          break
        fi
    done
    log "Objects store been created."
  else
    log "Objects store could not be created. Please use the UI to create it."
  fi

}


###############################################################################################################################################################################
# Routine for PC_Admin
###############################################################################################################################################################################

function pc_admin() {
  local  _http_body
  local       _test
  local _admin_user='nathan'

  _http_body=$(cat <<EOF
  {"profile":{
    "username":"${_admin_user}",
    "firstName":"Nathan",
    "lastName":"Cox",
    "emailId":"${EMAIL}",
    "password":"${PE_PASSWORD}",
    "locale":"en-US"},"enabled":false,"roles":[]}
EOF
  )
  _test=$(curl ${CURL_HTTP_OPTS} \
    --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST --data "${_http_body}" \
    https://localhost:9440/PrismGateway/services/rest/v1/users)
  log "create.user=${_admin_user}=|${_test}|"

  _http_body='["ROLE_USER_ADMIN","ROLE_MULTICLUSTER_ADMIN"]'
       _test=$(curl ${CURL_HTTP_OPTS} \
    --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST --data "${_http_body}" \
    https://localhost:9440/PrismGateway/services/rest/v1/users/${_admin_user}/roles)
  log "add.roles ${_http_body}=|${_test}|"
}

###############################################################################################################################################################################
# Routine set PC authentication to use the AD as well
###############################################################################################################################################################################
function pc_auth() {
  # TODO:190 configure case for each authentication server type?
  local      _group
  local  _http_body
  local _pc_version
  local       _test

  # TODO:50 FUTURE: pass AUTH_SERVER argument

  log "Add Directory ${AUTH_SERVER}"
  _http_body=$(cat <<EOF
{"name":"${AUTH_SERVER}","domain":"${AUTH_FQDN}","directoryType":"ACTIVE_DIRECTORY","connectionType":"LDAP",
EOF
  )

  # shellcheck disable=2206
  _pc_version=(${PC_VERSION//./ })

  log "Checking if PC_VERSION ${PC_VERSION} >= 5.9"
  if (( ${_pc_version[0]} >= 5 && ${_pc_version[1]} >= 9 )); then
    _http_body+=$(cat <<EOF
"groupSearchType":"RECURSIVE","directoryUrl":"ldap://${AUTH_HOST}:${LDAP_PORT}",
EOF
)
  else
    _http_body+=" \"directoryUrl\":\"ldaps://${AUTH_HOST}/\","
  fi

  _http_body+=$(cat <<EOF
    "serviceAccountUsername":"${AUTH_ADMIN_USER}",
    "serviceAccountPassword":"${AUTH_ADMIN_PASS}"
  }
EOF
  )

  _test=$(curl ${CURL_POST_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST --data "${_http_body}" \
    https://localhost:9440/PrismGateway/services/rest/v1/authconfig/directories)
  log "directories: _test=|${_test}|_http_body=|${_http_body}|"

  log "Add Role Mappings to Groups for PC logins (not projects, which are separate)..."
  #TODO:20 hardcoded role mappings
  for _group in 'SSP Admins' 'SSP Power Users' 'SSP Developers' 'SSP Basic Users'; do
    _http_body=$(cat <<EOF
    {
      "directoryName":"${AUTH_SERVER}",
      "role":"ROLE_CLUSTER_ADMIN",
      "entityType":"GROUP",
      "entityValues":["${_group}"]
    }
EOF
    )
    _test=$(curl ${CURL_POST_OPTS} \
      --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST --data "${_http_body}" \
      https://localhost:9440/PrismGateway/services/rest/v1/authconfig/directories/${AUTH_SERVER}/role_mappings)
    log "Cluster Admin=${_group}, _test=|${_test}|"
  done
}

###############################################################################################################################################################################
# Routine to import the images into PC
###############################################################################################################################################################################

function pc_cluster_img_import() {
  local _http_body
  local      _test
  local      _uuid

       _uuid=$(source /etc/profile.d/nutanix_env.sh \
              && ncli --json=true cluster info \
              | jq -r .data.uuid)
  _http_body=$(cat <<EOF
{"action_on_failure":"CONTINUE",
 "execution_order":"SEQUENTIAL",
 "api_request_list":[{
   "operation":"POST",
   "path_and_params":"/api/nutanix/v3/images/migrate",
   "body":{
     "image_reference_list":[],
     "cluster_reference":{
       "uuid":"${_uuid}",
       "kind":"cluster",
       "name":"string"}}}],
 "api_version":"3.0"}
EOF
  )
  _test=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST --data "${_http_body}" \
    https://localhost:9440/api/nutanix/v3/batch)
  log "batch _test=|${_test}|"
}

###############################################################################################################################################################################
# Routine to add dns servers
###############################################################################################################################################################################

function pc_dns_add() {
  local _dns_server
  local       _test

  for _dns_server in $(echo "${DNS_SERVERS}" | sed -e 's/,/ /'); do
    _test=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST --data "[\"$_dns_server\"]" \
      https://localhost:9440/PrismGateway/services/rest/v1/cluster/name_servers/add_list)
    log "name_servers/add_list |${_dns_server}| _test=|${_test}|"
  done
}

###############################################################################################################################################################################
# Routine to setup the initial steps for PC; NTP, EULA and Pulse
###############################################################################################################################################################################

function pc_init() {
  # TODO:130 pc_init: NCLI, type 'cluster get-smtp-server' config for idempotency?
  local _test

  log "Configure NTP@PC"
  ncli cluster add-to-ntp-servers \
    servers=0.us.pool.ntp.org,1.us.pool.ntp.org,2.us.pool.ntp.org,3.us.pool.ntp.org

  log "Validate EULA@PC"
  _test=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST -d '{
      "username": "SE",
      "companyName": "NTNX",
      "jobTitle": "SE"
  }' https://localhost:9440/PrismGateway/services/rest/v1/eulas/accept)
  log "EULA _test=|${_test}|"

  log "Disable Pulse@PC"
  _test=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X PUT -d '{
      "emailContactList":null,
      "enable":false,
      "verbosityType":null,
      "enableDefaultNutanixEmail":false,
      "defaultNutanixEmail":null,
      "nosVersion":null,
      "isPulsePromptNeeded":false,
      "remindLater":null
  }' https://localhost:9440/PrismGateway/services/rest/v1/pulse)
  log "PULSE _test=|${_test}|"
}

###############################################################################################################################################################################
# Routine to setup the SMTP server in PC
###############################################################################################################################################################################

function pc_smtp() {
  log "Configure SMTP@PC"
  local _sleep=5

  args_required 'SMTP_SERVER_ADDRESS SMTP_SERVER_FROM SMTP_SERVER_PORT'
  ncli cluster set-smtp-server port=${SMTP_SERVER_PORT} \
    address=${SMTP_SERVER_ADDRESS} from-email-address=${SMTP_SERVER_FROM}
  #log "sleep ${_sleep}..."; sleep ${_sleep}
  #log $(ncli cluster get-smtp-server | grep Status | grep success)

  # shellcheck disable=2153
  ncli cluster send-test-email recipient="${EMAIL}" \
    subject="pc_smtp https://${PRISM_ADMIN}:${PE_PASSWORD}@${PC_HOST}:9440 Testing."
  # local _test=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST -d '{
  #   "address":"${SMTP_SERVER_ADDRESS}","port":"${SMTP_SERVER_PORT}","username":null,"password":null,"secureMode":"NONE","fromEmailAddress":"${SMTP_SERVER_FROM}","emailStatus":null}' \
  #   https://localhost:9440/PrismGateway/services/rest/v1/cluster/smtp)
  # log "_test=|${_test}|"
}

###############################################################################################################################################################################
# Routine to change the PC admin password
###############################################################################################################################################################################

function pc_passwd() {
  args_required 'PRISM_ADMIN PE_PASSWORD'

  log "Reset PC password to PE password, must be done by ncli@PC, not API or on PE"
  ncli user reset-password user-name=${PRISM_ADMIN} password=${PE_PASSWORD}
  if (( $? > 0 )); then
   log "Warning: password not reset: $?."# exit 10
  fi
  # TOFIX: nutanix@PC Linux account password change as well?

  # local _old_pw='nutanix/4u'
  # local _http_body=$(cat <<EOF
  # {"oldPassword": "${_old_pw}","newPassword": "${PE_PASSWORD}"}
  # EOF
  # )
  # local _test
  # _test=$(curl ${CURL_HTTP_OPTS} --user "${PRISM_ADMIN}:${_old_pw}" -X POST --data "${_http_body}" \
  #     https://localhost:9440/PrismGateway/services/rest/v1/utils/change_default_system_password)
  # log "cURL reset password _test=${_test}"
}




###############################################################################################################################################################################
# Seed PC data for Prism Pro Labs
###############################################################################################################################################################################

function seedPC() {
    local _test
    local _setup

    _test=$(curl -L ${PC_DATA} -o /home/nutanix/${SeedPC})
    log "Pulling Prism Data| PC_DATA ${PC_DATA}|${_test}"
    unzip /home/nutanix/${SeedPC}
    pushd /home/nutanix/lab/

    #_setup=$(/home/nutanix/lab/setupEnv.sh ${PC_HOST} > /dev/null 2>&1)
    _setup=$(/home/nutanix/lab/initialize_lab.sh ${PC_HOST} > /dev/null 2>&1)
    log "Running Setup Script|$_setup"

    popd
}

###############################################################################################################################################################################
# Routine to setp up the SSP authentication to use the AutoDC server
###############################################################################################################################################################################

function ssp_auth() {
  args_required 'AUTH_SERVER AUTH_HOST AUTH_ADMIN_USER AUTH_ADMIN_PASS'

  local   _http_body
  local   _ldap_name
  local   _ldap_uuid
  local _ssp_connect

  log "Find ${AUTH_SERVER} uuid"
  _ldap_uuid=$(PATH=${PATH}:${HOME}; curl ${CURL_POST_OPTS} \
    --user ${PRISM_ADMIN}:${PE_PASSWORD} --data '{ "kind": "directory_service" }' \
    https://localhost:9440/api/nutanix/v3/directory_services/list \
    | jq -r .entities[0].metadata.uuid)
  log "_ldap_uuid=|${_ldap_uuid}|"

  # TODO:110 get directory service name _ldap_name
  _ldap_name=${AUTH_SERVER}
  # TODO:140 bats? test ldap connection

  log "Connect SSP Authentication (spec-ssp-authrole.json)..."
  _http_body=$(cat <<EOF
  {
    "spec": {
      "name": "${AUTH_SERVER}",
      "resources": {
        "admin_group_reference_list": [
          {
            "name": "cn=ssp developers,cn=users,dc=ntnxlab,dc=local",
            "uuid": "3933a846-fe73-4387-bb39-7d66f222c844",
            "kind": "user_group"
          }
        ],
        "service_account": {
          "username": "${AUTH_ADMIN_USER}",
          "password": "${AUTH_ADMIN_PASS}"
        },
        "url": "ldaps://${AUTH_HOST}/",
        "directory_type": "ACTIVE_DIRECTORY",
        "admin_user_reference_list": [],
        "domain_name": "${AUTH_DOMAIN}"
      }
    },
    "metadata": {
      "kind": "directory_service",
      "spec_version": 0,
      "uuid": "${_ldap_uuid}",
      "categories": {}
    },
    "api_version": "3.1.0"
  }
EOF
  )
  _ssp_connect=$(curl ${CURL_POST_OPTS} \
    --user ${PRISM_ADMIN}:${PE_PASSWORD} -X PUT --data "${_http_body}" \
    https://localhost:9440/api/nutanix/v3/directory_services/${_ldap_uuid})
  log "_ssp_connect=|${_ssp_connect}|"

  # TODO:120 SSP Admin assignment, cluster, networks (default project?) = spec-project-config.json
  # PUT https://localhost:9440/api/nutanix/v3/directory_services/9d8c2c33-9d95-438c-a7f4-2187120ae99e = spec-ssp-direcory_service.json
  # TODO:60 FUTURE: use directory_type variable?
  log "Enable SSP Admin Authentication (spec-ssp-direcory_service.json)..."
  _http_body=$(cat <<EOF
  {
    "spec": {
      "name": "${_ldap_name}",
      "resources": {
        "service_account": {
          "username": "${AUTH_ADMIN_USER}@${AUTH_FQDN}",
          "password": "${AUTH_ADMIN_PASS}"
        },
        "url": "ldaps://${AUTH_HOST}/",
        "directory_type": "ACTIVE_DIRECTORY",
        "domain_name": "${AUTH_DOMAIN}"
      }
    },
    "metadata": {
      "kind": "directory_service",
      "spec_version": 0,
      "uuid": "${_ldap_uuid}",
      "categories": {}
    },
    "api_version": "3.1.0"
  }
EOF
  )
  _ssp_connect=$(curl ${CURL_POST_OPTS} \
    --user ${PRISM_ADMIN}:${PE_PASSWORD} -X PUT --data "${_http_body}" \
    https://localhost:9440/api/nutanix/v3/directory_services/${_ldap_uuid})
  log "_ssp_connect=|${_ssp_connect}|"
  # POST https://localhost:9440/api/nutanix/v3/groups = spec-ssp-groups.json
  # TODO:100 can we skip previous step?
  log "Enable SSP Admin Authentication (spec-ssp-groupauth_2.json)..."
  _http_body=$(cat <<EOF
  {
    "spec": {
      "name": "${_ldap_name}",
      "resources": {
        "service_account": {
          "username": "${AUTH_ADMIN_USER}@${AUTH_DOMAIN}",
          "password": "${AUTH_ADMIN_PASS}"
        },
        "url": "ldaps://${AUTH_HOST}/",
        "directory_type": "ACTIVE_DIRECTORY",
        "domain_name": "${AUTH_DOMAIN}"
        "admin_user_reference_list": [],
        "admin_group_reference_list": [
          {
            "kind": "user_group",
            "name": "cn=ssp admins,cn=users,dc=ntnxlab,dc=local",
            "uuid": "45d495e1-b797-4a26-a45b-0ef589b42186"
          }
        ]
      }
    },
    "api_version": "3.1",
    "metadata": {
      "last_update_time": "2018-09-14T13:02:55Z",
      "kind": "directory_service",
      "uuid": "${_ldap_uuid}",
      "creation_time": "2018-09-14T13:02:55Z",
      "spec_version": 2,
      "owner_reference": {
        "kind": "user",
        "name": "admin",
        "uuid": "00000000-0000-0000-0000-000000000000"
      },
      "categories": {}
    }
  }
EOF
    )
    _ssp_connect=$(curl ${CURL_POST_OPTS} \
      --user ${PRISM_ADMIN}:${PE_PASSWORD} -X PUT --data "${_http_body}" \
      https://localhost:9440/api/nutanix/v3/directory_services/${_ldap_uuid})
    log "_ssp_connect=|${_ssp_connect}|"

}

###############################################################################################################################################################################
# Routine to enable Calm and proceed only if Calm is enabled
###############################################################################################################################################################################

function calm_enable() {
  local _http_body
  local _test
  local _sleep=30
  local CURL_HTTP_OPTS=' --max-time 25 --silent --header Content-Type:application/json --header Accept:application/json  --insecure '

  log "Enable Nutanix Calm..."
  # Need to check if the PE to PC registration has been done before we move forward to enable Calm. If we've done that, move on.
  _json_data="{\"perform_validation_only\":true}"
  _response=($(curl $CURL_HTTP_OPTS --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST -d "${_json_data}" https://localhost:9440/api/nutanix/v3/services/nucalm | jq '.validation_result_list[].has_passed'))
  while [ ${#_response[@]} -lt 4 ]; do
    _response=($(curl $CURL_HTTP_OPTS --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST -d "${_json_data}" https://localhost:9440/api/nutanix/v3/services/nucalm | jq '.validation_result_list[].has_passed'))
    sleep 10
  done


  _http_body='{"enable_nutanix_apps":true,"state":"ENABLE"}'
  _test=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST -d "${_http_body}" https://localhost:9440/api/nutanix/v3/services/nucalm)

  # Sometimes the enabling of Calm is stuck due to an internal error. Need to retry then.
  _error_calm=$(echo $_test | grep "\"state\": \"ERROR\"" | wc -l)
  while [ $_error_calm -gt 0 ]; do
      _test=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST -d "${_http_body}" https://localhost:9440/api/nutanix/v3/services/nucalm)
      _error_calm=$(echo $_test | grep "\"state\": \"ERROR\"" | wc -l)
  done

  log "_test=|${_test}|"

  # Check if Calm is enabled
  while true; do
    # Get the progress of the task
    _progress=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} https://localhost:9440/api/nutanix/v3/services/nucalm/status | jq '.service_enablement_status' 2>nul | tr -d \")
    if [[ ${_progress} == "ENABLED" ]]; then
      log "Calm has been Enabled..."
      break;
    else
      log "Still enabling Calm.....Sleeping ${_sleep} seconds"
      sleep ${_sleep}
    fi
  done
}

###############################################################################################################################################################################
# Routine to upload Citrix Calm Blueprint and set variables
###############################################################################################################################################################################

function upload_citrix_calm_blueprint() {
  local DIRECTORY="/home/nutanix/"
  local CALM_PROJECT="BootcampInfra"
  local DOMAIN=${AUTH_FQDN}
  local AD_IP=${AUTH_HOST}
  local PE_IP=${PE_HOST}
  local NutanixAcropolisPlugin="none"
  local CVM_NETWORK=${NW1_NAME}
  local BPG_RKTOOLS_URL="none"
  local DDC_IP=${CITRIX_DDC_HOST}
  local NutanixAcropolis_Installed_Path="none"

  local VLAN_NAME=${NW1_VLAN}
  local DOWNLOAD_BLUEPRINTS

  # download the blueprint
  DOWNLOAD_BLUEPRINTS=$(curl -L ${BLUEPRINT_URL}${CALM_Blueprint} -o ${DIRECTORY}${CALM_Blueprint})
  log "Downloading ${CALM_Blueprint} | BLUEPRINT_URL ${BLUEPRINT_URL}|${DOWNLOAD_BLUEPRINTS}"

  # ensure the directory that contains the blueprints to be imported is not empty
  if [[ $(ls -l "$DIRECTORY"/*.json) == *"No such file or directory"* ]]; then
      echo "There are no .json files found in the directory provided."
      exit 0
  fi

  # create a list to store all bluprints found in the directory provided by user
  declare -a LIST_OF_BLUEPRINTS=()

  # circle thru all of the files in the provided directory and add file names to a list of blueprints array
  # IMPORTANT NOTE: THE FILES NAMES FOR THE JSON FILES BEING IMPORTED CAN'T HAVE ANY SPACES (IN THIS SCRIPT)
  for FILE in "$DIRECTORY"/*.json; do
      BASENAM="$(basename ${FILE})"
      FILENAME="${BASENAM%.*}"
      LIST_OF_BLUEPRINTS+=("$BASENAM")
  done

  # echo $LIST_OF_BLUEPRINTS
  # if the list of blueprints is not empty then:
  if ((${#LIST_OF_BLUEPRINTS[@]})); then
      #   first check if the user has specified a project for the imported blueprints
      #   if they did, we need to make sure the project exists before assigning it to the BPs

      if [ $CALM_PROJECT != 'none' ]; then

          # curl command needed:
          # curl -s -k -X POST https://10.42.7.39:9440/api/nutanix/v3/projects/list -H 'Content-Type: application/json' --user admin:techX2019! -d '{"kind": "project", "filter": "name==default"}' | jq -r '.entities[].metadata.uuid'

          # formulate the curl to check for project
          _url_pc="https://localhost:9440/api/nutanix/v3/projects/list"

          # make API call and store project_uuid
          project_uuid=$(curl -s -k -X POST $_url_pc -H 'Content-Type: application/json' --user ${PRISM_ADMIN}:${PE_PASSWORD} -d "{\"kind\": \"project\", \"filter\": \"name==$CALM_PROJECT\"}" | jq -r '.entities[].metadata.uuid')

          if [ -z "$project_uuid" ]; then
              # project wasn't found
              # exit at this point as we don't want to assume all blueprints should then hit the 'default' project
              echo "\nProject $CALM_PROJECT was not found. Please check the name and retry."
              exit 0
          else
              echo "\nProject $CALM_PROJECT exists..."
          fi
      fi
  else
      echo '\nNo JSON files found in' + $DIRECTORY +' ... nothing to import!'
  fi

  # update the user with script progress...
  _num_of_files=${#LIST_OF_BLUEPRINTS[@]}
  echo "\nNumber of .json files found: ${_num_of_files}"
  echo "\nStarting blueprint updates and then exporting to Calm one file at a time...\n\n"

  # go through the blueprint JSON files list found in the specified directory
  for elem in "${LIST_OF_BLUEPRINTS[@]}"; do
      # read the entire JSON file from the directory
      JSONFile=${DIRECTORY}/"$elem"

      echo "\nCurrently updating blueprint $JSONFile..."

      # NOTE: bash doesn't do in place editing so we need to use a temp file and overwrite the old file with new changes for every blueprint
      tmp=$(mktemp)

      # ADD PROJECT (affects all BPs being imported) if no project was specified on the command line, we've already pre-set the project variable to 'none' if a project was specified, we need to add it into the JSON data
      if [ $CALM_PROJECT != 'none' ]; then
          # add the new atributes to the JSON and overwrite the old JSON file with the new one
          $(jq --arg proj $CALM_PROJECT --arg proj_uuid $project_uuid '.metadata+={"project_reference":{"kind":$proj,"uuid":$proj_uuid}}' $JSONFile >"$tmp" && mv "$tmp" $JSONFile)
      fi

      # ADD VARIABLES (affects ONLY if the current blueprint being imported MATCHES the name specified earlier "EraServerDeployment.json")
      if [ "$elem" == "${NAME}" ]; then
          if [ "$DOMAIN" != "none" ]; then
              tmp_DOMAIN=$(mktemp)
              # add the new variable to the json file and save it
              $(jq --arg var_name $DOMAIN'(.spec.resources.service_definition_list[0].variable_list[] | select (.name=="DOMAIN")).value=$var_name' $JSONFile >"$tmp_DOMAIN" && mv "$tmp_DOMAIN" $JSONFile)
          fi
          if [ "$AD_IP" != "none" ]; then
              tmp_AD_IP=$(mktemp)
              $(jq --arg var_name $AD_IP '(.spec.resources.service_definition_list[0].variable_list[] | select (.name=="AD_IP")).value=$var_name' $JSONFile >"$tmp_AD_IP" && mv "$tmp_AD_IP" $JSONFile)
          fi
          if [ "$PE_IP" != "none" ]; then
              tmp_PE_IP=$(mktemp)
              $(jq --arg var_name $PE_IP'(.spec.resources.service_definition_list[0].variable_list[] | select (.name=="PE_IP")).value=$var_name' $JSONFile >"$tmp_PE_IP" && mv "$tmp_PE_IP" $JSONFile)
          fi
          if [ "$NutanixAcropolisPlugin" != "none" ]; then
              tmp_NutanixAcropolisPluginE=$(mktemp)
              $(jq --arg var_name $NutanixAcropolisPlugin '(.spec.resources.service_definition_list[0].variable_list[] | select (.name=="NutanixAcropolisPlugin")).value=$var_name' $JSONFile >"$tmp_NutanixAcropolisPlugin" && mv "$tmp_NutanixAcropolisPlugin" $JSONFile)
          fi
          if [ "$CVM_NETWORK" != "none" ]; then
              tmp_CVM_NETWORK=$(mktemp)
              $(jq --arg var_name $CVM_NETWORK '(.spec.resources.service_definition_list[0].variable_list[] | select (.name=="CVM_NETWORK")).value=$var_name' $JSONFile >"$tmp_CVM_NETWORK" && mv "$tmp_CVM_NETWORK" $JSONFile)
          fi
          if [ "$BPG_RKTOOLS_URL" != "none" ]; then
              tmp_BPG_RKTOOLS_URL=$(mktemp)
              $(jq --arg var_name $VLAN_NAME '(.spec.resources.service_definition_list[0].variable_list[] | select (.name=="BPG_RKTOOLS_URL")).value=$var_name' $JSONFile >"$tmp_BPG_RKTOOLS_URL" && mv "$tmp_BPG_RKTOOLS_URL" $JSONFile)
          fi
          if [ "$DDC_IP" != "none" ]; then
              tmp_DDC_IP=$(mktemp)
              $(jq --arg var_name $DDC_IP '(.spec.resources.service_definition_list[0].variable_list[] | select (.name=="DDC_IP")).value=$var_name' $JSONFile >"$tmp_DDC_IP" && mv "$tmp_DDC_IP" $JSONFile)
          fi
          if [ "$NutanixAcropolis_Installed_Path" != "none" ]; then
              tmp_NutanixAcropolis_Installed_Path=$(mktemp)
              $(jq --arg var_name $NutanixAcropolis_Installed_Path '(.spec.resources.service_definition_list[0].variable_list[] | select (.name=="NutanixAcropolis_Installed_PathL")).value=$var_name' $JSONFile >"$tmp_NutanixAcropolis_Installed_Path" && mv "$tmp_NutanixAcropolis_Installed_Path" $JSONFile)
          fi
      fi

      # REMOVE the "status" and "product_version" keys (if they exist) from the JSON data this is included on export but is invalid on import. (affects all BPs being imported)
      tmp_removal=$(mktemp)
      $(jq 'del(.status) | del(.product_version)' $JSONFile >"$tmp_removal" && mv "$tmp_removal" $JSONFile)

      # GET BP NAME (affects all BPs being imported)
      # if this fails, it's either a corrupt/damaged/edited blueprint JSON file or not a blueprint file at all
      blueprint_name_quotes=$(jq '(.spec.name)' $JSONFile)
      blueprint_name="${blueprint_name_quotes%\"}" # remove the suffix "
      blueprint_name="${blueprint_name#\"}" # will remove the prefix "

      if [ blueprint_name == 'null' ]; then
          echo "\nUnprocessable JSON file found. Is this definitely a Nutanix Calm blueprint file?\n"
          exit 0
      else
          # got the blueprint name means it is probably a valid blueprint file, we can now continue the upload
          echo "\nUploading the updated blueprint: $blueprint_name...\n"

          # Example curl call from the console:
          # url="https://10.42.7.39:9440/api/nutanix/v3/blueprints/import_file"
          # path_to_file="/Users/sharon.santana/Desktop/saved_blueprints/EraServerDeployment.json"
          # bp_name="EraServerDeployment"
          # project_uuid="a944258a-fd8a-4d02-8646-72c311e03747"
          # password='techX2019!'
          # curl -s -k -X POST $url -F file=@$path_to_file -F name=$bp_name -F project_uuid=$project_uuid --user admin:"$password"

          url="https://localhost:9440/api/nutanix/v3/blueprints/import_file"
          path_to_file=$JSONFile
          bp_name=$blueprint_name
          project_uuid=$project_uuid
          password=$PE_PASSWORD
          upload_result=$(curl -s -k -X POST $url -F file=@$path_to_file -F name=$bp_name -F project_uuid=$project_uuid --user admin:"$password")

          #if the upload_result var is not empty then let's say it was succcessful
          if [ -z "$upload_result" ]; then
              echo "\nUpload for $bp_name did not finish."
          else
              echo "\nUpload for $bp_name finished."
              echo "-----------------------------------------"
              # echo "Result: $upload_result"
          fi
      fi

    done

    echo "\nFinished uploading Citrix Blueprint and setting Variables!\n"

}

###############################################################################################################################################################################
# Routine to upload Era Calm Blueprint and set variables
###############################################################################################################################################################################

function upload_era_calm_blueprint() {
  local DIRECTORY="/home/nutanix/"
  local CALM_PROJECT="BootcampInfra"
  local ERA_IP=${ERA_HOST}
  local PE_IP=${PE_HOST}
  local CLSTR_NAME="none"
  local CTR_UUID=${_storage_default_uuid}
  local CTR_NAME=${STORAGE_DEFAULT}
  local NETWORK_NAME=${NW1_NAME}
  local VLAN_NAME=${NW1_VLAN}
  local DOWNLOAD_BLUEPRINTS



  # download the blueprint
  DOWNLOAD_BLUEPRINTS=$(curl -L ${BLUEPRINT_URL}${ERA_Blueprint} -o ${DIRECTORY}${ERA_Blueprint})
  log "Downloading ${ERA_Blueprint} | BLUEPRINT_URL ${BLUEPRINT_URL}|${DOWNLOAD_BLUEPRINTS}"

  # ensure the directory that contains the blueprints to be imported is not empty
  if [[ $(ls -l "$DIRECTORY"/*.json) == *"No such file or directory"* ]]; then
      echo "There are no .json files found in the directory provided."
      exit 0
  fi

  # create a list to store all bluprints found in the directory provided by user
  declare -a LIST_OF_BLUEPRINTS=()

  # circle thru all of the files in the provided directory and add file names to a list of blueprints array
  # IMPORTANT NOTE: THE FILES NAMES FOR THE JSON FILES BEING IMPORTED CAN'T HAVE ANY SPACES (IN THIS SCRIPT)
  for FILE in "$DIRECTORY"/*.json; do
      BASENAM="$(basename ${FILE})"
      FILENAME="${BASENAM%.*}"
      LIST_OF_BLUEPRINTS+=("$BASENAM")
  done

  # echo $LIST_OF_BLUEPRINTS
  # if the list of blueprints is not empty then:
  if ((${#LIST_OF_BLUEPRINTS[@]})); then
      #   first check if the user has specified a project for the imported blueprints
      #   if they did, we need to make sure the project exists before assigning it to the BPs

      if [ $CALM_PROJECT != 'none' ]; then

          # curl command needed:
          # curl -s -k -X POST https://10.42.7.39:9440/api/nutanix/v3/projects/list -H 'Content-Type: application/json' --user admin:techX2019! -d '{"kind": "project", "filter": "name==default"}' | jq -r '.entities[].metadata.uuid'

          # formulate the curl to check for project
          _url_pc="https://localhost:9440/api/nutanix/v3/projects/list"

          # make API call and store project_uuid
          project_uuid=$(curl -s -k -X POST $_url_pc -H 'Content-Type: application/json' --user ${PRISM_ADMIN}:${PE_PASSWORD} -d "{\"kind\": \"project\", \"filter\": \"name==$CALM_PROJECT\"}" | jq -r '.entities[].metadata.uuid')

          if [ -z "$project_uuid" ]; then
              # project wasn't found
              # exit at this point as we don't want to assume all blueprints should then hit the 'default' project
              echo "\nProject $CALM_PROJECT was not found. Please check the name and retry."
              exit 0
          else
              echo "\nProject $CALM_PROJECT exists..."
          fi
      fi
  else
      echo '\nNo JSON files found in' + $DIRECTORY +' ... nothing to import!'
  fi

  # update the user with script progress...
  _num_of_files=${#LIST_OF_BLUEPRINTS[@]}
  echo "\nNumber of .json files found: ${_num_of_files}"
  echo "\nStarting blueprint updates and then exporting to Calm one file at a time...\n\n"

  # go through the blueprint JSON files list found in the specified directory
  for elem in "${LIST_OF_BLUEPRINTS[@]}"; do
      # read the entire JSON file from the directory
      JSONFile=${DIRECTORY}/"$elem"

      echo "\nCurrently updating blueprint $JSONFile..."

      # NOTE: bash doesn't do in place editing so we need to use a temp file and overwrite the old file with new changes for every blueprint
      tmp=$(mktemp)

      # ADD PROJECT (affects all BPs being imported) if no project was specified on the command line, we've already pre-set the project variable to 'none' if a project was specified, we need to add it into the JSON data
      if [ $CALM_PROJECT != 'none' ]; then
          # add the new atributes to the JSON and overwrite the old JSON file with the new one
          $(jq --arg proj $CALM_PROJECT --arg proj_uuid $project_uuid '.metadata+={"project_reference":{"kind":$proj,"uuid":$proj_uuid}}' $JSONFile >"$tmp" && mv "$tmp" $JSONFile)
      fi

      # ADD VARIABLES (affects ONLY if the current blueprint being imported MATCHES the name specified earlier "EraServerDeployment.json")
      if [ "$elem" == "${NAME}" ]; then
          if [ "$ERA_IP" != "none" ]; then
              tmp_ERA_IP=$(mktemp)
              # add the new variable to the json file and save it
              $(jq --arg var_name $ERA_IP '(.spec.resources.service_definition_list[0].variable_list[] | select (.name=="ERA_IP")).value=$var_name' $JSONFile >"$tmp_ERA_IP" && mv "$tmp_ERA_IP" $JSONFile)
              # result="$(jq --arg newOBJ "${obj_with_replaced_variable}" '.spec.resources.service_definition_list[0].variable_list[] | select (.name=="PE_VIP") | .+=$newOBJ' $JSONFile )"
          fi
          if [ "$PE_IP" != "none" ]; then
              tmp_PE_IP=$(mktemp)
              # add the new variable to the json file and save it
              $(jq --arg var_name $PE_IP '(.spec.resources.service_definition_list[0].variable_list[] | select (.name=="PE_VIP")).value=$var_name' $JSONFile >"$tmp_PE_IP" && mv "$tmp_PE_IP" $JSONFile)
              # result="$(jq --arg newOBJ "${obj_with_replaced_variable}" '.spec.resources.service_definition_list[0].variable_list[] | select (.name=="PE_VIP") | .+=$newOBJ' $JSONFile )"
          fi
          if [ "$CLSTR_NAME" != "none" ]; then
              tmp_CLSTR_NAME=$(mktemp)
              $(jq --arg var_name $CLSTR_NAME '(.spec.resources.service_definition_list[0].variable_list[] | select (.name=="CLSTR_NAME")).value=$var_name' $JSONFile >"$tmp_CLSTR_NAME" && mv "$tmp_CLSTR_NAME" $JSONFile)
          fi
          if [ "$CTR_UUID" != "none" ]; then
              tmp_CTR_UUID=$(mktemp)
              $(jq --arg var_name $CTR_UUID '(.spec.resources.service_definition_list[0].variable_list[] | select (.name=="CTR_UUID")).value=$var_name' $JSONFile >"$tmp_CTR_UUID" && mv "$tmp_CTR_UUID" $JSONFile)
          fi
          if [ "$CTR_NAME" != "none" ]; then
              tmp_CTR_NAME=$(mktemp)
              $(jq --arg var_name $CTR_NAME '(.spec.resources.service_definition_list[0].variable_list[] | select (.name=="CTR_NAME")).value=$var_name' $JSONFile >"$tmp_CTR_NAME" && mv "$tmp_CTR_NAME" $JSONFile)
          fi
          if [ "$NETWORK_NAME" != "none" ]; then
              tmp_NETWORK_NAME=$(mktemp)
              $(jq --arg var_name $NETWORK_NAME '(.spec.resources.service_definition_list[0].variable_list[] | select (.name=="NETWORK_NAME")).value=$var_name' $JSONFile >"$tmp_NETWORK_NAME" && mv "$tmp_NETWORK_NAME" $JSONFile)
          fi
          if [ "$VLAN_NAME" != "none" ]; then
              tmp_VLAN_NAME=$(mktemp)
              $(jq --arg var_name $VLAN_NAME '(.spec.resources.service_definition_list[0].variable_list[] | select (.name=="VLAN_NAME")).value=$var_name' $JSONFile >"$tmp_VLAN_NAME" && mv "$tmp_VLAN_NAME" $JSONFile)
          fi
      fi

      # REMOVE the "status" and "product_version" keys (if they exist) from the JSON data this is included on export but is invalid on import. (affects all BPs being imported)
      tmp_removal=$(mktemp)
      $(jq 'del(.status) | del(.product_version)' $JSONFile >"$tmp_removal" && mv "$tmp_removal" $JSONFile)

      # GET BP NAME (affects all BPs being imported)
      # if this fails, it's either a corrupt/damaged/edited blueprint JSON file or not a blueprint file at all
      blueprint_name_quotes=$(jq '(.spec.name)' $JSONFile)
      blueprint_name="${blueprint_name_quotes%\"}" # remove the suffix "
      blueprint_name="${blueprint_name#\"}" # will remove the prefix "

      if [ blueprint_name == 'null' ]; then
          echo "\nUnprocessable JSON file found. Is this definitely a Nutanix Calm blueprint file?\n"
          exit 0
      else
          # got the blueprint name means it is probably a valid blueprint file, we can now continue the upload
          echo "\nUploading the updated blueprint: $blueprint_name...\n"

          # Example curl call from the console:
          # url="https://10.42.7.39:9440/api/nutanix/v3/blueprints/import_file"
          # path_to_file="/Users/sharon.santana/Desktop/saved_blueprints/EraServerDeployment.json"
          # bp_name="EraServerDeployment"
          # project_uuid="a944258a-fd8a-4d02-8646-72c311e03747"
          # password='techX2019!'
          # curl -s -k -X POST $url -F file=@$path_to_file -F name=$bp_name -F project_uuid=$project_uuid --user admin:"$password"

          url="https://localhost:9440/api/nutanix/v3/blueprints/import_file"
          path_to_file=$JSONFile
          bp_name=$blueprint_name
          project_uuid=$project_uuid
          password=$PE_PASSWORD
          upload_result=$(curl -s -k -X POST $url -F file=@$path_to_file -F name=$bp_name -F project_uuid=$project_uuid --user admin:"$password")

          #if the upload_result var is not empty then let's say it was succcessful
          if [ -z "$upload_result" ]; then
              echo "\nUpload for $bp_name did not finish."
          else
              echo "\nUpload for $bp_name finished."
              echo "-----------------------------------------"
              # echo "Result: $upload_result"
          fi
      fi

    done

    echo "\nFinished uploading Era Blueprint and setting Variables!\n"

}

###############################################################################################################################################################################
# Routine to make changes to the PC UI; Colors, naming and the Welcome Banner
###############################################################################################################################################################################

function pc_ui() {
  # http://vcdx56.com/2017/08/change-nutanix-prism-ui-login-screen/
  local  _http_body
  local       _json
  local _pc_version
  local       _test
#{"type":"WELCOME_BANNER","username":"system_data","key":"welcome_banner_content","value":"${PRISM_ADMIN}:${PE_PASSWORD}@${CLUSTER_NAME}"} \
  _json=$(cat <<EOF
{"type":"custom_login_screen","key":"color_in","value":"#ADD100"} \
{"type":"custom_login_screen","key":"color_out","value":"#11A3D7"} \
{"type":"custom_login_screen","key":"product_title","value":"${CLUSTER_NAME},PC-${PC_VERSION}"} \
{"type":"custom_login_screen","key":"title","value":"Nutanix.HandsOnWorkshops.com,@${AUTH_FQDN}"} \
{"type":"WELCOME_BANNER","username":"system_data","key":"welcome_banner_status","value":true} \
{"type":"WELCOME_BANNER","username":"system_data","key":"welcome_banner_content","value":"${PRISM_ADMIN}:${PE_PASSWORD}"} \
{"type":"WELCOME_BANNER","username":"system_data","key":"disable_video","value":true} \
{"type":"UI_CONFIG","username":"system_data","key":"disable_2048","value":true} \
{"type":"UI_CONFIG","key":"autoLogoutGlobal","value":7200000} \
{"type":"UI_CONFIG","key":"autoLogoutOverride","value":0} \
{"type":"UI_CONFIG","key":"welcome_banner","value":"https://Nutanix.HandsOnWorkshops.com/workshops/6070f10d-3aa0-4c7e-b727-dc554cbc2ddf/start/"}
EOF
  )

  for _http_body in ${_json}; do
    _test=$(curl ${CURL_HTTP_OPTS} \
      --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST --data "${_http_body}" \
      https://localhost:9440/PrismGateway/services/rest/v1/application/system_data)
    log "_test=|${_test}|${_http_body}"
  done

  _http_body='{"type":"UI_CONFIG","key":"autoLogoutTime","value": 3600000}'
       _test=$(curl ${CURL_HTTP_OPTS} \
    --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST --data "${_http_body}" \
    https://localhost:9440/PrismGateway/services/rest/v1/application/user_data)
  log "autoLogoutTime _test=|${_test}|"

  # shellcheck disable=2206
  _pc_version=(${PC_VERSION//./ })

  if (( ${_pc_version[0]} >= 5 && ${_pc_version[1]} >= 10 && ${_test} != 500 )); then
    log "PC_VERSION ${PC_VERSION} >= 5.10, setting favorites..."

    _json=$(cat <<EOF
{"complete_query":"Karbon","route":"ebrowser/k8_cluster_entitys"} \
{"complete_query":"Images","route":"ebrowser/image_infos"} \
{"complete_query":"Projects","route":"ebrowser/projects"} \
{"complete_query":"Calm","route":"calm"}
EOF
    )

    for _http_body in ${_json}; do
      _test=$(curl ${CURL_HTTP_OPTS} --user ${PRISM_ADMIN}:${PE_PASSWORD} -X POST --data "${_http_body}" \
        https://localhost:9440/api/nutanix/v3/search/favorites)
      log "favs _test=|${_test}|${_http_body}"
    done
  fi
}

###############################################################################################################################################################################
# Routine to Create a Project in the Calm part
###############################################################################################################################################################################

function pc_project() {
  local _name="BootcampInfra"
  local _count
  local _role="Project Admin"
  local _role_uuid
  local _pc_account_uuid
  local _nw_name="${NW1_NAME}"
  local _nw_uuid

# Get the Network UUIDs
log "Get cluster network UUID"

_nw_uuid=$(curl --location --request POST 'https://localhost:9440/api/nutanix/v3/subnets/list' --header 'Content-Type: application/json' --user ${PRISM_ADMIN}:${PE_PASSWORD} --insecure -s --data '{"kind":"subnet","filter": "name==Primary"}' | jq -r '.entities[] | .metadata.uuid' | tr -d \")

# Get the Role UUIDs
log "Get Role UUID"

_role_uuid=$(curl --location --request POST 'https://localhost:9440/api/nutanix/v3/roles/list' --header 'Content-Type: application/json' --user ${PRISM_ADMIN}:${PE_PASSWORD} --insecure -s --data '{"kind":"role","filter":"name==Project Admin"}' | jq -r '.entities[] | .metadata.uuid' | tr -d \")

# Get the PC Account UUIDs
log "Get PC Account  UUID"

_pc_account_uuid=$(curl --location --request POST 'https://localhost:9440/api/nutanix/v3/accounts/list' --header 'Content-Type: application/json' --user ${PRISM_ADMIN}:${PE_PASSWORD} --insecure -s --data '{"kind":"account","filter":"type==nutanix_pc"}' | jq -r '.entities[] | .status.resources.data.cluster_account_reference_list[0].resources.data.pc_account_uuid' | tr -d \")

log "Create BootcampInfra Project ..."
log "NW UUID = ${_nw_uuid}"
log "Role UUID = ${_role_uuid}"
log "PC Account UUID = ${_pc_account_uuid}"

_http_body=$(cat <<EOF
{
  "api_version": "3.1",
  "metadata": {
	"kind": "project"
  },
  "spec": {
  	"access_control_policy_list": [
  	{
  		"operation": "ADD",
  		"metadata": {
			"kind": "access_control_policy"
		},
  		"acp": {
  			"name": "BootcampInfra",
  			"resources": {
  				"role_reference": {
  					"kind": "role",
					  "name": "Project Admin",
					  "uuid": "${_role_uuid}"
  				},
  				"user_group_reference_list": [
        		{
        			"kind": "user_group",
        			"name": "CN=SSP Admins,CN=Users,DC=ntnxlab,DC=local",
        			"uuid": "015456ee-399f-4517-bee8-90b71c5c81a0"
        		}
    			]
  			}
  		}
  	}
  	],
	"project_detail": {
  	"name": "${_name},
  	"resources": {
    	"account_reference_list": [
      	{
        	"kind": "account",
			    "name": "nutanix_pc",
			    "uuid": "${_pc_account_uuid}"
      	}
    	],
    	"subnet_reference_list": [
      	{
        	"kind": "subnet",
        	"name": "Primary",
        	"uuid": "${_nw_uuid}"
      	}
    	],
    	"external_user_group_reference_list": [
        {
          "kind": "user_group",
          "name": "CN=SSP Admins,CN=Users,DC=ntnxlab,DC=local",
          "uuid": "015456ee-399f-4517-bee8-90b71c5c81a0"
        }
    	]
  	}
	},
	"user_list": [],
	"user_group_list": []
  }
}
EOF
)


  _create_project=$(curl --location --insecure -s --request POST 'https://localhost:9440/api/nutanix/v3/projects_internal' --header 'Content-Type: application/json' --user ${PRISM_ADMIN}:${PE_PASSWORD} --data "${_http_body}")

  log "_ssp_connect=|${_ssp_connect}|"

}

#   _name=${EMAIL%%@nutanix.com}.test
#  _count=$(. /etc/profile.d/nutanix_env.sh \
#    && nuclei project.list 2>/dev/null | grep ${_name} | wc --lines)
#  if (( ${_count} > 0 )); then
#    nuclei project.delete ${_name} confirm=false 2>/dev/null
#  else
#    log "Warning: _count=${_count}"
#  fi

#  log "Creating ${_name}..."
#  nuclei project.create name=${_name} description='test from NuCLeI!' 2>/dev/null
#  _uuid=$(. /etc/profile.d/nutanix_env.sh \
#    && nuclei project.get ${_name} format=json 2>/dev/null \
#    | jq .metadata.project_reference.uuid | tr -d '"')
#  log "${_name}.uuid = ${_uuid}"



}
