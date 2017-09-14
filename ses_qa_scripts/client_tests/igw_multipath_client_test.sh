#!/bin/bash
# igw multipath check 
set -ex
iSCSI_PORTAL=$1
# enable and start multipath sw on client 
chkconfig multipathd on
systemctl start multipathd
systemctl status multipathd
# attach iscsi disks
iscsiadm -m node --logoutall=all || echo "No logins"
iscsiadm -m discovery --type=st --portal=$iSCSI_PORTAL
result=$(iscsiadm -m discovery --type=st --portal=$iSCSI_PORTAL|tail -n 1);target=iqn${result#*iqn};echo $target
iscsiadm -m node -n $target --login
sleep 3
multipath -ll
#DEV=$(ls -la /dev/mapper/|grep part|grep -o dm-[0-9]|uniq)
NUM_OF_PATHS=$(multipath -ll|grep "active ready running"|wc -l)
[[ $NUM_OF_PATHS -eq 2 ]] && echo "Result: OK" || echo "Result: NOT_OK"