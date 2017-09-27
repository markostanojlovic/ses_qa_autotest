#!/bin/bash

source ./exploit/CONFIG

# IGW multipath test of default demo image
PORTAL=$(ssh $MASTER "source ~/ses_qa_autotest/exploit/helper.sh;_get_igw_portals"|head -n 1)
_run_script_on_remote_host $CLIENT_NODE ${BASEDIR}/ses_qa_scripts/client_tests/igw_multipath_client_test.sh $PORTAL
