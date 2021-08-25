#!/bin/bash -eux
snapcraft clean --destructive-mode
snapcraft --destructive-mode
snapcraft upload ovs-stat_1.2_amd64.snap

echo -e "\nDon't forget to snapcraft release!"
