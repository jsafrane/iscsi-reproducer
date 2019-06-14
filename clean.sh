#!/bin/bash

# Clean up any leftovers from the tests.
sudo iscsiadm -m node --logout
sudo iscsiadm -m node -o delete
docker stop `docker ps -qa`; docker rm `docker ps -qa`
sudo targetcli clearconfig confirm=true
sudo /bin/rm -rf /srv/iscsi
sudo /bin/rm -rf /mnt/test

