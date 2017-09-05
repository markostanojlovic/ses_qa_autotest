#!/bin/bash
# MOUNT, READ AND WRITE TEST OF cephFS on a clinet server
CEPHFS_IP=$1 		# EXAMPLE: ses5node2.qatest
# OBTAINED BY: ceph auth list 2>/dev/null|grep -A 1 client.admin|grep key|sed 's/key: //'|tr -d '\t'
CLIENT_ADMIN_KEY=$2	# EXAMPLE: AQAwX65ZAAAAABAAjAtdwWIkx0PunxBRuo9uNA==
set -ex
# checking and installing ceph-common package needed for mounting cephFS 
INSTALLED=$(zypper se ceph-common|grep ceph-common|awk -F '|' '{print $1}'|tr -d ' ')
[[ -z $INSTALLED ]] && zypper in -y ceph-common
# adding admin secret key
[[ -d /etc/ceph/ ]] || mkdir /etc/ceph/
echo $CLIENT_ADMIN_KEY > /etc/ceph/admin.secret
chmod 600 /etc/ceph/admin.secret
# mount test 
mount|grep mnt && umount /mnt -f
mount -t ceph $CEPHFS_IP:6789:/ /mnt -o name=admin,secretfile=/etc/ceph/admin.secret
# write test 
openssl rand -base64 10000000 -out /mnt/cephfs_random.txt
# read test 
ls -la /mnt
tail /mnt/cephfs_random.txt
# unmount
umount /mnt
sleep 1
# checking time needed to complete actions 
time mount -t ceph $CEPHFS_IP:6789:/ /mnt -o name=admin,secretfile=/etc/ceph/admin.secret
time umount /mnt 
echo 'Result: OK'