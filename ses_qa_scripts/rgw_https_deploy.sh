#!/bin/bash
BASEDIR=$(pwd)
echo $BASEDIR |grep DeepSea/qa || BASEDIR=$(find / -type d -name DeepSea)/qa
source $BASEDIR/common/helper.sh

RGW_NODE_fqdn=$(_get_fqdn_from_pillar_role rgw|tail -n 1) 	# choosing only one node to deploy HTTPS
RGW_NODE=${RGW_NODE_fqdn%%\.*}
[[ -z $RGW_NODE ]] && (echo "Couldn't find RGW node name."; exit 1)
echo "RGW node for deploying https: " $RGW_NODE_fqdn
# set a grain if needed to be used later
salt $RGW_NODE_fqdn grains.setval RGW_HTTPS True

[[ -d /srv/salt/ceph/rgw/cert ]] && cd /srv/salt/ceph/rgw/cert || mkdir /srv/salt/ceph/rgw/cert
openssl req -x509 -nodes -days 1095 -newkey rsa:4096 -keyout rgw.key -out rgw.crt -subj "/C=CZ/ST=Praha/L=Prague/O=SUSEQA/OU=QA/CN=qatest"
cat rgw.key > rgw.pem && cat rgw.crt >> rgw.pem

echo "\
[ client.{{ client }} ]
rgw frontends = "civetweb port=443s ssl_certificate=/etc/ceph/rgw.pem"
rgw dns name = {{ grains['host'] }}" > /srv/salt/ceph/configuration/files/ceph.conf.rgw

echo "\
include:
  - .{{ salt['pillar.get']('rgw_init', 'default') }}
  - .cert" > /srv/salt/ceph/rgw/init.sls

echo "\
deploy the rgw.pem file:
  file.managed:
    - name: /etc/ceph/rgw.pem
    - source: salt://ceph/rgw/cert/rgw.pem" > /srv/salt/ceph/rgw/cert/init.sls

salt-run state.orch ceph.stage.2
salt-run state.orch ceph.stage.4

echo "\
[client.rgw.${RGW_NODE}]
rgw_frontends = civetweb port=443s ssl_certificate=/etc/ceph/rgw.pem " >> /etc/ceph/ceph.conf
salt-cp '*' '/etc/ceph/ceph.conf' '/etc/ceph/'

salt -C 'I@roles:rgw' cmd.run 'systemctl restart ceph-radosgw@*'
salt -C 'I@roles:rgw' cmd.run 'systemctl status ceph-radosgw@*'
salt -C 'I@roles:rgw' cmd.run 'ss -n -l -p|grep rados'

# check if the port is OK
RGW_TCP_PORT=$(salt $RGW_NODE_fqdn cmd.run "ss -l -p -n|grep tcp|grep rados"|awk '{print $5}') # should be *:443
echo $RGW_TCP_PORT|grep 443 || (echo "Error: RGW TCP listening port NOT_OK."; exit 1)

# check if the curl gets html page
TEST_RESULT=$(curl --insecure https://${RGW_NODE})
echo $TEST_RESULT|grep ListAllMyBucketsResult || (echo "Error: no result from curl get. NOT_OK."; exit 1)

echo 'Result: OK'

# # manually copy files:
# cp /srv/salt/ceph/rgw/cert/rgw.pem /etc/ceph/rgw.pem
# salt-cp -C 'I@roles:rgw' '/etc/ceph/rgw.pem' '/etc/ceph/'
# # or manually execute sls file: 
# salt -C 'I@roles:rgw' state.sls ceph.rgw.cert.init

