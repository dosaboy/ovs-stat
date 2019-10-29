# Colours:
CSI='\033['
RES="${CSI}0m"
red () { echo "${CSI}31m$1${RES}"; }
grn () { echo "${CSI}32m$1${RES}"; }
ylw () { echo "${CSI}33m$1${RES}"; }
bold () { echo -e "\e[1m$1\e[0m"; }
uline () { echo -e "\e[4m$1\e[0m"; }

COMMAND_CACHE_PATH=`mktemp -d --suffix -$$-cache-i-am-safe-to-delete`
LOCKPATH=$COMMAND_CACHE_PATH/lock

get_ps ()
{
    sos=${root}ps
    if [ -r "$sos" ]; then
        cat $sos
    else
        ( flock -e 200
        cache=$COMMAND_CACHE_PATH/cache.$$.ps
        if ! [ -r "$cache" ]; then
            ps auxx| tee $cache
        else
            cat $cache
        fi
        ) 200>$LOCKPATH
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
        ( flock -e 200
        cache=$COMMAND_CACHE_PATH/cache.$$.ip_addr
        if ! [ -r "$cache" ]; then
            ip -d address| tee $cache
        else
            cat $cache
        fi
        ) 200>$LOCKPATH
    fi    
}

get_ip_link_show ()
{
    sos=${root}sos_commands/networking/ip_-s_-d_link
    if [ -r "${root}sos_commands" ]; then
        cat $sos
    else
        ( flock -e 200
        cache=$COMMAND_CACHE_PATH/cache.$$.ip_addr
        if ! [ -r "$cache" ]; then
            ip -s -d link| tee $cache
        else
            cat $cache
        fi
        ) 200>$LOCKPATH
    fi    
}

get_ip_netns ()
{
    sos=${root}sos_commands/networking/ip_netns
    if [ -r "${root}sos_commands" ]; then
        cat $sos
    else
        ( flock -e 200
        cache=$COMMAND_CACHE_PATH/cache.$$.ipnetns
        if ! [ -r "$cache" ]; then
            ip netns| tee $cache
        else
            cat $cache
        fi
        ) 200>$LOCKPATH
    fi
}

get_ns_ip_addr_show ()
{
    ns=$1
    sos=${root}sos_commands/networking/ip_netns_exec_${ns}_ip_address_show
    if [ -r "${root}sos_commands" ]; then
        cat $sos
    else
        ( flock -e 200
        cache=$COMMAND_CACHE_PATH/cache.$$.${ns}_ipnetnsipas
        if ! [ -r "$cache" ]; then
            ip netns exec $ns ip addr show| tee $cache
        else
            cat $cache
        fi
        ) 200>$LOCKPATH
    fi    
}

get_ns_iptables ()
{
    ns=$1
    sos=${root}sos_commands/networking/ip_netns_exec_${ns}_iptables-save
    if [ -r "${root}sos_commands" ]; then
        cat $sos
    else
        ( flock -e 200
        cache=$COMMAND_CACHE_PATH/cache.$$.${ns}_ipnetnsipts
        if ! [ -r "$cache" ]; then
            ip netns exec $ns iptables-save| tee $cache
        else
            cat $cache
        fi
        ) 200>$LOCKPATH
    fi
}

get_ns_ss ()
{
    ns=$1
    sos=${root}sos_commands/networking/ip_netns_exec_${ns}_ss_-peaonmi
    if [ -r "${root}sos_commands" ]; then
        cat $sos
    else
        ( flock -e 200
        cache=$COMMAND_CACHE_PATH/cache.$$.${ns}_ipnetnsss
        if ! [ -r "$cache" ]; then
            ip netns exec ${ns} ss -peaonmi| tee $cache
        else
            cat $cache
        fi
        ) 200>$LOCKPATH
    fi
}

get_ns_netstat ()
{
    ns=$1
    sos=${root}sos_commands/networking/ip_netns_exec_${ns}_netstat_-W_-neopa
    if [ -r "${root}sos_commands" ]; then
        cat $sos
    else
        ( flock -e 200
        cache=$COMMAND_CACHE_PATH/cache.$$.${ns}_ipnetnsnetstat
        if ! [ -r "$cache" ]; then
            ip netns exec ${ns} netstat -W -neopa| tee $cache
        else
            cat $cache
        fi
        ) 200>$LOCKPATH
    fi
}

