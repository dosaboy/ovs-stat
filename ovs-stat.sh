#!/bin/bash -u
#
# Origin: https://github.com/dosaboy/ovs-stat
#
# Authors:
#  - edward.hope-morley@canonical.com
#  - opentastic@gmail.com
#
root=.
results_path=
force=false
do_show_dataset=false
do_create_dataset=true
do_delete_results=false
compress_dataset=false
archive_tag=

. `dirname $(readlink -f $0)`/common.sh

usage ()
{
echo "USAGE: `basename $0` [OPTS] [datapath]"
echo -e "\nOPTS:"
cat << EOF
    --archive-tag
    --compress
    --overwrite|--force
    --summary
    --results-path|-p (default=TMP)
    --tree
    --help|-h
EOF
echo -e "\nINFO:"
echo "    <datapath> defaults to /"
echo "    <TMP> is a temporary directory"
}

while (($#)); do
    case $1 in
        --results-path|-p)
            results_path="$2"
            shift
            ;;
        --overwrite|--force)
            force=true
            ;;
        --summary)
            do_create_dataset=false
            ;;
        --delete)
            do_delete_results=true
            ;;
        --tree)
            do_show_dataset=true
            ;;
        --compress)
            compress_dataset=true
            ;;
        --archive-tag)
            archive_tag="$2"
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            [ -d "$1" ] || { echo "ERROR: data directory '$1' does not exist"; exit 1; }
            root=$1
            ;;
    esac
    shift
done

# NO CODE HERE, MUST GO AFTER FUNC DEFS

