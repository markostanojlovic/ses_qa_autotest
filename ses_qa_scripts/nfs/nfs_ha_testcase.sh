#!/bin/bash

source ./exploit/CONFIG
source ./exploit/nfs_helper.sh

# NFS HA
_run_script_on_remote_host $MASTER ${BASEDIR}/ses_qa_scripts/nfs/nfs_HA.sh
