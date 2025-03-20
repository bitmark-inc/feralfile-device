#!/bin/sh
apt-get update
apt-get clean
apt-get -y install $(apt-cache depends feralfile-launcher | awk '{print $2}' | sed 's/[<>]//g' | xargs)