load_namespaces ()
{
    readarray -t namespaces<<<"`get_ip_netns`"
    { ((${#namespaces[@]}==0)) || [ -z "${namespaces[0]}" ]; } && return
    for ns in "${namespaces[@]}"; do
        #NOTE: sometimes ip netns contains (id: <id>) and sometimes it doesnt
        mkdir -p $results_path/linux/namespaces/${ns%% *}
    done
}

load_ovs_bridges()
{
    # loads all bridges in ovs

    readarray -t bridges<<<"`get_ovs_vsctl_show| \
        sed -r 's/.*Bridge\s+\"?([[:alnum:]\-]+)\"*/\1/g;t;d'`"
    mkdir -p $results_path/ovs/bridges
    ((${#bridges[@]})) && [ -n "${bridges[0]}" ] || return
    for bridge in ${bridges[@]}; do
        mkdir -p $results_path/ovs/bridges/$bridge
    done
}

load_ovs_bridges_ports()
{
    # loads all ports on all bridges
    # :requires: load_ovs_bridges

    for bridge in `ls $results_path/ovs/bridges`; do
        readarray -t ports<<<"`get_ovs_ofctl_show $bridge| \
            sed -r 's/^\s+([[:digit:]]+)\((.+)\):\s+.+/\1:\2/g;t;d'`"
        mkdir -p $results_path/ovs/bridges/$bridge/ports
        ((${#ports[@]})) && [ -n "${ports[0]}" ] || continue
        for port in "${ports[@]}"; do
            {
                name=${port##*:}
                id=${port%%:*}

                mkdir -p $results_path/ovs/ports/$name
                ln -s ../../bridges/$bridge \
                    $results_path/ovs/ports/$name/bridge
                ln -s ../../../ports/$name \
                    $results_path/ovs/bridges/$bridge/ports/$id
                echo $id > $results_path/ovs/ports/$name/id

                # is it actually a linux port - create fwd and rev ref
                if `get_ip_link_show| grep -q $name`; then
                    mkdir -p $results_path/linux/ports/$name
                    ln -s ../../../linux/ports/$name \
                        $results_path/ovs/ports/$name/hostnet
                    ln -s ../../../ovs/ports/$name \
                        $results_path/linux/ports/$name/ovs
                fi
            } &
        done
        wait
    done
}

load_bridges_port_vlans ()
{
    # loads all port vlans on all bridges
    # :requires: load_bridges_flow_vlans

    mkdir -p $results_path/ovs/vlans
    for bridge in `ls $results_path/ovs/bridges`; do
        for port in `get_ovs_bridge_ports $bridge`; do
            readarray -t vlans<<<"`get_ovs_vsctl_show $bridge| \
                grep -A 1 \"Port \\\"$port\\\"\"| \
                    sed -r 's/.+tag:\s+([[:digit:]]+)/\1/g;t;d'| \
                    sort -n | uniq`"
            ((${#vlans[@]})) && [ -n "${vlans[0]}" ] || continue
            for vlan in ${vlans[@]}; do
                mkdir -p $results_path/ovs/vlans/$vlan/ports
                ln -s ../../vlans/$vlan \
                    $results_path/ovs/ports/$port/vlan
                ln -s ../../../ports/$port \
                    $results_path/ovs/vlans/$vlan/ports/$port
            done
        done
    done
}

load_bridges_flow_vlans ()
{
    # loads all vlans contained in flows on bridge
    # :requires: load_ovs_bridges

    for bridge in `ls $results_path/ovs/bridges`; do
        readarray -t vlans<<<"`get_ovs_ofctl_dump_flows $bridge| \
                               sed -r -e 's/.+vlan=([[:digit:]]+)[,\s]+.+/\1/g;t;d' \
                                      -e 's/.+vid:([[:digit:]]+)[,\s]+.+/\1/g;t;d'| \
                               sort -n| uniq`"
        flow_vlans_root=$results_path/ovs/bridges/$bridge/flowinfo/vlans
        mkdir -p $flow_vlans_root
        ((${#vlans[@]})) && [ -n "${vlans[0]}" ] || continue
        for vlan in ${vlans[@]}; do
            ln -s ../../../../vlans/$vlan $flow_vlans_root/$vlan
        done
    done
}

load_bridges_port_macs ()
{
    # loads all mac addresses for ports on all bridges
    # :requires: load_ovs_bridges_ports

    for bridge in `ls $results_path/ovs/bridges`; do
        for port in `get_ovs_bridge_ports $bridge`; do
            mac=`get_ovs_ofctl_show $bridge| \
                 sed -r "s/^\s+.+\($port\):\s+addr:(.+)/\1/g;t;d"`
            echo $mac > $results_path/ovs/ports/$port/hwaddr
        done
    done
}

load_bridges_port_ns_attach_info ()
{
    # for each port on each bridge, determine if that port is attached to a
    # a namespace and if it is using a veth pair to do so, get info on the
    # peer interface.

    for bridge in `ls $results_path/ovs/bridges`; do
        for port in `get_ovs_bridge_ports $bridge`; do
            {
            port_suffix=${port##tap}

            # first try linux
            ns_id=`get_ip_link_show| grep -A 1 $port| \
                       sed -r 's/.+link-netnsid ([[:digit:]]+)\s*.*/\1/g;t;d'`
            ns_name=
            if [ -n "$ns_id" ]; then
                ns_name=`get_ip_netns| grep "(id: $ns_id)"| \
                            sed -r 's/\s+\(id:\s+.+\)//g'`
            else
                # then try searching all ns since ovs does not provide info about which namespace a port maps to.
                ns_name="`get_ns_ip_addr_show_all| egrep "netns:|${port_suffix}"| grep -B 1 $port_suffix| head -n 1`" || true
                ns_name=${ns_name##netns: }
            fi

            if [ -n "$ns_name" ]; then
                mkdir -p $results_path/linux/namespaces/$ns_name/ports

                ns_port="`get_ns_ip_addr_show $ns_name| 
                       sed -r \"s,[[:digit:]]+:\s+(.*${port_suffix})(@[[:alnum:]]+)?:\s+.+,\1,g;t;d\"`"

                if [ "$ns_port" = "$port" ]; then
                    is_veth_pair=false
                else
                    is_veth_pair=true
                fi

                if [ -n "$ns_port" ]; then
                    if $is_veth_pair; then
                        if [ -e "$results_path/linux/ports/$port" ]; then
                            mkdir -p $results_path/linux/namespaces/$ns_name/ports/$ns_port
                            ln -s ../../../../ports/$port \
                                $results_path/linux/namespaces/$ns_name/ports/$ns_port/veth_peer

                            ln -s ../../namespaces/$ns_name/ports/$ns_port \
                                $results_path/linux/ports/$port/veth_peer

                            mac="`get_ns_ip_addr_show $ns_name| \
                                  grep -A 1 $port_suffix| \
                                  sed -r 's,.*link/ether\s+([[:alnum:]\:]+).+,\1,g;t;d'`"
                            echo $mac > $results_path/linux/ports/$port/veth_peer/hwaddr
                        else
                            echo "WARNING: ns veth pair peer (host) port $port not found"
                        fi
                    else
                        if [ -e "../../../ports/$port" ]; then
                            ln -s ../../../ports/$port \
                                $results_path/linux/namespaces/$ns_name/ports/$ns_port
                            ln -s ../../../linux/namespaces/$ns_name \
                                $results_path/linux/ports/$ns_port/namespace
                        else
                            ln -s ../../../../ovs/ports/$port \
                                $results_path/linux/namespaces/$ns_name/ports/$ns_port
                            ln -s ../../../linux/namespaces/$ns_name \
                                $results_path/ovs/ports/$ns_port/namespace
                        fi
                    fi
                fi
            fi
            } &
        done
        wait
    done
}

load_bridges_flows ()
{
    for bridge in `ls $results_path/ovs/bridges`; do
        get_ovs_ofctl_dump_flows $bridge > $results_path/ovs/bridges/$bridge/flows
    done    
}

load_bridges_flow_tables ()
{
    for bridge in `ls $results_path/ovs/bridges`; do
        tables_root=$results_path/ovs/bridges/$bridge/flowinfo/tables
        bridge_flows=$results_path/ovs/bridges/$bridge/flows
        readarray -t tables<<<"`sed -r 's/.+table=([[:digit:]]+).+/\1/g;t;d' $bridge_flows| sort -un`"
        for t in "${tables[@]}"; do
            mkdir -p $tables_root/$t
            egrep 'table=[[:digit:]]+,' $bridge_flows > ${tables_root}/${t}/flows
        done
    done
}

load_bridges_port_flows ()
{
    # loads flows for bridges ports and disects.

    for bridge in `ls $results_path/ovs/bridges`; do
        for id in `ls $results_path/ovs/bridges/$bridge/ports/ 2>/dev/null`; do
            {
            flows_root=$results_path/ovs/bridges/$bridge/ports/$id/flows
            port_mac=$results_path/ovs/bridges/$bridge/ports/$id/hwaddr
            hexid=`printf '%x' $id`

            mkdir -p $flows_root
            get_ovs_ofctl_dump_flows $bridge | \
                egrep "in_port=$id[, ]+|output:$id[, ]+|reg5=0x${hexid}[ ,]+|$port_mac" > $flows_root/all

            mkdir -p $flows_root/by-table
            for table in `ls $results_path/ovs/bridges/$bridge/flowinfo/tables`; do
                table_flows=$flows_root/by-table/$table
                egrep "table=$table," $flows_root/all > $table_flows
                [ -s "$table_flows" ] || rm -f $table_flows
            done

            mkdir -p $flows_root/by-proto

            proto_flows_root=$flows_root/by-proto

            proto=$proto_flows_root/dhcp
            grep udp $flows_root/all| egrep "tp_(src|dst)=(67|68)[, ]+" >> $proto
            [ -s "$proto" ] || rm -f $proto

            proto=$proto_flows_root/dns
            egrep "tp_dst=53[, ]+" $flows_root/all >> $proto
            [ -s "$proto" ] || rm -f $proto

            proto=$proto_flows_root/arp
            egrep "arp" $flows_root/all >> $proto
            [ -s "$proto" ] || rm -f $proto

            proto=$proto_flows_root/icmp6
            egrep "icmp6" $flows_root/all >> $proto
            [ -s "$proto" ] || rm -f $proto

            proto=$proto_flows_root/icmp
            egrep "icmp" $flows_root/all| grep -v icmp6 >> $proto
            [ -s "$proto" ] || rm -f $proto

            proto=$proto_flows_root/udp6
            egrep "udp6" $flows_root/all >> $proto
            [ -s "$proto" ] || rm -f $proto

            proto=$proto_flows_root/udp
            egrep "udp" $flows_root/all| grep -v udp6 >> $proto
            [ -s "$proto" ] || rm -f $proto
            } &
        done
        wait
    done    
}


# See neutron/agent/linux/openvswitch_firewall/constants.py
REG_PORT=5
REG_NET=6
REG_REMOTE_GROUP=7

# used by neutron openvswitch firewall driver
load_bridge_flow_regs ()
{
    for bridge in `ls $results_path/ovs/bridges`; do
        readarray -t regs<<<"`get_ovs_ofctl_dump_flows $bridge | \
            sed -r 's/.+(reg[[:digit:]]+)=(0x[[:alnum:]]+).+/\1=\2/g;t;d'| sort -u`"
        regspath=$results_path/ovs/bridges/$bridge/flowinfo/registers
        mkdir -p $regspath
        ((${#regs[@]})) && [ -n "${regs[0]}" ] || continue
        # reg5 is portid
        # reg6 is networkid
        for ((i=0;i<${#regs[@]};i++)); do
            reg=${regs[$i]%%=*}
            val=${regs[$i]##*=}
            # TODO: these should be segregated by vlan
            mkdir -p $regspath/$reg
            if [ "$reg" = "reg$REG_PORT" ]; then
                hex2dec=$((16#${val##*0x}))
                ln -s ../../../ports/$hex2dec \
                    $regspath/$reg/$val  
            elif [ "$reg" = "reg$REG_NET" ]; then
                # is this the vlan ID?
                hex2dec=$((16#${val##*0x}))
                ln -s ../../../../../../ovs/vlans/$hex2dec \
                    $regspath/$reg/$val
            elif [ "$reg" = "reg$REG_REMOTE_GROUP" ]; then
                # TODO: not sure what to do with this yet
                echo "$val" > $regspath/$reg/$val
            else
                echo "$val" > $regspath/$reg/$val
            fi
        done
    done
}

# used by neutron openvswitch firewall driver
load_bridge_conjunctive_flow_ids ()
{
    for bridge in `ls $results_path/ovs/bridges`; do
        readarray -t conj_ids<<<"`cat $results_path/ovs/bridges/$bridge/flows| \
            sed -r 's/.+conj_id=([[:digit:]]+).+/\1/g;t;d'| sort -u`"
        conj_ids_path=$results_path/ovs/bridges/$bridge/flowinfo/conj_ids
        mkdir -p $conj_ids_path
        ((${#conj_ids[@]})) && [ -n "${conj_ids[0]}" ] || continue
        for id in ${conj_ids[@]}; do
            mkdir -p $conj_ids_path/$id
            egrep "conj_id=$id[, ]|conjunction\($id," \
                    $results_path/ovs/bridges/$bridge/flows > \
                $conj_ids_path/$id/flows
        done
    done
}

get_ovs_bridge_port ()
{
    # returns translate bridge port id to port name
    # :requires: load_ovs_bridges_ports

    bridge=$1
    port=$2

    [ -e "$results_path/ovs/bridges/$bridge/ports/$port" ] || return
    readlink -f $results_path/ovs/bridges/$bridge/ports/$port| \
        xargs -l basename
}

get_ovs_bridge_ports ()
{
    # returns list of all ports on bridge
    # :requires: load_ovs_bridges_ports

    bridge=$1

    ((`ls $results_path/ovs/bridges/$bridge/ports/| wc -l`)) || return
    find $results_path/ovs/bridges/$bridge/ports/*| xargs -l readlink -f| \
        xargs -l basename
}

check_error ()
{
    if [ -s "$results_path/error.$$" ]; then
        echo "ERROR: unable to load $1: `cat $results_path/error.$$`"
    fi
    rm -f $results_path/error.$$
}

create_dataset ()
{
    echo -en "\nCreating dataset..."

    # ordering is important!
    load_namespaces 2>$results_path/error.$$; check_error "namespaces"
    load_ovs_bridges 2>$results_path/error.$$; check_error "ovs bridges"
    load_bridges_flows 2>$results_path/error.$$; check_error "bridge flows"
    load_ovs_bridges_ports 2>$results_path/error.$$; check_error "bridge ports"

    load_bridges_port_vlans 2>$results_path/error.$$; check_error "port vlans" &
    load_bridges_flow_tables 2>$results_path/error.$$; check_error "bridge flow tables" &
    load_bridges_flow_vlans 2>$results_path/error.$$; check_error "flow vlans" &
    load_bridges_port_macs 2>$results_path/error.$$; check_error "port macs" &
    load_bridges_port_ns_attach_info 2>$results_path/error.$$; check_error "port ns info" &

    # do this first so that we can use reg5 to identify port flows if it exists
    load_bridge_flow_regs 2>$results_path/error.$$; check_error "flow regs" &
    wait
    # these depend on everything else existing so wait till the rest is finished
    load_bridges_port_flows 2>$results_path/error.$$; check_error "port flows" &
    load_bridge_conjunctive_flow_ids 2>$results_path/error.$$; check_error "conj_ids" &
    wait
    echo "done."
}

show_summary ()
{
    num=`ls $results_path/ovs/ports 2>/dev/null| wc -l`
    echo -e "\nOVS ports:\n  $num"

    echo -e "\nOVS bridge ports:"
    for b in `ls $results_path/ovs/bridges`; do
        echo -n "$b: "
        ls $results_path/ovs/bridges/$b/ports| wc -l
    done | sort -rnk 2| column -t| sed -r 's/^\s*/  /g'

    num=`ls $results_path/ovs/vlans/ 2>/dev/null| wc -l`
    echo -e "\nOVS vlans:\n  $num"

    echo -e "\nTagged ports:"
    for bridge in `ls $results_path/ovs/bridges`; do
        num=`ls -d $results_path/ovs/bridges/$bridge/ports/*/vlan 2>/dev/null| wc -l`
        echo "$bridge: $num"
    done | sort -rnk 2| column -t| sed -r 's/^\s*/  /g'

    num=`ls $results_path/linux/namespaces/ 2>/dev/null| wc -l`
    echo -e "\nLinux namespaces with ovs ports associated (incl. veth pairs):\n  $num"

    num=`ls -d $results_path/ovs/ports/*/hostnet/veth_peer 2>/dev/null| wc -l`
    echo -e "\nOVS ports with namespaced veth peers:\n  $num"

    echo -e "\nNeutron flow registers used:"
    for bridge in `ls $results_path/ovs/bridges`; do
        num=`ls -d $results_path/ovs/bridges/$bridge/flowinfo/registers/* 2>/dev/null| wc -l`
        echo "$bridge: $num"
    done | sort -rnk 2| column -t| sed -r 's/^\s*/  /g'
}

## MAIN ##

tmp_datastore=
cleanup () {
    wait
    if [ -d "$tmp_datastore" ] && $do_delete_results; then
        echo -e "\nDeleting datastore at $tmp_datastore"
        rm -rf $tmp_datastore
    fi
    echo -e "\nDone."
}
trap cleanup EXIT INT

if [ -z "$results_path" ]; then
    tmp_datastore=`mktemp -d`
    results_path=$tmp_datastore
fi

# Add missing slash
[ "${root:(-1)}" = "/" ] || root="${root}/"
if [ -n "${results_path}" ]; then
    [ "${results_path:(-1)}" = "/" ] || results_path="${results_path}/"
fi

# get hostname
hostname=`get_hostname`

results_path=$results_path$hostname
echo "Data source: $root"
echo "Data destination: $results_path"

if $do_create_dataset && [ -e "$results_path" ] && [ -z "$tmp_datastore" ]; then
    if ! $force; then
    echo -e "\nWARNING: $results_path already exists! - skipping create"
        do_create_dataset=false
    else
        rm -rf $results_path
    fi
fi

# top-level structure
mkdir -p $results_path/ovs
mkdir -p $results_path/linux
# next-level
mkdir -p $results_path/ovs/{bridges,ports,vlans}
mkdir -p $results_path/linux/{namespaces,ports}
# the rest is created dynamically

$do_create_dataset && create_dataset

# check for broken symlinks
if ((`find $results_path -xtype l| wc -l`)); then
    echo -e "\n================================================================================"
    echo -e "WARNING: dataset contains broken links.\nExecute 'find $results_path -xtype l' to display them."
    echo -e "================================================================================\n"
fi

show_summary

if $do_show_dataset; then
    echo -e "\nDataset:"
    tree $results_path
fi

if $compress_dataset; then
    target=ovs-stat-${hostname}
    [ -n "$archive_tag" ] && target+="-$archive_tag"
    target+="-`date +%d%m%y.%s`.tgz"
    echo -e "\nCompressing to `pwd`/$target"
    tar -czf $target -C `dirname $results_path` $hostname
fi

