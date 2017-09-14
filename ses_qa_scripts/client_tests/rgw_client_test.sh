#!/bin/bash
set -ex 
RGW_HOST=$1
TCP_PORT=$2
curl GET http://$RGW_HOST:$TCP_PORT

