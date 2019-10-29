#!/bin/bash

# SCript to stage the NHT clusters for the fourth node
# Create single node cluster
yes | cluster --cluster_name=NHTLab --dns_servers=10.42.196.10 --ntp_servers=10.42.196.10 --svm_ips=$(/sbin/ifconfig eth0 | grep 'inet ' | awk '{ print $2}') create

# Give the cluster some time to settle
sleep 60

#Reset the admin password
ncli user reset-password user-name='admin' password='nht2EMEA!'

#Rename the default SP to SP1
default_sp=$(ncli storagepool ls | grep 'Name' | cut -d ':' -f 2 | sed s/' '//g)
ncli sp edit name="${default_sp}" new-name="SP1"

# Create an Images container if it doesn't exist
(ncli container ls | grep -P '^(?!.*VStore Name).*Name' | cut -d ':' -f 2 | sed s/' '//g | grep "^Images" 2>&1 > /dev/null) \
    && echo "Container Images already exists" \
    || ncli container create name="Images" sp-name="SP1"

# Accept the EULA
curl -u admin:'nht2EMEA!' -k -H 'Content-Type: application/json' -X POST \
  https://127.0.0.1:9440/PrismGateway/services/rest/v1/eulas/accept \
  -d '{
    "username": "SE",
    "companyName": "NTNX",
    "jobTitle": "SE"
}'

# Disable Pulse in PE
curl -u admin:'nht2EMEA!' -k -H 'Content-Type: application/json' -X PUT \
  https://127.0.0.1:9440/PrismGateway/services/rest/v1/pulse \
  -d '{
    "defaultNutanixEmail": null,
    "emailContactList": null,
    "enable": false,
    "enableDefaultNutanixEmail": false,
    "isPulsePromptNeeded": false,
    "nosVersion": null,
    "remindLater": null,
    "verbosityType": null
}'


# Upload the images
curl -X POST \
  https://127.0.0.1:9440/api/nutanix/v3/batch \
  -H 'Content-Type: application/json' \
  --insecure --user admin:'nht2EMEA!' \
  -d '{
	"action_on_failure":"CONTINUE",
	"execution_order":"SEQUENTIAL",
	"api_request_list":[
		{
			"operation":"POST",
			"path_and_params":"/api/nutanix/v3/images",
			"body":{
				"spec":{
					"name":"X-Ray.qcow2",
					"resources":{
						"image_type":"DISK_IMAGE",
						"source_uri":"http://download.nutanix.com/xray/3.5.0/xray.qcow2"
					}
				},
				"metadata":{
					"kind":"image"
				},
				"api_version":"3.1.0"
			}
		},
		{
			"operation":"POST",
			"path_and_params":"/api/nutanix/v3/images",
			"body":{
				"spec":{
					"name":"Foundation.qcow2",
					"resources":{
						"image_type":"DISK_IMAGE",
						"source_uri":"http://download.nutanix.com/foundation/foundation-4.4.3/Foundation_VM-4.4.3-disk-0.qcow2"
					}
				},
				"metadata":{
					"kind":"image"
				},
				"api_version":"3.1.0"
			}
		}
	],
	"api_version":"3.0"
}'