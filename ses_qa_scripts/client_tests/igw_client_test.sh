#!/bin/bash
set -ex
iSCSI_PORTAL=$1
# checking and installing open-iscsi package  
INSTALLED=$(zypper se open-iscsi|grep open-iscsi|awk -F '|' '{print $1}'|tr -d ' ')
[[ -z $INSTALLED ]] && zypper in -y open-iscsi
systemctl enable iscsid;systemctl start iscsid;systemctl status iscsid
iscsiadm -m node --logoutall=all 2>/tmp/igw_logoutall_err_log || cat /tmp/igw_logoutall_err_log
iscsiadm -m discovery --type=st --portal=$iSCSI_PORTAL
result=$(iscsiadm -m discovery --type=st --portal=$iSCSI_PORTAL|tail -n 1);target=iqn${result#*iqn};echo $target
iscsiadm -m node -n $target --login
sleep 1
new_disk=$(dmesg|tail -n 1|grep 'Attached SCSI disk'|awk '{print $5}'|tr -d '[]');echo $new_disk 	
# TODO: what if more than 1 disk is exported???
# check if the disk is already formated
lsblk|grep ${new_disk}1 || ( sgdisk --largest-new=1 /dev/$new_disk; mkfs.xfs /dev/${new_disk}1 -f )
mount|grep mnt && umount /mnt -f
mount /dev/${new_disk}1 /mnt
ls -la /mnt
openssl rand -base64 10000000 -out /mnt/igw_random.txt
tail /mnt/igw_random.txt
umount /mnt
echo "Result: OK"