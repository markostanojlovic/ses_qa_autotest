#!/bin/bash
# Script for deploying and testing NFS ganesha HA feature
# REQUIREMENTS:
# - to have 2 nfs ganesha nodes in ceph cluster
# - to have connection do download HA ISO images from mirror.suse.cz
# -

set -ex
BASEDIR=$(find / -type d -name ses_qa_autotest 2>/dev/null)
source ${BASEDIR}/exploit/CONFIG
source ${BASEDIR}/exploit/nfs_helper.sh

# setting one of ganesha nodes to be HA primary node
NFS_NODE=$(_get_fqdn_from_pillar_role ganesha|head -n 1)
salt $NFS_NODE grains.setval ceph_ganesha_HA_master_node True

set_NFS_HA_IP 192.168.100.149
nfs_ganesha_disable_service
nfs_ha_cluster_bootstrap
_run_script_on_remote_host $CLIENT_NODE ${BASEDIR}/ses_qa_scripts/client_tests/nfs_client_test.sh $(get_NFS_HA_IP)
ha_ganesha_ip_failover
_run_script_on_remote_host $CLIENT_NODE ${BASEDIR}/ses_qa_scripts/client_tests/nfs_client_test.sh $(get_NFS_HA_IP)
ha_ganesha_ip_failover
_run_script_on_remote_host $CLIENT_NODE ${BASEDIR}/ses_qa_scripts/client_tests/nfs_client_test.sh $(get_NFS_HA_IP)
echo "Result: OK"
