#!/bin/bash
# This script is testing mount of NFS export with different mount options 
# USAGE:
# ./NFS_client_test.sh NFS_IP_ADDRESS
set -ex
[[ -n $1 ]] && NFS_IP_ADDRESS=$1 || (echo ERROR: Missing NFS IP. ; exit 1)
timeout_limit=5   
LOG_FILE=/tmp/NFS_HA_QA_test.log
> $LOG_FILE
MOUNT_OPTIONS_FILE=/tmp/mount_options_input_file
##### mount options input file #####
echo "\
mount.nfs4 -o rw,hard,intr,noatime
mount.nfs4 -o rw,soft,timeo=20,noatime 
mount -t nfs 
mount -t nfs -o rw,sync 
mount.nfs4 " > $MOUNT_OPTIONS_FILE
####################################
date >> $LOG_FILE
mount_target="${NFS_IP_ADDRESS}:/ /mnt"
openssl rand -base64 10000000 -out /tmp/random.txt

function test_command_for_timeout {
	command_to_test=$1
	timeout $timeout_limit $command_to_test
	timeout_rc=$?
	if [[ $timeout_rc == 0 ]]
		then
		echo "INFO: command: [ $command_to_test ] finished OK" >> $LOG_FILE
	else
		echo "ERROR: command: [ $command_to_test ] timed out after $timeout_limit seconds" >> $LOG_FILE; exit 1 
    fi
}

mount|grep mnt && umount /mnt -f 
# test ping
ping -q -c 3 $NFS_IP_ADDRESS|grep " 0% packet loss" || ( echo "PING status: *** KO ***" >> $LOG_FILE;exit 1 )
echo "PING status: OK " >> $LOG_FILE
# TESTING
while read mount_options
do
# test mount 
test_command_for_timeout "$mount_options $mount_target"
# test ls
test_command_for_timeout "ls /mnt/cephfs"
# test write 
test_command_for_timeout "cp /tmp/random.txt /mnt/cephfs/nfs-ganesha_test_file_$(date +%H_%M_%S)"
# test read 
test_command_for_timeout "tail -n 1 /mnt/cephfs/nfs-ganesha_test_file_*"
# test umount 
test_command_for_timeout 'umount /mnt'
done < $MOUNT_OPTIONS_FILE

date >> $LOG_FILE
echo 'Result: OK'
