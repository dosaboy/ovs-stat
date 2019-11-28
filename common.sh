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

cache_preload ()
{
    get_ps &>/dev/null
    get_hostname &>/dev/null
    get_ip_addr_show &>/dev/null
    get_ip_link_show &>/dev/null
    get_ip_netns &>/dev/null
    get_ovs_vsctl_show &>/dev/null
    get_ovsdb_client_list_dump &>/dev/null
    get_ns_ip_addr_show_all &>/dev/null
}

get_bridge_of_version ()
{
    bridge="$1"
    ver="`ovs-vsctl get bridge $bridge protocols| jq -r '.| first'`"
    [ -z "$ver" ] || [ "$ver" = "null" ] && return 0
    echo -n $ver
    return 0
}

get_ps ()
{
    sos=${root}ps
    if [ -r "$sos" ]; then
        cat $sos
        return
    fi

    cache=$COMMAND_CACHE_PATH/cache.ps
    ( flock -e 200
      if [ -r "$cache" ]; then
          cat $cache
      else
          ps auxx| tee $cache
      fi
    ) 200>$LOCKPATH
}

get_hostname ()
{
    sos=${root}hostname
    if [ -r "$sos" ]; then
        cat $sos
        return
    fi

    hostname
}

get_ip_addr_show ()
{
    sos=${root}sos_commands/networking/ip_-d_address
    if [ -r "${root}sos_commands" ]; then
        cat $sos
        return
    fi

    cache=$COMMAND_CACHE_PATH/cache.ip_addr
    ( flock -e 200
      if [ -r "$cache" ]; then
          cat $cache
      else
          ip -d address| tee $cache
      fi
    ) 200>$LOCKPATH
}

get_ip_link_show ()
{
    sos=${root}sos_commands/networking/ip_-s_-d_link
    if [ -r "${root}sos_commands" ]; then
        cat $sos
        return
    fi

    cache=$COMMAND_CACHE_PATH/cache.ip_-s_-d_link
    ( flock -e 200
      if [ -r "$cache" ]; then
          cat $cache
      else
          ip -s -d link| tee $cache
      fi
    ) 200>$LOCKPATH
}

get_ip_netns ()
{
    sos=${root}sos_commands/networking/ip_netns
    if [ -r "${root}sos_commands" ]; then
        cat $sos
        return
    fi

    cache=$COMMAND_CACHE_PATH/cache.ipnetns
    ( flock -e 200
      if [ -r "$cache" ]; then
          cat $cache
      else
          ip netns| tee $cache
      fi
    ) 200>$LOCKPATH
}

get_ns_ip_addr_show ()
{
    ns="$1"
    sos=${root}sos_commands/networking/ip_netns_exec_${ns}_ip_address_show
    if [ -r "${root}sos_commands" ]; then
        cat $sos
        return
    fi

    ip netns exec $ns ip addr show
}

get_ns_iptables ()
{
    ns=$1
    sos=${root}sos_commands/networking/ip_netns_exec_${ns}_iptables-save
    if [ -r "${root}sos_commands" ]; then
        cat $sos
        return
    fi

    ip netns exec $ns iptables-save
}

get_ns_ss ()
{
    ns="$1"
    sos=${root}sos_commands/networking/ip_netns_exec_${ns}_ss_-peaonmi
    if [ -r "${root}sos_commands" ]; then
        cat $sos
        return
    fi

    ip netns exec ${ns} ss -peaonmi
}

get_ns_netstat ()
{
    ns="$1"
    sos=${root}sos_commands/networking/ip_netns_exec_${ns}_netstat_-W_-neopa
    if [ -r "${root}sos_commands" ]; then
        cat $sos
        return
    fi

    ip netns exec ${ns} netstat -W -neopa
}

