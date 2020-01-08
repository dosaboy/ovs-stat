# ovs-stat

Analysing Openvswitch flow tables can be hard, particularly if they are large.
This tool organises information from an Openvswitch switch - such as flows and
ports - into a filesystem structure so that conventional tools like find, ls
and grep can be used to perform queries and provide a more intuitive
visualisation of the configuration of an ovs switch.

Run ovs-stat on a system running openvswitch or against a sosreport containing
ovs data (i.e. sos_commands/openvswitch must exist in your sosreport) and it
will create a "dataset" - a sysfs-style representation of bridges, ports, flows
etc - along with a summary of what the switch looks like. You can then use
built-in commands e.g. --tree to display the dataset or --compress to create a
tarball of the dataset for export. A dataset root can contain one or more
hostnames representing data from one or more hosts/sosreports allowing for
queries to be run against data from multiple hosts at once.

## Install

See https://github.com/dosaboy/ovs-stat for installation and usage info.

