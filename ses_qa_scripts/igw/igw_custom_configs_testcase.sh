#!/bin/bash

source ./exploit/CONFIG

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