get_ovs_ofctl_dump_flows ()
{
    bridge="$1"
    sos=${root}sos_commands/openvswitch/ovs-ofctl_dump-flows_${bridge}
    if [ -r "${root}sos_commands" ]; then
        cat $sos
        return
    fi

    cache=$COMMAND_CACHE_PATH/cache.ofctl_dump_flows_${bridge}
    ( flock -e 200
      if [ -r "$cache" ]; then
          cat $cache
      else
            of_ver="`get_bridge_of_version $bridge`"
            if [ -n "$of_ver" ]; then
                ovs-ofctl -O $of_ver dump-flows $bridge| tee $cache
            else
                ovs-ofctl dump-flows $bridge| tee $cache
            fi
      fi
    ) 200>$LOCKPATH
}

get_ovs_ofctl_show ()
{
    bridge="$1"
    sos=${root}sos_commands/openvswitch/ovs-ofctl_show_${bridge}
    if [ -r "${root}sos_commands" ]; then
        cat $sos
        return
    fi

    cache=$COMMAND_CACHE_PATH/cache.ofctl_show_${bridge}
    ( flock -e 200
      if [ -r "$cache" ]; then
          cat $cache
      else
            of_ver="`get_bridge_of_version $bridge`"
            if [ -n "$of_ver" ]; then
                ovs-ofctl -O $of_ver show $bridge| tee $cache
            else
                ovs-ofctl show $bridge| tee $cache
            fi
      fi
    ) 200>$LOCKPATH
}

get_ovs_vsctl_show ()
{
    sos=${root}sos_commands/openvswitch/ovs-vsctl_-t_5_show
    if [ -r "${root}sos_commands" ]; then
        cat $sos
        return
    fi

    cache=$COMMAND_CACHE_PATH/cache.vsctl_show
    ( flock -e 200
      if [ -r "$cache" ]; then
          cat $cache
      else
          ovs-vsctl show| tee $cache
      fi
    ) 200>$LOCKPATH
}

get_ovs_appctl_fdbshow ()
{
    bridge=$1
    sos=${root}sos_commands/openvswitch/ovs-appctl_fdb.show_${bridge}
    if [ -r "${root}sos_commands" ]; then
        cat $sos
        return
    fi

    cache=$COMMAND_CACHE_PATH/cache.ovs-appctl_fdb.show_${bridge}
    ( flock -e 200
      if [ -r "$cache" ]; then
          cat $cache
      else
          ovs-appctl fdb/show $bridge| tee $cache
      fi
    ) 200>$LOCKPATH
}

get_ovsdb_client_list_dump ()
{
    sos=${root}sos_commands/openvswitch/ovsdb-client_-f_list_dump
    if [ -r "${root}sos_commands" ]; then
        cat $sos
        return
    fi

    cache=$COMMAND_CACHE_PATH/cache.ovsdb-client_-f_list_dump
    ( flock -e 200
      if [ -r "$cache" ]; then
          cat $cache
      else
          ovsdb-client -f list dump| tee $cache
      fi
    ) 200>$LOCKPATH
}

get_ns_ip_addr_show_all ()
{
    #NOTE: this is a bit of a hack to make sos version look the same as real
    sos=${root}sos_commands/networking/ip_netns_exec_*_ip_address_show
    cache=$COMMAND_CACHE_PATH/cache.ipnetns_all_ip_addr_show

    tmp=`mktemp`
    echo 0 > $tmp
    ( flock -e 200
      if [ -r "$cache" ]; then
          cat $cache
          echo 1 > $tmp
      fi
    ) 200>$LOCKPATH

    ((`cat $tmp`)) && return

    if [ -r "${root}sos_commands" ]; then
        readarray -t namespaces<<<"`get_ip_netns`"
        if ((${#namespaces[@]}>0)) && [ -n "${namespaces[0]}" ]; then
            for ns in "${namespaces[@]}"; do
                # NOTE: sometimes ip netns contains (id: <id>) and sometimes it doesn't
                ns=${ns%% *}
                echo "netns: $ns"
                get_ns_ip_addr_show $ns
            done > $tmp
        else
            return
        fi
    else
        ip -all netns exec ip addr show > $tmp
    fi

    ( flock -e 200
        mv $tmp $cache
        cat $cache
    ) 200>$LOCKPATH
}
