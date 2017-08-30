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
# - TODO: OSD VM disk images 
# - VM names are $VM_NAME_BASE and incrementing suffix number - hardcoded to "ses5node"
# - SALT MASTER node is the first VM "ses5node1"
# - 
#
#
#######################################################################################

BASEDIR=$(pwd)
VM_DIR=/VM
# TODO: Create separate directory for OSD VM images 

sript_start_time=$(date +%s)

REPO_FILE=${BASEDIR}/exploit/REPO_ISO_URLs
[[ -r $REPO_FILE ]] || (echo "ERROR: No REPO file."; exit 1)
lin_num=1
while read linija;do link[lin_num]=$linija;let lin_num+=1
done <$REPO_FILE

VM_NAME_BASE='ses5node'
MASTER=${VM_NAME_BASE}1

VM_HYP_DEF_GW=$(ip a s dev virbr1|grep inet|awk '{print $2}'| cut -d/ -f1)	# EXAMPLE: 192.168.100.1
VMNET_IP_BASE=${VM_HYP_DEF_GW%\.*}											# EXAMPLE: 192.168.100

OS_VARIANT=sles12sp3
os_url1=${link[1]}
ses_url1=${link[2]}
#ses_url2=${link[3]}
#ses_url3=${link[4]}

# Repo media ISOs: 
ISO_MEDIA=${os_url1##*/}
ISO_MEDIA_SES_1=${ses_url1##*/}
#ISO_MEDIA_SES_2=${ses_url2##*/}
#ISO_MEDIA_SES_3=${ses_url3##*/}

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
# Preparing the environment 
echo "Preparing the environment..." 
###############################
# VMs are existing?
echo "Checking if VMs are existing..." 
NO_VMs=0
virsh list --all|grep ${VM_NAME_BASE}||NO_VMs=1

# TODO make it to destroy variable number of VMs

if [[ $NO_VMs = 0 ]] 
then
# Force stop VMs (even if they are not running)
virsh destroy ${VM_NAME_BASE}1 2>/dev/null
virsh destroy ${VM_NAME_BASE}2 2>/dev/null
virsh destroy ${VM_NAME_BASE}3 2>/dev/null
virsh destroy ${VM_NAME_BASE}4 2>/dev/null
virsh destroy ${VM_NAME_BASE}5 2>/dev/null
# Remove VMs
# Undefine VMs (--nvram option for aarch64)
virsh undefine ${VM_NAME_BASE}1 --nvram
virsh undefine ${VM_NAME_BASE}2 --nvram
virsh undefine ${VM_NAME_BASE}3 --nvram
virsh undefine ${VM_NAME_BASE}4 --nvram
virsh undefine ${VM_NAME_BASE}5 --nvram
fi

# TODO: 
# Create a script/function that will check available disk space and according to it,
# assign and create virtual disk for VMs 
# This should be also requirement for the number of VMs to deploy

# Delete disk images 
rm ${VM_DIR}/${VM_NAME_BASE}*

> ~/.ssh/known_hosts

###############################
# NUMBER of VMs to deploy #TODO - moralo bi se promeni for petlja i da se ubaci brojac za racunanje IP adresa
# Limitation : setting the max number of VMs to create to 100
# Disk space has to be calculated 
VM_NUM=5
MAX_VM_NUM=100

# Generate autoyast xml files:					# TODO: zameni ove vrednosti sa varijablama u INIT fajlu
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
#sed -i "s|__ses_http_link_2__|${ses_url2}|" $xmlfile
#sed -i "s|__ses_http_link_3__|${ses_url3}|" $xmlfile
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

# TODO make it so that custom number of disks and their size can be set in some config file 
# TODO make it for the variable number of VMs
# adding disks to VMs
qemu-img create -f raw ${VM_DIR}/${VM_NAME_BASE}2-osd-1 30G
qemu-img create -f raw ${VM_DIR}/${VM_NAME_BASE}3-osd-1 30G
qemu-img create -f raw ${VM_DIR}/${VM_NAME_BASE}4-osd-1 30G
qemu-img create -f raw ${VM_DIR}/${VM_NAME_BASE}5-osd-1 30G
qemu-img create -f raw ${VM_DIR}/${VM_NAME_BASE}4-osd-2 25G
qemu-img create -f raw ${VM_DIR}/${VM_NAME_BASE}5-osd-2 25G
qemu-img create -f raw ${VM_DIR}/${VM_NAME_BASE}5-osd-3 40G
virsh attach-disk ${VM_NAME_BASE}2 ${VM_DIR}/${VM_NAME_BASE}2-osd-1 sdb --config --cache none 
virsh attach-disk ${VM_NAME_BASE}3 ${VM_DIR}/${VM_NAME_BASE}3-osd-1 sdb --config --cache none
virsh attach-disk ${VM_NAME_BASE}4 ${VM_DIR}/${VM_NAME_BASE}4-osd-1 sdb --config --cache none
virsh attach-disk ${VM_NAME_BASE}5 ${VM_DIR}/${VM_NAME_BASE}5-osd-1 sdb --config --cache none
virsh attach-disk ${VM_NAME_BASE}4 ${VM_DIR}/${VM_NAME_BASE}4-osd-2 sdc --config --cache none
virsh attach-disk ${VM_NAME_BASE}5 ${VM_DIR}/${VM_NAME_BASE}5-osd-2 sdc --config --cache none
virsh attach-disk ${VM_NAME_BASE}5 ${VM_DIR}/${VM_NAME_BASE}5-osd-3 sdd --config --cache none
# start all VMs
virsh start ${VM_NAME_BASE}1
virsh start ${VM_NAME_BASE}2
virsh start ${VM_NAME_BASE}3
virsh start ${VM_NAME_BASE}4
virsh start ${VM_NAME_BASE}5

# wait 5min for autoyast to complete
echo "Waiting for autoyast init script to complete... "
sleep 300

# PREPARING SSH PASSWRODLESS EXECUTION
# check if hosts file is ok
grep ${VM_NAME_BASE} /etc/hosts >/dev/null 2>&1 || echo "\
${VMNET_IP_BASE}.151    ${VM_NAME_BASE}1.qatest ${VM_NAME_BASE}1
${VMNET_IP_BASE}.152    ${VM_NAME_BASE}2.qatest ${VM_NAME_BASE}2
${VMNET_IP_BASE}.153    ${VM_NAME_BASE}3.qatest ${VM_NAME_BASE}3
${VMNET_IP_BASE}.154    ${VM_NAME_BASE}4.qatest ${VM_NAME_BASE}4
${VMNET_IP_BASE}.155    ${VM_NAME_BASE}5.qatest ${VM_NAME_BASE}5
" >> /etc/hosts
# before to login to the host, check local ssh options 
sed -i '/StrictHostKeyChecking/c\StrictHostKeyChecking no' /etc/ssh/ssh_config

# Checking if the ssh passwordless access is working
timeout 10 ssh $MASTER || (echo "ERROR: Can't establish ssh connection to master host. "; exit 255)

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
ssh $MASTER "salt '*' grains.setval deepsea True"
scp ${BASEDIR}/exploit/policy.cfg $MASTER:/tmp/
run_script_remotly $MASTER ${BASEDIR}/ses_qa_scripts/cluster_deploy.sh
# run_script_remotly $MASTER ${BASEDIR}/ses_qa_scripts/rgw_https_deploy.sh
LRBD_CONF_FILE=lrbd.conf_1tgt_2img_1portal_1pool.json
scp ${BASEDIR}/exploit/${LRBD_CONF_FILE} $MASTER:/tmp/lrbd.conf.json
run_script_remotly $MASTER ${BASEDIR}/ses_qa_scripts/igw_deploy.sh

# calculating script execution duration
sript_end_time=$(date +%s)
script_runtime=$(((sript_end_time-sript_start_time)/60))
echo "Runtime in minutes: " $script_runtime
