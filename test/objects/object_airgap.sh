#!/bin/sh

# Script to set the airgap for Objects to our TS filesservers.

for _cluster in $(cat cluster.txt | grep -v ^#)
    do
      set -f
      _fields=(${_cluster//|/ })
      PE_HOST=${_fields[0]}
      PE_PASSWORD=${_fields[1]}
      OCTET=(${PE_HOST//./ })
      PC_HOST=${PE_HOST:-2}
      CURL_HTTP_OPTS=' --max-time 25 --silent --header Content-Type:application/json --header Accept:application/json  --insecure '
      _url_network="https://${PC_HOST}:9440/api/nutanix/v3/subnets/list"
      _url_oss="'https://${PC_HOST}:9440/oss/api/nutanix/v3/objectstores"
      _url_oss_check="https://${PC_HOST}:9440/oss/api/nutanix/v3/objectstores/list"


      # Getting the IP for the sources file of objects
      if [[ ${OCTET[1]} == "42" || ${OCTET[1]} == "38" ]]; then
      	source_ip="http://10.42.38.10/images"
      else
      	source_ip="http://10.55.76.10"
      fi

      # Getting the command ready based on IP network of the cluster
      cmd='/usr/local/nutanix/cluster/bin/mspctl airgap --enable --lcm-server='
      cmd+=$source_ip
      cmd+=';sleep 3;/usr/local/nutanix/cluster/bin/mspctl airgap --status | grep "\"enable\":true" | wc -l'

      # Fire the command on the PC of the cluster so we have the right Dark Site image pull for Objects
      sshpass -e ssh nutanix@${PE_HOST} -o StrictHostKeyChecking=no -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=/dev/null $cmd

      # See if we have an error on the cluster for the objects
      url="https://${PC_HOST}:9440/oss/api/nutanix/v3/groups"
      payload='{"entity_type":"objectstore","group_member_sort_attribute":"name","group_member_sort_order":"ASCENDING","group_member_count":20,"group_member_offset":0,"group_member_attributes":[{"attribute":"name"},{"attribute":"domain"},{"attribute":"num_msp_workers"},{"attribute":"usage_bytes"},{"attribute":"num_buckets"},{"attribute":"num_objects"},{"attribute":"num_alerts_internal"},{"attribute":"client_access_network_ip_used_list"},{"attribute":"total_capacity_gib"},{"attribute":"last_completed_step"},{"attribute":"state"},{"attribute":"percentage_complete"},{"attribute":"ipv4_address"},{"attribute":"num_alerts_critical"},{"attribute":"num_alerts_info"},{"attribute":"num_alerts_warning"},{"attribute":"error_message_list"},{"attribute":"cluster_name"},{"attribute":"client_access_network_name"},{"attribute":"client_access_network_ip_list"},{"attribute":"buckets_infra_network_name"},{"attribute":"buckets_infra_network_vip"},{"attribute":"buckets_infra_network_dns"},{"attribute":"total_memory_size_mib"},{"attribute":"total_vcpu_count"},{"attribute":"num_vcpu_per_msp_worker"}]}'
      _respone_json=$(curl ${CURL_HTTP_OPTS} -d ${payload} ${url} --user admin:${PE_PASSWORD} | jq '.group_results[0].entity_results[0].data[] | select (.name=="state") .values[0].values[0]' | tr -d \")

      if [[ ${_respone_json} != "COMPLETE" ]]; then
        if [[ ${_respone_json} == "PENDING" ]]; then
          echo "Status for ${PC_HOST} is pending.... Skipping"
        else
          echo "Found and error at PC ${PC_HOST}.. Starting counter measurements...."
          # Delete the current objectstore
          _respone_json=$(curl ${CURL_HTTP_OPTS} -d ${payload} ${url} --user admin:${PE_PASSWORD} | jq '.group_results[0].entity_results[0].entity_id' | tr -d \")
          uuid_objects_store=${_respone_json}
          url_delete="https://${PC_HOST}:9440/oss/api/nutanix/v3/objectstores/${uuid_objects_store}"
          del_oss_response=$(curl ${CURL_HTTP_OPTS} -X DELETE ${url_delete} -w "%{http_code}\n" --user admin:${PE_PASSWORD})

          # Has the deletion been accepted?
          if [[ ${del_oss_response} == "202" ]]; then
            echo "Objectstore is to be deleted... Checking before moving on..."
            url="https://${PC_HOST}:9440/oss/api/nutanix/v3/groups"
            payload='{"entity_type":"objectstore","group_member_sort_attribute":"name","group_member_sort_order":"ASCENDING","group_member_count":20,"group_member_offset":0,"group_member_attributes":[{"attribute":"name"}]}'
            _response_json=$(curl ${CURL_HTTP_OPTS} -d ${payload} ${url} --user admin:${PE_PASSWORD} | jq '.filtered_entity_count' | tr -d \")
            # Wait while the objectstore is still there before we move on in creating one.
            while [[ ${_response_json} != 0 ]]
              do
                echo "Objectstore still found... Waiting 10 seconds.."
                sleep 10
                _response_json=$(curl ${CURL_HTTP_OPTS} -d ${payload} ${url} --user admin:${PE_PASSWORD} | jq '.filtered_entity_count' | tr -d \")  
              done
          


            # Done waiting, now let's create the payload for the objectstore.
            # Get the variables from the cluster
            # Payload for the _json_data so we get the data needed...
            _json_data='{"kind":"subnet"}'
            CLUSTER_UUID=$(curl -X POST -d $_json_data $CURL_HTTP_OPTS --user admin:${PE_PASSWORD} $_url_network | jq '.entities[].spec | select (.name=="Primary") | .cluster_reference.uuid' | tr -d \")
            PRIM_NETWORK_UUID=$(curl -X POST -d $_json_data $CURL_HTTP_OPTS --user admin:${PE_PASSWORD} $_url_network | jq '.entities[] | select (.spec.name=="Primary") | .metadata.uuid' | tr -d \")

            BUCKETS_VIP="${OCTET[0]}.${OCTET[1]}.${OCTET[2]}.17"
            BUCKETS_DNS_IP="${OCTET[0]}.${OCTET[1]}.${OCTET[2]}.16"
            OBJECTS_NW_START="${OCTET[0]}.${OCTET[1]}.${OCTET[2]}.18"
            OBJECTS_NW_END="${OCTET[0]}.${OCTET[1]}.${OCTET[2]}.21"

            # Create the payload URL
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

            # Now we have the correct data in the payload, let's fire ti to the cluster
            oss_create="https://${PC_HOST}:9440/oss/api/nutanix/v3/objectstores"
            echo "curl ${CURL_HTTP_OPTS} -X POST --user admin:${PE_PASSWORD} -d ${_json_data_oss} ${oss_create})"
            _response_oss_create=$(curl ${CURL_HTTP_OPTS} -X POST --user admin:${PE_PASSWORD} -d ${_json_data_oss} ${oss_create} | jq '.metadata.uuid' | tr -d \")
            if [[ -z ${_response_oss_create} ]]; then
              echo "Failed to fire the script. Please check the cluster.."
            else
              echo "Create Objectstore has been fired...."
            fi
          fi
        fi
      else
        echo "All good at PC ${PC_HOST}..."
      fi


  	done