get_ovs_ofctl_dump_flows ()
{
    bridge=$1
    sos=${root}sos_commands/openvswitch/ovs-ofctl_dump-flows_${bridge}
    if [ -r "${root}sos_commands" ]; then
        cat $sos
    else
        ( flock -e 200
        cache=$COMMAND_CACHE_PATH/cache.$$.ofctl_dump_flows_${bridge}
        if ! [ -r "$cache" ]; then
            ovs-ofctl dump-flows $bridge| tee $cache
        else
            cat $cache
        fi
        ) 200>$LOCKPATH
    fi
}

get_ovs_ofctl_show ()
{
    bridge=$1
    sos=${root}sos_commands/openvswitch/ovs-ofctl_show_${bridge}
    if [ -r "${root}sos_commands" ]; then
        cat $sos
    else
        ( flock -e 200
        cache=$COMMAND_CACHE_PATH/cache.$$.ofctl_show_${bridge}
        if ! [ -r "$cache" ]; then
            ovs-ofctl show $bridge| tee $cache
        else
            cat $cache
        fi
        ) 200>$LOCKPATH
    fi
}

get_ovs_vsctl_show ()
{
    sos=${root}sos_commands/openvswitch/ovs-vsctl_-t_5_show
    if [ -r "${root}sos_commands" ]; then
        cat $sos
    else
        ( flock -e 200
        cache=$COMMAND_CACHE_PATH/cache.$$.vsctl_show
        if ! [ -r "$cache" ]; then
            ovs-vsctl show| tee $cache
        else
            cat $cache
        fi
        ) 200>$LOCKPATH
    fi
}

get_ovs_appctl_fdbshow ()
{
    bridge=$1
    sos=${root}sos_commands/openvswitch/ovs-appctl_fdb.show_${bridge}
    if [ -r "${root}sos_commands" ]; then
        cat $sos
    else
        ( flock -e 200
        cache=$COMMAND_CACHE_PATH/cache.$$.ovs-appctl_fdb.show_${bridge}
        if ! [ -r "$cache" ]; then
            ovs-appctl fdb/show $bridge| tee $cache
        else
            cat $cache
        fi
        ) 200>$LOCKPATH
    fi
}

get_ovsdb_client_list_dump ()
{
    sos=${root}sos_commands/openvswitch/ovsdb-client_-f_list_dump
    if [ -r "${root}sos_commands" ]; then
        cat $sos
    else
        ( flock -e 200
        cache=$COMMAND_CACHE_PATH/cache.$$.ovsdb-client_-f_list_dump
        if ! [ -r "$cache" ]; then
            ovsdb-client -f list dump| tee $cache
        else
            cat $cache
        fi
        ) 200>$LOCKPATH
    fi
}

get_ns_ip_addr_show_all ()
{
    #NOTE: this is a bit of a hack to make sos version look the same as real
    sos=${root}sos_commands/networking/ip_netns_exec_*_ip_address_show
    cache=$COMMAND_CACHE_PATH/cache.$$.all_ipnetnsipas
    ( flock -e 200
    if [ -r "${root}sos_commands" ]; then
        if [ -r "$cache" ]; then
            cat $cache
        else
            readarray -t namespaces<<<"`get_ip_netns`"
            { ((${#namespaces[@]}==0)) || [ -z "${namespaces[0]}" ]; } && return
            for ns in "${namespaces[@]}"; do
                # NOTE: sometimes ip netns contains (id: <id>) and sometimes it doesn't
                ns=${ns%% *}
                echo "netns: $ns"
                get_ns_ip_addr_show $ns
            done | tee $cache
        fi
    else
        if ! [ -r "$cache" ]; then
            ip -all netns exec ip addr show| tee $cache
        else
            cat $cache
        fi
    fi
    ) 200>$LOCKPATH
}
