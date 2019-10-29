#!/bin/bash
#
BIN=/usr/bin
DOMAIN=ntnxlab.local
PASSWD="nutanix/4u"
IFS=","

while read -u50 Webname IP1 DBName IP2 DRIP1 DRIP2
do
  echo Adding: "$Webname" with IP "$IP1" with DRIP "$DRIP1" and "$DBName" with IP "$IP2" and DRIP "$DRIP2"
  OCTETDC1=(${IP1//./,})
  OCTETDC2=(${DRIP1//./,})
  DC1="${OCTETDC1[0]}.${OCTETDC1[1]}.${OCTETDC1[2]}.41"
  DC2="${OCTETDC2[0]}.${OCTETDC2[1]}.${OCTETDC2[2]}.41"
  echo "Using Domain controlers: DC1: $DC1 and DC2: $DC2"
  SSHPASS=$PASSWD sshpass -e ssh root@$DC1 samba-tool dns add $DC1 $DOMAIN $Webname A $IP1 -U administrator --password $PASSWD
  SSHPASS=$PASSWD sshpass -e ssh root@$DC1 samba-tool dns add $DC1 $DOMAIN $DBName A $IP2 -U administrator --password $PASSWD
  echo "Updating the DR side......"
  SSHPASS=$PASSWD sshpass -e ssh root@$DC2 samba-tool dns add $DC2 $DOMAIN $Webname A $DRIP1 -U administrator --password $PASSWD
  SSHPASS=$PASSWD sshpass -e ssh root@$DC2 samba-tool dns add $DC2 $DOMAIN $DBName A $DRIP2 -U administrator --password $PASSWD
  echo "--------------------------------------------------------------------------------------------------------------------------------"
  echo ""
done 50< <(cat minigts_ce_list.txt )

for i in 104 111 184 110 99 4 96 95 69 86 81 61
do 
    DC="10.42.$i.41"
    SSHPASS=$PASSWD sshpass -e ssh root@$DC "samba-tool dns query $DC $DOMAIN @ ALL -U administrator --password $PASSWD"
    echo "--------------------------------------------------------"
done
