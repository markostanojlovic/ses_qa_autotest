#!/bin/bash
# openAttic configuration
# Steps already done:
# - added /srv/pillar/ceph/rgw.sls file @cluster_deploy.sh
# - run salt-call state.apply ceph.salt-api @cluster_deploy.sh

# @MASTER:
ACC_KEY=$(radosgw-admin user info --uid=admin|grep "access_key"|awk -F ":" '{print $2}'|tr -d ' ",')
SECRET_KEY=$(radosgw-admin user info --uid=admin|grep "secret_key"|awk -F ":" '{print $2}'|tr -d ' ",')
RGW_API_HOST_NODE=$(_get_fqdn_from_pillar_role rgw|head -n 1)

echo "\
RGW_API_HOST=\"$RGW_API_HOST_NODE\"
RGW_API_PORT=80
RGW_API_SCHEME=\"http\"
RGW_API_ACCESS_KEY=\"$ACC_KEY\"
RGW_API_SECRET_KEY=\"$SECRET_KEY\"
RGW_API_ADMIN_RESOURCE=\"admin\"" >> /tmp/oa_cfg

salt-cp $(_get_fqdn_from_pillar_role openattic) /tmp/oa_cfg  /tmp/
salt -C I@roles:openattic cmd.run "cat /tmp/oa_cfg >> /etc/sysconfig/openattic;cat /etc/sysconfig/openattic"
salt -C I@roles:openattic cmd.run "oaconfig reload"
