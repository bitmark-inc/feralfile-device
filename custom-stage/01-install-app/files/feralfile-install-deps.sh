#!/bin/sh
apt-get update
apt-get -y install $(apt-cache depends feralfile-launcher | awk '{print $2}' | grep -v '<' | xargs)