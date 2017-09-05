#!/bin/bash

# Script for perfoming basic checks of Ceph cluster
# Executed on MASTER node

set -ex 

ceph health detail
ceph -s
ceph osd lspools
ceph osd pool ls
ceph osd pool create test-pool 8 8 replicated
ceph osd pool ls|grep test
ceph osd pool rename test-pool pool-test
ceph osd pool application enable pool-test rbd
ceph mon stat
ceph mon_status -f json-pretty
ceph mon dump
ceph quorum_status -f json-pretty
ceph osd stat
ceph osd tree
rados df
ceph df 

# PGs - placement groups 
ceph osd pool get pool-test pg_num
ceph osd pool get pool-test all
ceph osd pool set pool-test pg_num 16
ceph osd pool set pool-test pgp_num 16
ceph pg dump_stuck inactive
ceph pg dump_stuck unclean
ceph pg dump_stuck stale
ceph pg ls|head
ceph pg map $(ceph pg ls|tail -n 1|awk '{print $1}')

# RBD 
ceph osd pool create vm-pool 32 32
ceph osd pool application enable vm-pool rbd
ceph osd pool create rbd-disks 8 8 
ceph osd pool application enable rbd-disks rbd

rbd create vm-img --size 1024 --pool vm-pool
rbd ls vm-pool
rbd --image vm-img -p vm-pool info
rbd resize --size 2048 --image vm-img -p vm-pool
rbd rm vm-img -p vm-pool

#RBD-snapshots 
rbd create vm-img --size 1024 --pool vm-pool # creating a disk
rbd snap create vm-pool/vm-img@vm-img_snapname_test_date
rbd snap ls vm-pool/vm-img

# Cache tiering 
ceph osd pool create cold-storage 32 32 replicated
ceph osd pool create hot-storage 32 32 replicated
ceph osd pool ls|egrep 'hot|cold'
ceph osd tier add cold-storage hot-storage
ceph osd tier cache-mode hot-storage writeback
ceph osd tier set-overlay cold-storage hot-storage
ceph osd pool set hot-storage hit_set_type bloom
ceph health 
ceph -s
ceph osd tier remove-overlay cold-storage
ceph osd tier remove cold-storage hot-storage

# Erasure coding 
ceph osd erasure-code-profile ls
ceph osd erasure-code-profile get default 
ceph osd erasure-code-profile set EC-temp-pool	

# ceph osd erasure-code-profile set EC-temp-pool ruleset-failure-domain=osd k=4 m=2 --force
ceph osd erasure-code-profile set EC-temp-pool crush-failure-domain=osd k=4 m=2 
ceph osd erasure-code-profile set EC-temp-pool crush-failure-domain=osd k=4 m=2 --force

ceph osd erasure-code-profile get EC-temp-pool

ceph osd pool create ECtemppool 8 8  erasure EC-temp-pool
ceph osd pool application enable ECtemppool rbd

base64 /dev/urandom | head --bytes=10MB > /tmp/object-A
rados -p ECtemppool put object.1 /tmp/object-A	
rados -p ECtemppool ls
ceph osd map ECtemppool object.1

# RBD
ceph osd pool create rbd-test 32 32 replicated
ceph osd pool application enable rbd-test rbd
rbd create rbd-test/test_img_1 --size 102400
rbd create rbd-test/test_img_2 --size 10240
rados df -p rbd-test
rados ls -p rbd-test -



