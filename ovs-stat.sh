#!/bin/bash -u
#
# Origin: https://github.com/dosaboy/ovs-stat
#
# Authors:
#  - edward.hope-morley@canonical.com
#  - opentastic@gmail.com
#
OVS_FS_DATA_SOURCE=
RESULTS_PATH_ROOT=
RESULTS_PATH_HOST=
ARCHIVE_TAG=
TREE_DEPTH=
FORCE=false
MAX_PARALLEL_JOBS=32
SCRATCH_AREA=`mktemp -d`
TMP_DATASTORE=
HOSTNAME=

declare -A DO_ACTIONS=(
    [SHOW_DATASET]=false
    [CREATE_DATASET]=true
    [DELETE_DATASET]=false
    [SHOW_SUMMARY]=true
    [SHOW_FOOTER]=true
    [QUIET]=false
    [SHOW_NEUTRON_ERRORS]=false
    [COMPRESS_DATASET]=false
)

# See neutron/agent/linux/openvswitch_firewall/constants.py
REG_PORT=5
REG_NET=6
REG_REMOTE_GROUP=7

. `dirname $(readlink -f $0)`/common.sh

usage ()
{
cat << EOF
USAGE: ovs-stat [OPTIONS] [SOSREPORT]

This tool can be used in different ways. The main use case is against a host
running an Openvswitch switch whereby running with all defaults will generate a
sysfs-style representation "dataset" of your switch in \$TMPDIR. You can then
run your own searches against this data or use some of the builtin commands
provided here. By default a dataset is not clobbered by subsequent runs.

If you have a sosreport taken from a host running Openvswitch then you can also
run this tool against that data and it will use that as input for the dataset.
This is useful if, for example, you want to collect data from multiple hosts
and query it all in one place.

One interesting feature of this tool is that it can sometimes simplify
identifying broken configuration such as flows or port config. This is by
virtue of the fact that the dataset is comprised largely of bi-directional
references between resources. If both ends don't point to each other you know
something is probably up. As a result, when broken references are detected a
warning message is displayed.

OPTIONS:
    --archive-tag <tag>
        Name tag used with --compress.

    --compress
        Create a tarball of the resulting dataset and names it with a tag if
        provided by --archive-tag.

    --delete
        Delete datastore once finished (i.e. on exit).

    -h, --help
        Print this usage output.

    --host
        Optionally provided hostname. This is used when you want to run commands
        like --tree against an existing dataset that contains data from
        multiple hosts.

    -j, --max-parallel-jobs
        Some tasks will run in parallel with a maxiumum of $MAX_PARALLEL_JOBS
        jobs. This options allows the maxium to be overriden.

    -L|--depth <int>
        Max directory depth to display when running the tree command (--tree).

    --overwrite, --force
        By default if the dataset path already exists it will be treated as
        readonly unless this option is provided in which case all data is wiped
        prior to creating the dataset.

    -p, --results-path <dir>
        Path in which to create dataset. If no path is provided, a temporary
        directory is created in \$TMPDIR.

    -q, --quiet
        Do not display any debug or summary output.

    -s, --summary
        Only display summary.

    --show-neutron-errors
        Display occurences that indicate issues when Openvswitch is being used
        with Openstack Neutron.

    --tree
        Run the tree command on the resulting dataset. You can control the
        depth of the tree displayed with --depth.

SOSREPORT:
    As opposed to running against a live Openvswitch switch, you can optionally
    point ovs-stat to a sosreport containing ovs data i.e.
    sos_commands/openvswitch must exist and contain a complete collection of
    data from Openvswitch.

EOF
}

while (($#)); do
    case $1 in
        --archive-tag)
            ARCHIVE_TAG="$2"
            shift
            ;;
        --delete)
            DO_ACTIONS[DELETE_DATASET]=true
            ;;
        --debug)
            set -x
            ;;
        -L|--depth)
            TREE_DEPTH="$2"
            shift
            ;;
        --compress)
            DO_ACTIONS[COMPRESS_DATASET]=true
            ;;
        --host)
            HOSTNAME="$2"
            shift
            ;;
        -j|--max-parallel-jobs)
            MAX_PARALLEL_JOBS=$2
            shift
            ;;
        --overwrite|--force)
            FORCE=true
            ;;
        -q|--quiet)
            DO_ACTIONS[QUIET]=true
            DO_ACTIONS[SHOW_SUMMARY]=false
            ;;
        -p|--results-path)
            RESULTS_PATH_ROOT="$2"
            shift
            ;;
        -s|--summary)
            DO_ACTIONS[SHOW_SUMMARY]=true
            ;;
        --show-neutron-errors)
            DO_ACTIONS[SHOW_NEUTRON_ERRORS]=true
            ;;
        --tree)
            DO_ACTIONS[SHOW_DATASET]=true
            DO_ACTIONS[SHOW_SUMMARY]=false
            DO_ACTIONS[SHOW_FOOTER]=false
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            [ -e "$1" ] || { echo "ERROR: path '$1' does not exist"; exit 1; }
            OVS_FS_DATA_SOURCE=$1
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
        mkdir -p $RESULTS_PATH_HOST/linux/namespaces/${ns%% *}
    done
}

