#!/bin/bash -eux
snapcraft clean
snapcraft
snapcraft push ovs-stat_1.2_amd64.snap

echo -e "\nDon't forget to snapcraft release!"
