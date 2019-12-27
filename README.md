# ovs-stat
Analysing Openvswitch flow tables can be hard. This tool organises information
from an Openvswitch switch - such as flows and ports - into a filesystem
structure so that conventional tools like find, ls and grep can be used to
perform queries and provide a more intuitive visualisation of the configuration
of an ovs switch.

Run ovs-stat on a system running openvswitch or against a sosreport containing
ovs data (i.e. sos_commands/openvswitch must exist in your sosreport) and it
will create a "dataset" - a sysfs-style representation of bridged, ports, flows
etc along with a summary of what the switch looks like. You can then use
built-in commands e.g. --tree to display the dataset or --compress to create a
tarball of the dataset for export. A dataset root can contain one or more
hostnames representing data from one or more hosts/sosreports allowing for
queries to be run against data from multiple hosts at once.

## Install

`sudo snap install snapd`

NOTE: recent version of snapd needed to get latest support for ovs interface
hence why use the snap version since distro apt package may not be sufficient.

`sudo snap install ovs-stat`

`sudo snap connect ovs-stat:openvswitch`

`sudo snap connect ovs-stat:network-control`

NOTE: if analysing sosreport ovs data where sosreport is on a separate
filesystem you only need this:

`sudo snap connect ovs-stat:removable-media`

## Examples

`sudo ovs-stat -p results`

`sudo ovs-stat -p results --tree`

NOTE: root only needed if running on live openvswitch e.g. for sosreport you
can do:

`ovs-stat -p results /path/to/sosreport-hostA`

`ovs-stat -p results /path/to/sosreport-hostB`

`ovs-stat -p results --host HostA --tree`

`ovs-stat -p results --host HostB --tree`

`find results -name tap-foo`

`ls results/*/ovs/ports/*`

See https://github.com/dosaboy/ovs-stat for more info.
