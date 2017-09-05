#!/bin/bash
# Deployment of iSCSI gateway
# This script should be run from master node 
# Template lrbd config file should be copied to /tmp/lrbd.conf.json

function _get_fqdn_from_pillar_role {
	# input argument is salt grain key
	salt -C I@roles:${1} grains.item fqdn --out yaml|grep fqdn|sed 's/fqdn: //g'|tr -d ' '
}

cp /tmp/lrbd.conf.json /tmp/lrbd.conf.custom
LRBD_CONF_FILE=/tmp/lrbd.conf.custom
APPLY_NEW_IGW_CONFIG=/tmp/apply_new_igw_config.sh

TARGET1=target1
TARGET2=target2
RBD_POOL1_NAME=iscsi-pool-01
RBD_POOL2_NAME=igw-pool-01
RBD_POOL1_IMG_1=img-001
RBD_POOL1_IMG_2=img-002
RBD_POOL2_IMG_1=img-003
RBD_POOL2_IMG_2=img-004

i=1
for node in $(_get_fqdn_from_pillar_role igw)
do
	declare HOST${i}_FQDN=$node;
	declare HOST${i}_NAME=${node%%\.*};
	declare PORTAL_IP_ADDR${i}=$(ping -c 1 $node|head -n 1|awk '{print $3}'|tr -d '()')
	let i+=1
done

echo $HOST1_NAME
echo $HOST2_NAME
echo $PORTAL_IP_ADDR1

# creating pools and rbd images:
ceph osd pool create $RBD_POOL1_NAME 8 8 
ceph osd pool create $RBD_POOL2_NAME 8 8 

rbd -p ${RBD_POOL1_NAME} ls|grep ${RBD_POOL1_IMG_1} || rbd create ${RBD_POOL1_NAME}/${RBD_POOL1_IMG_1} --size=1G
rbd -p ${RBD_POOL1_NAME} ls|grep ${RBD_POOL1_IMG_2} || rbd create ${RBD_POOL1_NAME}/${RBD_POOL1_IMG_2} --size=2G
rbd -p ${RBD_POOL2_NAME} ls|grep ${RBD_POOL2_IMG_1} || rbd create ${RBD_POOL2_NAME}/${RBD_POOL2_IMG_1} --size=3G
rbd -p ${RBD_POOL2_NAME} ls|grep ${RBD_POOL2_IMG_2} || rbd create ${RBD_POOL2_NAME}/${RBD_POOL2_IMG_2} --size=4G

sed -i "\
s|__HOST1_FQDN__|${HOST1_FQDN}|;\
s|__HOST2_FQDN__|${HOST2_FQDN}|;\
s|__HOST1_NAME__|${HOST1_NAME}|;\
s|__HOST2_NAME__|${HOST2_NAME}|;\
s|__PORTAL_IP_ADDR1__|${PORTAL_IP_ADDR1}|;\
s|__PORTAL_IP_ADDR2__|${PORTAL_IP_ADDR2}|;\
s|__RBD_POOL1_IMG_1__|${RBD_POOL1_IMG_1}|;\
s|__RBD_POOL1_IMG_2__|${RBD_POOL1_IMG_2}|;\
s|__RBD_POOL2_IMG_1__|${RBD_POOL2_IMG_1}|;\
s|__RBD_POOL2_IMG_2__|${RBD_POOL2_IMG_2}|;\
s|__TARGET1__|${TARGET1}|;\
s|__TARGET2__|${TARGET2}|;\
s|__RBD_POOL1_NAME__|${RBD_POOL1_NAME}|;\
s|__RBD_POOL2_NAME__|${RBD_POOL2_NAME}|" $LRBD_CONF_FILE

cat << 'EOF' > $APPLY_NEW_IGW_CONFIG
#!/bin/bash
LRBD_CONF_FILE=/tmp/lrbd.conf.custom
lrbd -C
source /etc/sysconfig/lrbd;lrbd -v $LRBD_OPTIONS -f $LRBD_CONF_FILE
lrbd
targetcli ls
EOF

for node in $(_get_fqdn_from_pillar_role igw)
do
	salt-cp $node $LRBD_CONF_FILE $LRBD_CONF_FILE
	salt-cp $node $APPLY_NEW_IGW_CONFIG $APPLY_NEW_IGW_CONFIG
	salt $node cmd.run "/bin/bash $APPLY_NEW_IGW_CONFIG"
	
done
