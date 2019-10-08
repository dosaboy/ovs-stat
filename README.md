# ovs-stat
Analysing Openvswitch flow tables can be hard. This tool organises information from
an Openvswitch switch such as flows and ports into a sysfs-style filesystem structure
so that conventional tools like find, ls and grep can be used to perform queries and
provide a more intuitive visualisation of the configuration of an ovs switch.

## Usage

To use this tool you can either clone this repo and run directly or you can install
as a snap as follows:

```
sudo snap install ovs-stat

# for analysing ovs itself 
sudo snap connect ovs-stat:openvswitch
sudo snap connect ovs-stat:network-control

# for analysing sosreport ovs data where sosreport is on a seperate filesystem
sudo snap connect ovs-stat:removable-media

```

Then you can either run on a host that is running openswitch or against a sosreport that contains openvswitch data e.g.

`sudo ovs-stat -p /tmp/results --tree`

or

`ovs-stat -p /tmp/results --tree ./sosreport-data`
