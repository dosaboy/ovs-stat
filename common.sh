# Colours:
CSI='\033['
RES="${CSI}0m"
red () { echo "${CSI}31m$1${RES}"; }
grn () { echo "${CSI}32m$1${RES}"; }
ylw () { echo "${CSI}33m$1${RES}"; }
bold () { echo -e "\e[1m$1\e[0m"; }
uline () { echo -e "\e[4m$1\e[0m"; }

get_ps ()
{
    sos=${root}ps
    if [ -r "$sos" ]; then
        cat $sos
    else
        cache=/tmp/cache.$$.ps
        if ! [ -r "$cache" ]; then
            ps auxx > $cache
        fi
        cat $cache
    fi
}

get_hostname ()
{
    sos=${root}hostname
    if [ -r "$sos" ]; then
        cat $sos
    else
        hostname
    fi
}

get_ip_addr_show ()
{
    sos=${root}sos_commands/networking/ip_-d_address
    if [ -r "${root}sos_commands" ]; then
        cat $sos
    else
        cache=/tmp/cache.$$.ip_addr
        if ! [ -r "$cache" ]; then
            ip -d address > $cache
        fi
        cat $cache
    fi    
}

get_ip_link_show ()
{
    sos=${root}sos_commands/networking/ip_-s_-d_link
    if [ -r "${root}sos_commands" ]; then
        cat $sos
    else
        cache=/tmp/cache.$$.ip_addr
        if ! [ -r "$cache" ]; then
            ip -s -d link > $cache
        fi
        cat $cache
    fi    
}

get_ip_netns ()
{
    sos=${root}sos_commands/networking/ip_netns
    if [ -r "${root}sos_commands" ]; then
        cat $sos
    else
        cache=/tmp/cache.$$.ipnetns
        if ! [ -r "$cache" ]; then
            ip netns > $cache
        fi
        cat $cache
    fi
}

get_ns_ip_addr_show ()
{
    ns=$1
    sos=${root}sos_commands/networking/ip_netns_exec_${ns}_ip_address_show
    if [ -r "${root}sos_commands" ]; then
        cat $sos
    else
        cache=/tmp/cache.$$.${ns}_ipnetnsipas
        if ! [ -r "$cache" ]; then
            ip netns exec $ns ip addr show > $cache
        fi
        cat $cache
    fi    
}

get_ns_iptables ()
{
    ns=$1
    sos=${root}sos_commands/networking/ip_netns_exec_${ns}_iptables-save
    if [ -r "${root}sos_commands" ]; then
        cat $sos
    else
        cache=/tmp/cache.$$.${ns}_ipnetnsipts
        if ! [ -r "$cache" ]; then
            ip netns exec $ns iptables-save > $cache
        fi
        cat $cache
    fi
}

get_ns_ss ()
{
    ns=$1
    sos=${root}sos_commands/networking/ip_netns_exec_${ns}_ss_-peaonmi
    if [ -r "${root}sos_commands" ]; then
        cat $sos
    else
        cache=/tmp/cache.$$.${ns}_ipnetnsss
        if ! [ -r "$cache" ]; then
            ip netns exec ${ns} ss -peaonmi > $cache
        fi
        cat $cache
    fi
}

get_ns_netstat ()
{
    ns=$1
    sos=${root}sos_commands/networking/ip_netns_exec_${ns}_netstat_-W_-neopa
    if [ -r "${root}sos_commands" ]; then
        cat $sos
    else
        cache=/tmp/cache.$$.${ns}_ipnetnsnetstat
        if ! [ -r "$cache" ]; then
            ip netns exec ${ns} netstat -W -neopa > $cache
        fi
        cat $cache
    fi
}

get_ovs_ofctl_dump_flows ()
{
    bridge=$1
    sos=${root}sos_commands/openvswitch/ovs-ofctl_dump-flows_${bridge}
    if [ -r "${root}sos_commands" ]; then
        cat $sos
    else
        cache=/tmp/cache.$$.ofctl_dump_flows_${bridge}
        if ! [ -r "$cache" ]; then
            ovs-ofctl dump-flows $bridge > $cache
        fi
        cat $cache
    fi
}

get_ovs_ofctl_show ()
{
    bridge=$1
    sos=${root}sos_commands/openvswitch/ovs-ofctl_show_${bridge}
    if [ -r "${root}sos_commands" ]; then
        cat $sos
    else
        cache=/tmp/cache.$$.ofctl_show_${bridge}
        if ! [ -r "$cache" ]; then
            ovs-ofctl show $bridge > $cache
        fi
        cat $cache
    fi
}

get_ovs_vsctl_show ()
{
    sos=${root}sos_commands/openvswitch/ovs-vsctl_-t_5_show
    if [ -r "${root}sos_commands" ]; then
        cat $sos
    else
        cache=/tmp/cache.$$.vsctl_show
        if ! [ -r "$cache" ]; then
            ovs-vsctl show > $cache
        fi
        cat $cache
    fi
}

get_ovs_appctl_fdbshow ()
{
    bridge=$1
    sos=${root}sos_commands/openvswitch/ovs-appctl_fdb.show_${bridge}
    if [ -r "${root}sos_commands" ]; then
        cat $sos
    else
        cache=/tmp/cache.$$.ovs-appctl_fdb.show_${bridge}
        if ! [ -r "$cache" ]; then
            ovs-appctl fdb/show ${bridge} > $cache
        fi
        cat $cache
    fi
}

get_ovsdb_client_list_dump ()
{
    sos=${root}sos_commands/openvswitch/ovsdb-client_-f_list_dump
    if [ -r "${root}sos_commands" ]; then
        cat $sos
    else
        cache=/tmp/cache.$$.ovsdb-client_-f_list_dump
        if ! [ -r "$cache" ]; then
            ovsdb-client -f list dump > $cache
        fi
        cat $cache
    fi
}

get_ns_ip_addr_show_all ()
{
    #NOTE: this is a bit of a hack to make sos version look the same as real
    sos=${root}sos_commands/networking/ip_netns_exec_*_ip_address_show
    cache=/tmp/cache.$$.all_ipnetnsipas
    if [ -r "${root}sos_commands" ]; then
        if [ -r "$cache" ]; then
            cat $cache
            return
        fi
        readarray -t namespaces<<<"`get_ip_netns`"
        { ((${#namespaces[@]}==0)) || [ -z "${namespaces[0]}" ]; } && return
        (
        for ns in "${namespaces[@]}"; do
            # NOTE: sometimes ip netns contains (id: <id>) and sometimes it doesn't
            ns=${ns%% *}
            echo "netns: $ns"
            get_ns_ip_addr_show $ns
        done
        ) > $cache
    else
        if ! [ -r "$cache" ]; then
            ip -all netns exec ip addr show > $cache
        fi
        cat $cache
    fi
}
