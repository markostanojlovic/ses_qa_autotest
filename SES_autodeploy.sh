#!/bin/bash
#######################################################################################
# Description: 	Script for creating VMs and depolying SES5 on them
# Author:  		Marko Stanojlovic, QA Ceph @ SUSE Enterprise Storage
# Contact: 		mstanojlovic@suse.com                                         
# Last update:  23-Aug-2017
# Usage: 		./SES_autodeploy.sh
#
# *** REQUIREMENTS: ***
# - Script should be run as root 
# - Directory where are the stored VM images is: $VM_DIR - hardcoded to /VM
# - VM names are $VM_NAME_BASE and incrementing suffix number - hardcoded to "ses5node"
# - SALT MASTER node is the first VM "ses5node1"
#######################################################################################

# ***** MANUAL CONFIG *****
VM_DIR=/VM
OSD_DEST_LIST='/VM /VM-images'
VM_NAME_BASE='ses5node'
OS_VARIANT=sles12sp3
VM_NUM=5
MAX_VM_NUM=100
# ***** END MANUAL CONFIG *****

BASEDIR=$(pwd)
MASTER=${VM_NAME_BASE}1

sript_start_time=$(date +%s)
# Checking the REPO file 
REPO_FILE=${BASEDIR}/exploit/REPO_ISO_URLs
[[ -r $REPO_FILE ]] || (echo "ERROR: No REPO file."; exit 1)
lin_num=1
while read linija;do link[lin_num]=$linija;let lin_num+=1
done <$REPO_FILE
os_url1=${link[1]}
ses_url1=${link[2]}
ISO_MEDIA=${os_url1##*/}
ISO_MEDIA_SES_1=${ses_url1##*/}

VM_HYP_DEF_GW=$(ip a s dev virbr1|grep inet|awk '{print $2}'| cut -d/ -f1)	# EXAMPLE: 192.168.100.1
VMNET_IP_BASE=${VM_HYP_DEF_GW%\.*}											# EXAMPLE: 192.168.100

RSA_PUB_KEY_ROOT=~/.ssh/id_rsa.pub
if [[ -r $RSA_PUB_KEY_ROOT ]]
	then 
	echo "RSA key exists."
	ssh_pub_key=$(cat $RSA_PUB_KEY_ROOT)
else 
	echo "Missing RSA key."
fi

VMNET_NAME=$(virsh net-list|grep active|tail -n 1|awk '{print $1}')
[[ $VMNET_NAME ]] || (echo "ERROR: Couldn't find vmnet value.";exit 13) 	# exit if vmnet is empty string 

###############################
echo "Preparing the environment..." 
###############################
echo "Checking if VMs are existing..." 
virsh list --all|grep ${VM_NAME_BASE} && NO_VMs=0 || NO_VMs=1
if [[ $NO_VMs -eq 0 ]] 
then
for (( NODE_NUMBER=1; NODE_NUMBER <=$VM_NUM; NODE_NUMBER++ ))
do
	virsh destroy ${VM_NAME_BASE}${NODE_NUMBER} 2>/dev/null 	# Force stop VMs (even if they are not running)
	virsh undefine ${VM_NAME_BASE}${NODE_NUMBER} --nvram 		# Undefine VMs (--nvram option for aarch64)
done
fi

# Delete disk images 
rm ${VM_DIR}/${VM_NAME_BASE}*

> ~/.ssh/known_hosts

# Generate autoyast xml files:			
autoyast_seed=${BASEDIR}/exploit/autoyast_${VM_NAME_BASE}.xml
[[ -r $autoyast_seed ]] || (echo "ERROR: Autoyast file missing. Exiting.";exit 15)
for (( NODE_NUMBER=1; NODE_NUMBER <=$VM_NUM; NODE_NUMBER++ ))
do
xmlfile=${VM_DIR}/autoyast_${VM_NAME_BASE}${NODE_NUMBER}.xml
cp $autoyast_seed $xmlfile
sed -i "s/__ip_default_route__/${VM_HYP_DEF_GW}/" $xmlfile
sed -i "s/__ip_nameserver__/${VM_HYP_DEF_GW}/" $xmlfile
sed -i "s|__ssh_pub_key__|${ssh_pub_key}|" $xmlfile 					
sed -i "s|__os_http_link__|${os_url1}|" $xmlfile
sed -i "s|__ses_http_link_1__|${ses_url1}|" $xmlfile
sed -i "s/ses5hostnameses5/${VM_NAME_BASE}${NODE_NUMBER}/" $xmlfile
sed -i "s/__VMNET_IP_BASE__xxxxx/${VMNET_IP_BASE}.15${NODE_NUMBER}/" $xmlfile
done

CREATE_VM_SCRIPT=${VM_DIR}/create_VMs.sh
> $CREATE_VM_SCRIPT

# check if the installation ISO is available 
[[ -r /var/lib/libvirt/images/$ISO_MEDIA ]] || (echo "ERROR: No installation ISO: /var/lib/libvirt/images/${ISO_MEDIA}";exit 1)

for (( NODE_NUMBER=1; NODE_NUMBER <=$VM_NUM; NODE_NUMBER++ ))
do
echo "virt-install \
--name ${VM_NAME_BASE}$NODE_NUMBER \
--memory 1024 \
--disk path=/VM/${VM_NAME_BASE}$NODE_NUMBER.qcow2,size=20 \
--vcpus 1 \
--network network=${VMNET_NAME},model=virtio \
--os-type linux \
--noautoconsole \
--os-variant ${OS_VARIANT} \
--location /var/lib/libvirt/images/$ISO_MEDIA \
--initrd-inject=${VM_DIR}/autoyast_${VM_NAME_BASE}${NODE_NUMBER}.xml \
--extra-args kernel_args=\"console=/dev/ttyS0 autoyast=file:/${VM_DIR}/autoyast_${VM_NAME_BASE}${NODE_NUMBER}.xml\" " >> $CREATE_VM_SCRIPT
done
chmod +x $CREATE_VM_SCRIPT
source $CREATE_VM_SCRIPT

# checking while all VM shut off
while sleep 1;do runningvms=$(virsh list|tail -n +3);if [[ $runningvms == '' ]];then echo 'NO VMs running...';break;fi;done

# ADDING OSD DISK to VMs
. ${BASEDIR}/exploit/add_OSDs.sh $VM_NAME_BASE $VM_NUM "$OSD_DEST_LIST"

# START ALL VMs
for (( NODE_NUMBER=1; NODE_NUMBER <=$VM_NUM; NODE_NUMBER++ ))
do
	virsh start ${VM_NAME_BASE}${NODE_NUMBER} 
done 

# wait 5min for autoyast to complete
echo "Waiting for autoyast init script to complete... "
sleep 300

# PREPARING SSH PASSWRODLESS EXECUTION
# before to login to the host, check local ssh options 
sed -i '/StrictHostKeyChecking/c\StrictHostKeyChecking no' /etc/ssh/ssh_config

# Waiting for autoyast script to be completed 
TIMEOUT_COUNTER=1
for (( i=1; i <=$VM_NUM; i++ ))
do
	while ! ssh ${VM_NAME_BASE}${i} "tail -n 1 /tmp/initscript.log"|grep 'SCRIPT DONE' >/dev/null
	do
		sleep 5
		echo "Autoyast init script on host ${VM_NAME_BASE}${i} not done..."
		let TIMEOUT_COUNTER=$TIMEOUT_COUNTER+1
	done
	if [[ $TIMEOUT_COUNTER -gt 300 ]]
		then
		echo "TIMEOUT!"
		exit 1
	fi
	echo "Autoyast init script on host ${VM_NAME_BASE}${i} FINISHED."
done


function run_script_remotly {
	# USAGE: run_script_remotly REMOTE_HOST_NAME SCRIPT_PATH
	scp $2 ${1}:/tmp/
	SCRIPT_NAME=${2##*/}
	ssh ${1} /tmp/$SCRIPT_NAME
}

# COPY AND EXECUTE SCRIPT FOR PREPARING SALT MINIONS
for (( i=2; i <=$VM_NUM; i++ )) # MINION NUMBERS ARE STARTING FROM 2
do
	run_script_remotly ${VM_NAME_BASE}${i} ${BASEDIR}/exploit/configure_salt_minion.sh
done
# COPY AND EXECUTE SCRIPT FOR PREPARING SALT MASTER
run_script_remotly $MASTER ${BASEDIR}/exploit/configure_salt_master.sh
# git init 
run_script_remotly $MASTER ${BASEDIR}/exploit/git_init.sh

# RUN TEST
scp ${BASEDIR}/exploit/policy.cfg $MASTER:/tmp/
run_script_remotly $MASTER ${BASEDIR}/ses_qa_scripts/cluster_deploy.sh

# run_script_remotly $MASTER ${BASEDIR}/ses_qa_scripts/rgw_https_deploy.sh

# LRBD_CONF_FILE=lrbd.conf_2tgt_3img_2portal_2pool.json
# scp ${BASEDIR}/exploit/${LRBD_CONF_FILE} $MASTER:/tmp/lrbd.conf.json
# run_script_remotly $MASTER ${BASEDIR}/ses_qa_scripts/igw_deploy.sh

# calculating script execution duration
sript_end_time=$(date +%s)
script_runtime=$(((sript_end_time-sript_start_time)/60))
echo "Runtime in minutes: " $script_runtime