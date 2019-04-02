# Script for checking the connectivity to PC from the PE

# Using sshpass to connect to the different PEs to be tested
for clusterIP in `cat clusterip.txt`
do
	echo =============================
	echo Checking Cluster: $clusterIP
	echo -----------------------------

	# Grabbing the status of the PC connection
	echo -n PC connection: 

	pc_state=`curl -s -X GET "https://$clusterIP:9440/PrismGateway/services/rest/v1/multicluster/cluster_external_state" -H 'Accept: application/json' -H 'Content-Type: application/json' --insecure --basic --user admin:techX2019! | cut -d"," -f 8`
	if [[ $pc_state != *"reachable"* ]]
	then
		echo No connection to the PRISM Central server
	else
		echo All OK
	fi

	# Grabbing the status of the versions of software for AFS
	state=`curl -s -X GET "https://$clusterIP:9440/PrismGateway/services/rest/v1/upgrade/afs/softwares" -H 'Accept: application/json' -H 'Content-Type: application/json' --insecure --basic --user admin:techX2019! | jq '.entities[].status' | cut -d" " -f 6`
	state=`echo $state | cut -d" " -f 6`

	# If the state is not COMPLETE throw an error and show what is the status
	if [[ $state != *"COMPLETED"* ]]
		then
			# Grabbing the status of the software versions
			version=`curl -s -X GET "https://$clusterIP:9440/PrismGateway/services/rest/v1/upgrade/afs/softwares" -H 'Accept: application/json' -H 'Content-Type: application/json' --insecure --basic --user admin:techX2019! | jq '.entities[].name' | cut -d" " -f 6`
			version=`echo $version | cut -d" " -f 6`
			echo Version avail is $version and status is $state
	fi
	
	# Grab the images and show them
	images_nr=`curl -s -X GET "https://$clusterIP:9440/PrismGateway/services/rest/v2.0/images/" -H 'Accept: application/json' -H 'Content-Type: application/json' --insecure --basic --user admin:techX2019! | jq '.entities[].name' | wc -l`
	if [ $images_nr -le 15 ]
	  then
		echo -n The images are: 
		curl -s -X GET "https://$clusterIP:9440/PrismGateway/services/rest/v2.0/images/" -H 'Accept: application/json' -H 'Content-Type: application/json' --insecure --basic --user admin:techX2019! | jq '.entities[].name'
	  else
	  	echo Images are OK 
	fi
	

	# Grab the networkconfigs
	#echo Defined networks are:
	#curl -s -X GET   "https://$clusterIP:9440/PrismGateway/services/rest/v2.0/networks/"   -H 'Accept: application/json'   -H 'Content-Type: application/json'   --insecure   --basic --user admin:techX2019! | jq '.entities[].name'
	#echo The defined ranges are:
	#curl -s -X GET   "https://$clusterIP:9440/PrismGateway/services/rest/v2.0/networks/"   -H 'Accept: application/json'   -H 'Content-Type: application/json'   --insecure   --basic --user admin:techX2019! | jq '.entities[].ip_config.pool[0].range'
	
	#echo Defined networks are:
	networks=`curl -s -X GET   "https://$clusterIP:9440/PrismGateway/services/rest/v2.0/networks/"   -H 'Accept: application/json'   -H 'Content-Type: application/json'   --insecure   --basic --user admin:techX2019! | jq '.entities[] | {name: .name, range: .ip_config.pool[].range}'`
	
	# Splitting the information into the two networks - network1
	network1=`echo $networks | cut -d":" -f 2 | cut -d"," -f 1`
	network1_rnge=`echo $networks | cut -d"," -f 2 | cut -d":" -f 2 | cut -d"}" -f 1`

	network2=`echo $networks | cut -d":" -f 4 | cut -d"," -f 1`
	network2_rnge=`echo $networks | cut -d":" -f 5 | cut -d"}" -f 1`

	# Check the network names Must be Secondary or Primary
	if [[ $network1 != *"Sec"* ]] && [[ $network1 != *"Prim"* ]]
	then
		echo Wrong naming of the network. Have found : $network1 with range $network1_rnge
	else
		if [[ $network2 != *"Sec"* ]] && [[ $network2 != *"Prim"* ]]
		then
			echo Also the other network has been named wrongly: $network2 with range $network2_rnge	
		else
			netw_nme_chk="Good"
		fi
	fi

	if [[ $network1_rnge != *".132"* ]] && [[ $network1_rnge != *".50"* ]]
	then
		echo Wrong IP Range $network1. It has range $network1_rnge
	else
		if [[ $network2_rnge != *".132"* ]] && [[ $network2_rnge != *".50"* ]]
		then
			echo Wrong IP Range for $network2. It has range $network2_rnge	
		else
			netw_rnge_chk="Good"
		fi
	fi

	if [[ $netw_rnge_chk == *"Good"* ]] && [[ $netw_nme_chk == *"Good"* ]]
	then
		echo Network OK
	fi

	# Add two extra two empty lines
	echo && echo

	
done