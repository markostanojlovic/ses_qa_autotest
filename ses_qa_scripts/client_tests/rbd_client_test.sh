#!/bin/bash
set -ex
RBD_POOL=$1
function _rbd_unmap_all {
	MAPPED_IMGs=$(rbd showmapped|grep "/dev/rbd"|awk '{print $5}')
	for img in $MAPPED_IMGs
	do
		rbd unmap $img
	done
}
# checking and installing librbd1 package needed for mounting cephFS 
INSTALLED=$(zypper se librbd1|grep librbd1|awk -F '|' '{print $1}'|tr -d ' ')
[[ -z $INSTALLED ]] && zypper in -y librbd1
# adding admin secret key
NEW_DISK=rbd_test_disk_001
rados -n client.admin --keyring=/etc/ceph/ceph.client.admin.keyring -p $RBD_POOL ls
rbd create $NEW_DISK --size 2048 --pool $RBD_POOL 2>/tmp/rbd_create_err_log || cat /tmp/rbd_create_err_log 
rbd -p $RBD_POOL ls
MAPPED_DEV=$(rbd map $NEW_DISK --pool $RBD_POOL --id admin)
rbd showmapped
DEV_NAME=${MAPPED_DEV##*/}
lsblk|grep ${DEV_NAME}p1 || ( sgdisk --largest-new=1 $MAPPED_DEV; mkfs.xfs ${MAPPED_DEV}p1 -f)
mount|grep mnt && umount /mnt -f
mount ${MAPPED_DEV}p1 /mnt
ls -la /mnt 
openssl rand -base64 1000000 -out /mnt/rbd_random.txt
tail /mnt/rbd_random.txt
umount /mnt -f 
_rbd_unmap_all
rbd showmapped
echo 'Result: OK'
