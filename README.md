# ovs-stat
Analysing Openvswitch flow tables can be hard. This tool organises information from
an Openvswitch switch such as flows and ports into a sysfs-style filesystem structure
so that conventional tools like find, ls and grep can be used to perform queries and
provide a more intuitive visualisation of the configuration of an ovs switch.
