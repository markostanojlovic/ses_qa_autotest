#!/bin/bash

source ./exploit/CONFIG
source ./exploit/nfs_helper.sh

# IGW multipath test of default demo image
PORTAL=$(ssh $MASTER "source ~/ses_qa_autotest/exploit/helper.sh;_get_igw_portals"|head -n 1)
_run_script_on_remote_host $CLIENT_NODE ${BASEDIR}/ses_qa_scripts/client_tests/igw_multipath_client_test.sh $PORTAL

# IGW custom configs
for LRBD_CONF_FILE in $(ls ${BASEDIR}/exploit/*lrbd.conf*json)
do
	scp $LRBD_CONF_FILE $MASTER:/tmp/lrbd.conf.json
	_run_command_on_remote_host $MASTER "~/ses_qa_autotest/ses_qa_scripts/igw/igw_deploy.sh"
	PORTALS=$(ssh $MASTER "source ~/ses_qa_autotest/exploit/helper.sh;_get_igw_portals")
	for portal in $PORTALS
	do
		_run_script_on_remote_host $CLIENT_NODE ${BASEDIR}/ses_qa_scripts/client_tests/igw_client_test.sh $portal
	done
done

# NFS HA
_run_script_on_remote_host $MASTER ${BASEDIR}/ses_qa_scripts/nfs/nfs_HA.sh