load_ovs_bridges()
{
    # loads all bridges in ovs

    readarray -t bridges<<<"`get_ovs_vsctl_show| \
        sed -r 's/.*Bridge\s+\"?([[:alnum:]\-]+)\"*/\1/g;t;d'`"
    mkdir -p $RESULTS_PATH_HOST/ovs/bridges
    ((${#bridges[@]})) && [ -n "${bridges[0]}" ] || return
    for bridge in ${bridges[@]}; do
        mkdir -p $RESULTS_PATH_HOST/ovs/bridges/$bridge
    done
}

load_ovs_bridges_ports()
{
    # loads all ports on all bridges
    # :requires: load_ovs_bridges

    current_jobs=0
    for bridge in `ls $RESULTS_PATH_HOST/ovs/bridges`; do
        readarray -t ports<<<"`get_ovs_ofctl_show $bridge| \
            sed -r 's/^\s+([[:digit:]]+)\((.+)\):\s+.+/\1:\2/g;t;d'`"
        mkdir -p $RESULTS_PATH_HOST/ovs/bridges/$bridge/ports
        ((${#ports[@]})) && [ -n "${ports[0]}" ] || continue
        for port in "${ports[@]}"; do
            {
                name=${port##*:}
                id=${port%%:*}

                mkdir -p $RESULTS_PATH_HOST/ovs/ports/$name
                ln -s ../../bridges/$bridge \
                    $RESULTS_PATH_HOST/ovs/ports/$name/bridge
                ln -s ../../../ports/$name \
                    $RESULTS_PATH_HOST/ovs/bridges/$bridge/ports/$id
                echo $id > $RESULTS_PATH_HOST/ovs/ports/$name/id

                # is it actually a linux port - create fwd and rev ref
                if `get_ip_link_show| grep -q $name`; then
                    mkdir -p $RESULTS_PATH_HOST/linux/ports/$name
                    ln -s ../../../linux/ports/$name \
                        $RESULTS_PATH_HOST/ovs/ports/$name/hostnet
                    ln -s ../../../ovs/ports/$name \
                        $RESULTS_PATH_HOST/linux/ports/$name/ovs
                fi
            } &
            job_wait $((++current_jobs)) && wait
        done
        wait
    done
}

load_bridges_port_vlans ()
{
    # loads all port vlans on all bridges
    # :requires: load_bridges_flow_vlans

    mkdir -p $RESULTS_PATH_HOST/ovs/vlans
    for bridge in `ls $RESULTS_PATH_HOST/ovs/bridges`; do
        for port in `get_ovs_bridge_ports $bridge`; do
            readarray -t vlans<<<"`get_ovs_vsctl_show $bridge| \
                grep -A 1 \"Port \\\"$port\\\"\"| \
                    sed -r 's/.+tag:\s+([[:digit:]]+)/\1/g;t;d'| \
                    sort -n | uniq`"
            ((${#vlans[@]})) && [ -n "${vlans[0]}" ] || continue
            for vlan in ${vlans[@]}; do
                mkdir -p $RESULTS_PATH_HOST/ovs/vlans/$vlan/ports
                ln -s ../../vlans/$vlan \
                    $RESULTS_PATH_HOST/ovs/ports/$port/vlan
                ln -s ../../../ports/$port \
                    $RESULTS_PATH_HOST/ovs/vlans/$vlan/ports/$port
            done
        done
    done
}

load_bridges_flow_vlans ()
{
    # loads all vlans contained in flows on bridge
    # :requires: load_ovs_bridges

    for bridge in `ls $RESULTS_PATH_HOST/ovs/bridges`; do
        readarray -t vlans<<<"`get_ovs_ofctl_dump_flows $bridge| \
                               sed -r -e 's/.+vlan=([[:digit:]]+)[,\s]+.+/\1/g;t;d' \
                                      -e 's/.+vid:([[:digit:]]+)[,\s]+.+/\1/g;t;d'| \
                               sort -n| uniq`"
        flow_vlans_root=$RESULTS_PATH_HOST/ovs/bridges/$bridge/flowinfo/vlans
        mkdir -p $flow_vlans_root
        ((${#vlans[@]})) && [ -n "${vlans[0]}" ] || continue
        for vlan in ${vlans[@]}; do
            ln -s ../../../../vlans/$vlan $flow_vlans_root/$vlan
        done
    done
}

load_bridges_port_macs ()
{
    # loads mac addresses for ports on all bridges where mac was not found by
    # other means.
    # :requires: load_ovs_bridges_ports

    for bridge in `ls $RESULTS_PATH_HOST/ovs/bridges`; do
        for port in `get_ovs_bridge_ports $bridge`; do
            [ -e "$RESULTS_PATH_HOST/ovs/ports/$port/hwaddr" ] && continue
            mac=`get_ovs_ofctl_show $bridge| \
                 sed -r "s/^\s+.+\($port\):\s+addr:(.+)/\1/g;t;d"`
            echo $mac > $RESULTS_PATH_HOST/ovs/ports/$port/hwaddr
        done
    done
}

job_wait ()
{
    local current_jobs=$1

    if ((current_jobs)) && ! ((current_jobs % MAX_PARALLEL_JOBS)); then
        return 0
    else
        return 1
    fi
}

load_bridges_port_ns_attach_info ()
{
    # for each port on each bridge, determine if that port is attached to a
    # a namespace and if it is using a veth pair to do so, get info on the
    # peer interface.

    current_jobs=0
    for bridge in `ls $RESULTS_PATH_HOST/ovs/bridges`; do
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
                mkdir -p $RESULTS_PATH_HOST/linux/namespaces/$ns_name/ports
                if_id=`get_ip_link_show| grep $port| sed -r "s/.+${port}@if([[:digit:]]+):\s+.+/\1/g"`

                if [ -n "$if_id" ]; then
                    ns_port="`get_ns_ip_addr_show $ns_name| 
                           sed -r \"s,^${if_id}:\s+(.+)@[[:alnum:]]+:\s+.+,\1,g;t;d\"`"
                else
                    ns_port="`get_ns_ip_addr_show $ns_name| 
                           sed -r \"s,[[:digit:]]+:\s+(.*${port_suffix})(@[[:alnum:]]+)?:\s+.+,\1,g;t;d\"`"
                fi

                if [ -n "$ns_port" ]; then
                    if [ "$ns_port" != "$port" ]; then
                        # it is a veth peer
                        if [ -e "$RESULTS_PATH_HOST/linux/ports/$port" ]; then
                            mkdir -p $RESULTS_PATH_HOST/linux/namespaces/$ns_name/ports/$ns_port
                            ln -s ../../../../ports/$port \
                                $RESULTS_PATH_HOST/linux/namespaces/$ns_name/ports/$ns_port/veth_peer

                            ln -s ../../namespaces/$ns_name/ports/$ns_port \
                                $RESULTS_PATH_HOST/linux/ports/$port/veth_peer

                            mac="`get_ns_ip_addr_show $ns_name| \
                                  grep -A 1 $port_suffix| \
                                  sed -r 's,.*link/ether\s+([[:alnum:]\:]+).+,\1,g;t;d'`"
                            echo $mac > $RESULTS_PATH_HOST/linux/ports/$port/veth_peer/hwaddr
                        else
                            echo "WARNING: ns veth pair peer (host) port $port not found"
                        fi
                    else
                        if [ -e "../../../ports/$port" ]; then
                            ln -s ../../../ports/$port \
                                $RESULTS_PATH_HOST/linux/namespaces/$ns_name/ports/$ns_port
                            ln -s ../../../linux/namespaces/$ns_name \
                                $RESULTS_PATH_HOST/linux/ports/$ns_port/namespace
                            port_path="$RESULTS_PATH_HOST/linux/ports/$ns_port"
                        else
                            ln -s ../../../../ovs/ports/$port \
                                $RESULTS_PATH_HOST/linux/namespaces/$ns_name/ports/$ns_port
                            ln -s ../../../linux/namespaces/$ns_name \
                                $RESULTS_PATH_HOST/ovs/ports/$ns_port/namespace
                            port_path="$RESULTS_PATH_HOST/ovs/ports/$ns_port"
                        fi
                        mac="`get_ns_ip_addr_show $ns_name| \
                              grep -A 1 $port| \
                              sed -r 's,.*link/ether\s+([[:alnum:]\:]+).+,\1,g;t;d'`"
                        echo $mac > $port_path/hwaddr
                    fi
                fi
            fi
            } &
            job_wait $((++current_jobs)) && wait
        done
        wait
    done
}

load_bridges_flows ()
{
    for bridge in `ls $RESULTS_PATH_HOST/ovs/bridges`; do
        flows_path=$RESULTS_PATH_HOST/ovs/bridges/$bridge/flows
        get_ovs_ofctl_dump_flows $bridge > $flows_path
        readarray -t cookies <<<"`sed -r 's/.*cookie=0x([[:alnum:]]+),.+/\1/g;t;d' $flows_path| sort -u`"
        cookies_path=$RESULTS_PATH_HOST/ovs/bridges/$bridge/flowinfo/cookies
        mkdir -p $cookies_path
        for c in ${cookies[@]}; do
            grep "cookie=0x$c," $flows_path > $cookies_path/$c
        done
        sed -r -e 's/cookie=[[:alnum:]]+,\s+//g' \
                  -e 's/duration=[[:digit:]\.]+s,\s+//g' \
                  -e 's/n_[[:alnum:]]+=[[:digit:]]+,\s+//g' \
                  -e 's/[[:alnum:]]+_age=[[:digit:]]+,\s+//g' \
            $flows_path > ${flows_path}.stripped
    done    
}

load_bridges_flow_tables ()
{
    for bridge in `ls $RESULTS_PATH_HOST/ovs/bridges`; do
        tables_root=$RESULTS_PATH_HOST/ovs/bridges/$bridge/flowinfo/tables
        bridge_flows=$RESULTS_PATH_HOST/ovs/bridges/$bridge/flows
        readarray -t tables<<<"`sed -r 's/.+table=([[:digit:]]+).+/\1/g;t;d' $bridge_flows| sort -un`"
        for t in "${tables[@]}"; do
            mkdir -p $tables_root/$t
            egrep "(^|\s+)table=$t," $bridge_flows > ${tables_root}/${t}/flows
        done
    done
}

load_bridges_port_flows ()
{
    # loads flows for bridges ports and disects.

    for bridge in `ls $RESULTS_PATH_HOST/ovs/bridges`; do
        current_port_jobs=0
        for id in `ls $RESULTS_PATH_HOST/ovs/bridges/$bridge/ports/ 2>/dev/null`; do
            {
            flows_root=$RESULTS_PATH_HOST/ovs/bridges/$bridge/ports/$id/flows
            port_mac=$RESULTS_PATH_HOST/ovs/bridges/$bridge/ports/$id/hwaddr
            hexid=`printf '%x' $id`

            mkdir -p $flows_root
            get_ovs_ofctl_dump_flows $bridge | \
                egrep "in_port=$id[, ]+|output:$id[, ]+|reg5=0x${hexid}[ ,]+|$port_mac" > $flows_root/all

            mkdir -p $flows_root/by-table
            for table in `ls $RESULTS_PATH_HOST/ovs/bridges/$bridge/flowinfo/tables`; do
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
            job_wait $((++current_port_jobs)) && wait
        done

        bridge_flows_root=$RESULTS_PATH_HOST/ovs/bridges/$bridge

        # this is what neutron uses to modify src mac for dvr
        mod_dl_src_root=$bridge_flows_root/flowinfo/mod_dl_src
        mod_dl_src_out=$SCRATCH_AREA/mod_dl_src.$$.`date +%s`
        grep "mod_dl_src" $bridge_flows_root/flows > $mod_dl_src_out
        if [ -s "$mod_dl_src_out" ]; then
            mkdir -p $mod_dl_src_root
            current_bridge_jobs=0
            while read line; do
                {
                mod_dl_src_mac=`echo "$line"| sed -r 's/.+mod_dl_src:([[:alnum:]\:]+).+/\1/g;t;d'`
                orig_mac=""
                if `echo "$line"| grep -q dl_dst`; then
                    orig_mac=`echo "$line"| sed -r 's/.+,dl_dst=([[:alnum:]\:]+).+/\1/g;t;d'`
                fi
                if [ -n "$orig_mac" ]; then
                    # ingress i.e. if dst==remote replace src dvr_mac with local
                    local_mac=$mod_dl_src_mac
                    target_path=$mod_dl_src_root/ingress
                    target_mac=$orig_mac
                else
                    # egress i.e. if src==local set src=dvr_mac
                    local_mac=`echo "$line"| sed -r 's/.+,dl_src=([[:alnum:]\:]+).+/\1/g;t;d'`
                    target_path=$mod_dl_src_root/egress
                    target_mac=$mod_dl_src_mac
                fi
                mkdir -p $target_path
                local_mac_path="`egrep -l '$local_mac' $RESULTS_PATH_HOST/ovs/ports/*/hwaddr`"
                if [ -n "$local_mac_path" ]; then
                    rel_path="`echo "$local_mac_path"| sed -r "s,$RESULTS_PATH_HOST,../../../../../..,g"`"
                    ln -s $rel_path $target_path/$target_mac
                else
                    echo "$local_mac" > $target_path/$target_mac
                fi
                } &
                job_wait $((++current_bridge_jobs)) && wait
            done < $mod_dl_src_out
        fi
        wait

        # collect flows corresponding to nw_src addresses
        nw_src_root=$bridge_flows_root/flowinfo/nw_src
        nw_src_out=$SCRATCH_AREA/nw_src.$$.`date +%s`
        grep "nw_src" $bridge_flows_root/flows > $nw_src_out.tmp
        if [ -s "$nw_src_out.tmp" ]; then
            sed -r 's/.+nw_src=([[:digit:]\.]+)(\/[[:digit:]]+)?.+/\1/g;t;d' $nw_src_out.tmp| sort -u > $nw_src_out
            mkdir -p $nw_src_root
            while read nw_src_addr; do
                egrep "nw_src=${nw_src_addr}(/[0-9]+)?" $bridge_flows_root/flows > $nw_src_root/$nw_src_addr
            done < $nw_src_out
        fi
        wait
    done
}

# used by neutron openvswitch firewall driver
load_bridge_flow_regs ()
{
    for bridge in `ls $RESULTS_PATH_HOST/ovs/bridges`; do
        readarray -t regs<<<"`get_ovs_ofctl_dump_flows $bridge | \
            sed -r 's/.+(reg[[:digit:]]+)=(0x[[:alnum:]]+).+/\1=\2/g;t;d'| sort -u`"
        regspath=$RESULTS_PATH_HOST/ovs/bridges/$bridge/flowinfo/registers
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
    for bridge in `ls $RESULTS_PATH_HOST/ovs/bridges`; do
        readarray -t conj_ids<<<"`cat $RESULTS_PATH_HOST/ovs/bridges/$bridge/flows| \
            sed -r 's/.+conj_id=([[:digit:]]+).+/\1/g;t;d'| sort -u`"
        conj_ids_path=$RESULTS_PATH_HOST/ovs/bridges/$bridge/flowinfo/conj_ids
        mkdir -p $conj_ids_path
        ((${#conj_ids[@]})) && [ -n "${conj_ids[0]}" ] || continue
        for id in ${conj_ids[@]}; do
            mkdir -p $conj_ids_path/$id
            egrep "conj_id=$id[, ]|conjunction\($id," \
                    $RESULTS_PATH_HOST/ovs/bridges/$bridge/flows > \
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

    [ -e "$RESULTS_PATH_HOST/ovs/bridges/$bridge/ports/$port" ] || return
    readlink -f $RESULTS_PATH_HOST/ovs/bridges/$bridge/ports/$port| \
        xargs -l basename
}

get_ovs_bridge_ports ()
{
    # returns list of all ports on bridge
    # :requires: load_ovs_bridges_ports

    bridge=$1

    ((`ls $RESULTS_PATH_HOST/ovs/bridges/$bridge/ports/| wc -l`)) || return
    find $RESULTS_PATH_HOST/ovs/bridges/$bridge/ports/*| xargs -l readlink -f| \
        xargs -l basename
}

check_error ()
{
    if [ -s "$RESULTS_PATH_HOST/error.$$" ]; then
        echo "ERROR: unable to load $1: `cat $RESULTS_PATH_HOST/error.$$`"
    fi
    rm -f $RESULTS_PATH_HOST/error.$$
}

create_dataset ()
{
    ${DO_ACTIONS[SHOW_SUMMARY]} && echo -en "Creating dataset"

    # ordering is important!
    load_namespaces 2>$RESULTS_PATH_HOST/error.$$; check_error "namespaces"
    ${DO_ACTIONS[SHOW_SUMMARY]} && echo -n "."
    load_ovs_bridges 2>$RESULTS_PATH_HOST/error.$$; check_error "ovs bridges"
    ${DO_ACTIONS[SHOW_SUMMARY]} && echo -n "."
    load_bridges_flows 2>$RESULTS_PATH_HOST/error.$$; check_error "bridge flows"
    ${DO_ACTIONS[SHOW_SUMMARY]} && echo -n "."
    load_ovs_bridges_ports 2>$RESULTS_PATH_HOST/error.$$; check_error "bridge ports"
    ${DO_ACTIONS[SHOW_SUMMARY]} && echo -n "."

    load_bridges_port_vlans 2>$RESULTS_PATH_HOST/error.$$; check_error "port vlans"
    ${DO_ACTIONS[SHOW_SUMMARY]} && echo -n "."
    load_bridges_flow_tables 2>$RESULTS_PATH_HOST/error.$$; check_error "bridge flow tables"
    ${DO_ACTIONS[SHOW_SUMMARY]} && echo -n "."
    load_bridges_flow_vlans 2>$RESULTS_PATH_HOST/error.$$; check_error "flow vlans"
    ${DO_ACTIONS[SHOW_SUMMARY]} && echo -n "."
    load_bridges_port_ns_attach_info 2>$RESULTS_PATH_HOST/error.$$; check_error "port ns info"
    ${DO_ACTIONS[SHOW_SUMMARY]} && echo -n "."
    wait

    load_bridges_port_macs 2>$RESULTS_PATH_HOST/error.$$; check_error "port macs"
    ${DO_ACTIONS[SHOW_SUMMARY]} && echo -n "."

    # do this first so that we can use reg5 to identify port flows if it exists
    load_bridge_flow_regs 2>$RESULTS_PATH_HOST/error.$$; check_error "flow regs"
    ${DO_ACTIONS[SHOW_SUMMARY]} && echo -n "."
    wait
    # these depend on everything else existing so wait till the rest is finished
    load_bridges_port_flows 2>$RESULTS_PATH_HOST/error.$$; check_error "port flows"
    ${DO_ACTIONS[SHOW_SUMMARY]} && echo -n "."
    load_bridge_conjunctive_flow_ids 2>$RESULTS_PATH_HOST/error.$$; check_error "conj_ids"
    ${DO_ACTIONS[SHOW_SUMMARY]} && echo -n "."
    wait

    ${DO_ACTIONS[SHOW_SUMMARY]} && echo "done."
}

show_summary ()
{
    summary=$SCRATCH_AREA/pretty_summary
    echo -e "\nSummary:"
    (
    echo "| Bridge | Tables | Cookies | Registers | Ports | ->tagged | ->namespaced | ->veth-peers | Vlans |"
    for bridge in `ls $RESULTS_PATH_HOST/ovs/bridges`; do
        echo -n "| $bridge "
        echo -n "| `ls $RESULTS_PATH_HOST/ovs/bridges/$bridge/flowinfo/tables 2>/dev/null| wc -l` "
        echo -n "| `ls $RESULTS_PATH_HOST/ovs/bridges/$bridge/flowinfo/cookies 2>/dev/null| wc -l` "
        echo -n "| `ls -d $RESULTS_PATH_HOST/ovs/bridges/$bridge/flowinfo/registers/* 2>/dev/null| wc -l` "
        echo -n "| `ls $RESULTS_PATH_HOST/ovs/bridges/$bridge/ports 2>/dev/null| wc -l` "
        echo -n "| `ls -d $RESULTS_PATH_HOST/ovs/bridges/$bridge/ports/*/vlan 2>/dev/null| wc -l` "
        readarray -t _ns<<<"`readlink -f $RESULTS_PATH_HOST/ovs/ports/*/namespace| sort -u`"
        echo -n "| `for ns in ${_ns[@]}; do readlink -f $ns/*/*/bridge; done| grep $bridge| wc -l` "
        echo -n "| `ls -d $RESULTS_PATH_HOST/ovs/bridges/$bridge/ports/*/hostnet/veth_peer 2>/dev/null| wc -l` "
        echo -n "| `readlink -f $RESULTS_PATH_HOST/ovs/bridges/$bridge/ports/*/vlan 2>/dev/null| sort -u| wc -l` "
        echo "|"
    done
    ) | column -t > ${summary}.tmp

    len=`head -n 1 ${summary}.tmp| wc -c`
    echo -n "+" >> $summary; i=$((len-2)); \
    while ((--i)); do echo -n '-' >> $summary; done; echo "+" >> $summary
    head -n 1 ${summary}.tmp >> $summary
    echo -n "+" >> $summary; i=$((len-2)); while ((--i)); do echo -n '-' >> $summary; done; echo "+" >> $summary
    tail +2 ${summary}.tmp| sort -hk1 >> $summary
    echo -n "+" >> $summary; i=$((len-2)); while ((--i)); do echo -n '-' >> $summary; done; echo "+" >> $summary

    cat $summary
}

ensure_interfaces ()
{
    # check network-control
    get_ip_netns &>/dev/null
    if (($?)); then
        echo "ERROR: unable to retreive network information - have you done 'snap connnect ovs-stat:network-control'?"
        exit 1
    fi

    # check openvswitch
    get_ovs_vsctl_show &>/dev/null
    if (($?)); then
        echo "ERROR: unable to retreive openvswitch information - have you done 'snap connnect ovs-stat:openvswitch'?"
        exit 1
    fi
}

## MAIN ##

# Need this to stop it from running multiple times
cleaned=false
cleanup () {
    $cleaned && return
    wait
    if [ -d "$TMP_DATASTORE" ] && ${DO_ACTIONS[DELETE_DATASET]}; then
        ${DO_ACTIONS[QUIET]} || echo -e "\nDeleting datastore at $TMP_DATASTORE"
        rm -rf $TMP_DATASTORE
    fi
    rm -rf $SCRATCH_AREA
    [ -e "$COMMAND_CACHE_PATH" ] && rm -rf $COMMAND_CACHE_PATH
    ${DO_ACTIONS[SHOW_SUMMARY]} && echo -e "\nDone."
    cleaned=true
    exit
}
trap cleanup EXIT INT

# Sanitise input
((MAX_PARALLEL_JOBS >= 0)) || MAX_PARALLEL_JOBS=0

# If no path was provided we will create one under $TMPDIR
if [ -z "$RESULTS_PATH_ROOT" ]; then
    TMP_DATASTORE=`mktemp -d`
    RESULTS_PATH_ROOT=${TMP_DATASTORE}/
elif ! [ "${RESULTS_PATH_ROOT:(-1)}" = "/" ]; then
    # Ensure trailing slash
    RESULTS_PATH_ROOT="${RESULTS_PATH_ROOT}/"
fi

# Ensure trailing slash
if [ -n "$OVS_FS_DATA_SOURCE" ] && ! [ "${OVS_FS_DATA_SOURCE:(-1)}" = "/" ]; then
    OVS_FS_DATA_SOURCE="${OVS_FS_DATA_SOURCE}/"
fi

# no fs data
# Ensure results path is writeable if exists
if ! ${DO_ACTIONS[CREATE_DATASET]} && ! [ -e $RESULTS_PATH_ROOT ]; then
    echo "ERROR: no dataset found at $RESULTS_PATH_ROOT"
elif ${DO_ACTIONS[CREATE_DATASET]} && [ -e $RESULTS_PATH_ROOT ] && \
        ! [ -w $RESULTS_PATH_ROOT ]; then
    echo "ERROR: insufficient permissions to write to $RESULTS_PATH_ROOT"
    exit 1
elif ${DO_ACTIONS[CREATE_DATASET]} && [ -e $RESULTS_PATH_ROOT ] && \
        [ -z "$TMP_DATASTORE" ]; then
    if $FORCE; then
        ${DO_ACTIONS[QUIET]} || echo "Deleting $RESULTS_PATH_ROOT"
        rm -rf $RESULTS_PATH_ROOT
    else
        # switch to read-only
        DO_ACTIONS[CREATE_DATASET]=false
        readarray -t hosts<<<"`ls -A $RESULTS_PATH_ROOT`"
        if [ -n "$HOSTNAME" ]; then
            if ! `echo "${hosts[@]}"| egrep -q "^$HOSTNAME$|\s$HOSTNAME$|^$HOSTNAME\s|\s$HOSTNAME\s"`; then
                echo "ERROR: hostname '$HOSTNAME' not found in dataset"
                exit 1
            fi
        else
            num_hosts=${#hosts[@]}
            if ((num_hosts>1)); then
                echo "Multiple hosts found in $RESULTS_PATH_ROOT:"
                for ((i=0;i<num_hosts;i++)); do
                    echo "[${i}] ${hosts[$i]}"
                done
                echo -en "\nWhich would you like to use? [0-$((num_hosts-1))]"
                read answer
                echo ""
                if ((answer>num_hosts)); then
                    echo "ERROR: invalid host id $answer (allowed=0-$((num_hosts-1)))"
                    exit 1
                fi
                HOSTNAME=${hosts[$answer]}
            else
                HOSTNAME=${hosts[0]}
            fi
        fi
    fi
fi

if [ -z "$HOSTNAME" ]; then
    # get hostname
    HOSTNAME=`get_hostname`
    if [ -z "$HOSTNAME" ]; then
        echo "ERROR: unable to identify hostname - have all necessary snap interfaces been enabled?"
        exit 1
    fi
fi
RESULTS_PATH_HOST=$RESULTS_PATH_ROOT$HOSTNAME

if ${DO_ACTIONS[SHOW_SUMMARY]}; then
    _source=${OVS_FS_DATA_SOURCE:-localhost}
    echo "Data source: ${_source%/} (hostname=$HOSTNAME)"
    echo "Results root: ${RESULTS_PATH_ROOT%/}"
    ${DO_ACTIONS[CREATE_DATASET]} && read_only=false || read_only=true
    echo -e "Read-only: $read_only"
fi

if ${DO_ACTIONS[CREATE_DATASET]}; then
    # first check we have what we need
    ensure_interfaces

    # create top-level structure and next-level, the rest is created dynamically
    for path in $RESULTS_PATH_HOST $RESULTS_PATH_HOST/ovs/{bridges,ports,vlans} \
         $RESULTS_PATH_HOST/linux/{namespaces,ports}; do
        mkdir -p $path
        if (($?)); then
            echo "ERROR: unable to create directory $path - insufficient permissions?"
            exit 1
        fi
    done

    # then pre-load the caches
    ${DO_ACTIONS[SHOW_SUMMARY]} && echo -en "\nPre-loading caches..."
    ${DO_ACTIONS[CREATE_DATASET]} && cache_preload
    ${DO_ACTIONS[SHOW_SUMMARY]} && echo -en "done.\n"

    # then go!
    create_dataset
fi

if ${DO_ACTIONS[SHOW_NEUTRON_ERRORS]}; then
    # look for "dead" vlan tagged ports
    echo -e "\nSearching for errors related to Openstack Neutron usage of Openvswitch...\n"
    errors_found=false
    if [ -d $RESULTS_PATH_HOST/ovs/vlans/4095 ]; then
        errors_found=true
        echo -e "INFO: dataset contains neutron \"dead\" vlan tag 4095:"
        tree --noreport $RESULTS_PATH_HOST/ovs/vlans/4095
        echo ""
    fi

    declare -A cookie_count=()
    for bridge in `ls -1 $RESULTS_PATH_HOST/ovs/bridges`; do
        c=`ls -1 $RESULTS_PATH_HOST/ovs/bridges/$bridge/flowinfo/cookies| wc -l`
        ((c<2)) || cookie_count[$bridge]=$c
    done

    if ((${#cookie_count[@]})); then
        errors_found=true
cat << EOF
INFO: the following bridges have more than one cookie. Depending on which
neutron plugin you are using this may or may not be a problem i.e. if you are
using the openvswitch ML2 plugin there is only supposed to be one cookie per
bridge but if you are using the OVN plugin there will be many cookies.
EOF

        for bridge in ${!cookie_count[@]}; do
            echo -e "\n$bridge (${cookie_count[$bridge]}) - run the following to see full list of cookies:\n\n  ls $RESULTS_PATH_HOST/ovs/bridges/$bridge/flowinfo/cookies/*"
        done
        echo ""
    fi

    if ! $errors_found; then
        echo -e "No neutron errors found"
    fi
    DO_ACTIONS[SHOW_SUMMARY]=false
fi

${DO_ACTIONS[SHOW_SUMMARY]} && show_summary

# check for broken symlinks
if ! ${DO_ACTIONS[QUIET]} && ((`find $RESULTS_PATH_HOST -xtype l| wc -l`)); then
cat << EOF

================================================================================
WARNING: dataset contains broken links!

If running against live data this might be resolved by recreating the dataset
otherwise it can be an indication of incorrectly configured ovs. To display
broken links run:

find $RESULTS_PATH_HOST -xtype l

================================================================================
EOF
fi

if ${DO_ACTIONS[SHOW_DATASET]}; then
    args=""
    if [ -n "$TREE_DEPTH" ]; then
        args+="-L $TREE_DEPTH"
    fi
    tree $args $RESULTS_PATH_HOST
fi

if ${DO_ACTIONS[COMPRESS_DATASET]}; then
    target=ovs-stat-${HOSTNAME}
    [ -n "$ARCHIVE_TAG" ] && target+="-$ARCHIVE_TAG"
    target+="-`date +%d%m%y.%s`.tgz"
    # snap running as root won't have access to non-root $HOME
    tar_root=`pwd`
    if ! [ -w $tar_root ]; then
        if [ "${RESULTS_PATH_ROOT:0:5}" == "/tmp/" ]; then
            tar_root="`mktemp -d`/"
        else
            tar_root=$RESULTS_PATH_ROOT
        fi
    fi
    echo -e "\nCompressing to $tar_root$target"
    tar -czf $tar_root$target -C `dirname $RESULTS_PATH_HOST` $HOSTNAME
fi

show_footer ()
{
    ${DO_ACTIONS[SHOW_SUMMARY]} && echo -ne "\nINFO: see --help for more display options"
}

${DO_ACTIONS[SHOW_FOOTER]} && show_footer

