#!/bin/bash
# Script for testing ceph clients on a non-cluster node:
# - igw (iSCSI)
# - cephfs 
# - NFS 
# - RBD
# - RGW

# README:
# 	- *** ONLY WORKING FOR SLES OS CLIENTS ***
# 	- Run as root from MASTER 
# 	- ssh paswrodless access to client server from MASTER
# 	@MASTER: 	ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa; cat ~/.ssh/id_rsa.pub
# 				sed -i '/StrictHostKeyChecking/c\StrictHostKeyChecking no' /etc/ssh/ssh_config
# USAGE: 
# ./ses_qa_scripts/clients.sh client_host_name_or_ip

set -ex
BASEDIR=$(find / -type d -name ses_qa_autotest)
source ${BASEDIR}/exploit/helper.sh

REMOTE_HOST_IP=$1
sed -i '/StrictHostKeyChecking/c\StrictHostKeyChecking no' /etc/ssh/ssh_config

############
# igw
############
iSCSI_PORTAL=$(_get_fqdn_from_pillar_role igw)
for portal in $iSCSI_PORTAL
do 
	_run_script_on_remote_host $REMOTE_HOST_IP ${BASEDIR}/ses_qa_scripts/client_tests/igw_client_test.sh $portal
done

############
# cephFS
############
CEPHFS_IP=$(_get_fqdn_from_pillar_role mds)
CLIENT_ADMIN_KEY=$(ceph auth list 2>/dev/null|grep -A 1 client.admin|grep key|sed 's/key: //'|tr -d '\t')
for host in $CEPHFS_IP
do 
	_run_script_on_remote_host $REMOTE_HOST_IP ${BASEDIR}/ses_qa_scripts/client_tests/cephFS_client_test.sh $host $CLIENT_ADMIN_KEY
done

############
# NFS
############
NFS_IP=$(_get_fqdn_from_pillar_role ganesha)
for host in $NFS_IP
do 
	_run_script_on_remote_host $REMOTE_HOST_IP ${BASEDIR}/ses_qa_scripts/client_tests/nfs_client_test.sh $host
done

############
# RBD
############
scp /etc/ceph/ceph.conf $REMOTE_HOST_IP:/etc/ceph/
scp /etc/ceph/ceph.client.admin.keyring $REMOTE_HOST_IP:/etc/ceph/
RBD_POOL=rbd-disks
ceph osd pool create $RBD_POOL 8 8 
ceph osd pool application enable $RBD_POOL rbd
_run_script_on_remote_host $REMOTE_HOST_IP ${BASEDIR}/ses_qa_scripts/client_tests/rbd_client_test.sh $RBD_POOL

############
# RGW
############
RGW_HOSTS=$(_get_fqdn_from_pillar_role rgw)
for host in $RGW_HOSTS
do 
	TCP_PORT=$(salt $host cmd.run 'ss -n -l -p '|grep tcp|grep radosgw|awk '{print $5}'|tr -d '*:')
	_run_script_on_remote_host $REMOTE_HOST_IP ${BASEDIR}/ses_qa_scripts/client_tests/rgw_client_test.sh $host $TCP_PORT
done

echo "Result: OK"