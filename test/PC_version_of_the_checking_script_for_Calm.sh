# Script for checking the connectivity to PC from the PE

# Using sshpass to connect to the different PEs to be tested
for clusterIP in `cat pcIP.txt`
do
	echo =============================
	echo Checking Cluster: $clusterIP
	echo -----------------------------
	
	# Check if there are projects defined. If so we have a go for Calm
	curl -k -s -X GET   https://$clusterIP:9440/apps/projects -H 'Authorization: Basic YWRtaW46dGVjaFgyMDE5IQ==' -H 'Postman-Token: e2f20f92-d0ff-4e87-92f7-1a1829108e4f' -H 'cache-control: no-cache' | grep CALM_VERSION | tr -s " "|cut -d" " -f 5
	
	# Add two extra two empty lines
	echo && echo

	
done