# Copyright 2020 opentastic@gmail.com
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

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
    local bridge="$1"
    local ver="`ovs-vsctl get bridge $bridge protocols| jq -r '.| first'`"
    [ -z "$ver" ] || [ "$ver" = "null" ] && return 0
    echo -n $ver
    return 0
}

get_ps ()
{
    local sos=${OVS_FS_DATA_SOURCE}ps
    if [ -r "$sos" ]; then
        cat $sos
        return
    fi

    local cache=$COMMAND_CACHE_PATH/cache.ps
    ( flock -e 200
      if [ -r "$cache" ]; then
          cat $cache
      else
          ps auxx > $cache
          cat $cache
      fi
    ) 200>$LOCKPATH
}

get_hostname ()
{
    local sos=${OVS_FS_DATA_SOURCE}hostname
    if [ -r "$sos" ]; then
        cat $sos
        return
    fi

    hostname
}

get_ip_addr_show ()
{
    local sos=${OVS_FS_DATA_SOURCE}sos_commands/networking/ip_-d_address
    if [ -r "${OVS_FS_DATA_SOURCE}sos_commands" ]; then
        cat $sos
        return
    fi

    local cache=$COMMAND_CACHE_PATH/cache.ip_addr
    local rc=${cache}.rc
    ( flock -e 200
      echo 0 > $rc
      if [ -r "$cache" ]; then
          cat $cache
      else
          ip -d address > $cache
          echo $? > $rc
          cat $cache
      fi
    ) 200>$LOCKPATH
    return `cat $rc`
}

get_ip_link_show ()
{
    local sos=${OVS_FS_DATA_SOURCE}sos_commands/networking/ip_-s_-d_link
    if [ -r "${OVS_FS_DATA_SOURCE}sos_commands" ]; then
        cat $sos
        return
    fi

    local cache=$COMMAND_CACHE_PATH/cache.ip_-s_-d_link
    local rc=${cache}.rc
    ( flock -e 200
      echo 0 > $rc
      if [ -r "$cache" ]; then
          cat $cache
      else
          ip -s -d link > $cache
          echo $? > $rc
          cat $cache
      fi
    ) 200>$LOCKPATH
    return `cat $rc`
}

get_ip_netns ()
{
    local sos=${OVS_FS_DATA_SOURCE}sos_commands/networking/ip_netns
    if [ -r "${OVS_FS_DATA_SOURCE}sos_commands" ]; then
        cat $sos
        return
    fi

    local cache=$COMMAND_CACHE_PATH/cache.ipnetns
    local rc=${cache}.rc
    ( flock -e 200
      echo 0 > $rc
      if [ -r "$cache" ]; then
          cat $cache
      else
          ip netns > $cache
          echo $? > $rc
          cat $cache
      fi
    ) 200>$LOCKPATH
    return `cat $rc`
}

get_ns_ip_addr_show ()
{
    local ns="$1"
    local sos=${OVS_FS_DATA_SOURCE}sos_commands/networking/ip_netns_exec_${ns}_ip_address_show
    if [ -r "${OVS_FS_DATA_SOURCE}sos_commands" ]; then
        cat $sos
        return
    fi

    ip netns exec $ns ip addr show
    return $?
}

get_ns_iptables ()
{
    local ns=$1
    local sos=${OVS_FS_DATA_SOURCE}sos_commands/networking/ip_netns_exec_${ns}_iptables-save
    if [ -r "${OVS_FS_DATA_SOURCE}sos_commands" ]; then
        cat $sos
        return
    fi

    ip netns exec $ns iptables-save
    return $?
}

get_ns_ss ()
{
    local ns="$1"
    local sos=${OVS_FS_DATA_SOURCE}sos_commands/networking/ip_netns_exec_${ns}_ss_-peaonmi
    if [ -r "${OVS_FS_DATA_SOURCE}sos_commands" ]; then
        cat $sos
        return
    fi

    ip netns exec ${ns} ss -peaonmi
    return $?
}

get_ns_netstat ()
{
    local ns="$1"
    local sos=${OVS_FS_DATA_SOURCE}sos_commands/networking/ip_netns_exec_${ns}_netstat_-W_-neopa
    if [ -r "${OVS_FS_DATA_SOURCE}sos_commands" ]; then
        cat $sos
        return
    fi

    ip netns exec ${ns} netstat -W -neopa
    return $?
}

get_ovs_ofctl_dump_flows ()
{
    local bridge="$1"
    local sos=${OVS_FS_DATA_SOURCE}sos_commands/openvswitch/ovs-ofctl_dump-flows_${bridge}
    if [ -r "${OVS_FS_DATA_SOURCE}sos_commands" ]; then
        cat $sos
        return
    fi

    local cache=$COMMAND_CACHE_PATH/cache.ofctl_dump_flows_${bridge}
    local rc=${cache}.rc
    ( flock -e 200
      echo 0 > $rc
      if [ -r "$cache" ]; then
          cat $cache
      else
            of_ver="`get_bridge_of_version $bridge`"
            if [ -n "$of_ver" ]; then
                ovs-ofctl -O $of_ver dump-flows $bridge > $cache
                echo $? > $rc
                cat $cache
            else
                ovs-ofctl dump-flows $bridge > $cache
                echo $? > $rc
                cat $cache
            fi
      fi
    ) 200>$LOCKPATH
    return `cat $rc`
}

get_ovs_ofctl_show ()
{
    local bridge="$1"
    local sos=${OVS_FS_DATA_SOURCE}sos_commands/openvswitch/ovs-ofctl_show_${bridge}
    if [ -r "${OVS_FS_DATA_SOURCE}sos_commands" ]; then
        cat $sos
        return
    fi

    local cache=$COMMAND_CACHE_PATH/cache.ofctl_show_${bridge}
    local rc=${cache}.rc
    ( flock -e 200
      echo 0 > $rc
      if [ -r "$cache" ]; then
          cat $cache
      else
            of_ver="`get_bridge_of_version $bridge`"
            if [ -n "$of_ver" ]; then
                ovs-ofctl -O $of_ver show $bridge > $cache
                echo $? > $rc
                cat $cache
            else
                ovs-ofctl show $bridge > $cache
                echo $? > $rc
                cat $cache
            fi
      fi
    ) 200>$LOCKPATH
    return `cat $rc`
}

get_ovs_vsctl_show ()
{
    local sos=${OVS_FS_DATA_SOURCE}sos_commands/openvswitch/ovs-vsctl_-t_5_show
    if [ -r "${OVS_FS_DATA_SOURCE}sos_commands" ]; then
        cat $sos
        return
    fi

    local cache=$COMMAND_CACHE_PATH/cache.vsctl_show
    local rc=${cache}.rc
    ( flock -e 200
      echo 0 > $rc
      if [ -r "$cache" ]; then
          cat $cache
      else
          ovs-vsctl show > $cache
          echo $? > $rc
          cat $cache
      fi
    ) 200>$LOCKPATH
    return `cat $rc`
}

get_ovs_appctl_fdbshow ()
{
    local bridge=$1
    local sos=${OVS_FS_DATA_SOURCE}sos_commands/openvswitch/ovs-appctl_fdb.show_${bridge}
    if [ -r "${OVS_FS_DATA_SOURCE}sos_commands" ]; then
        cat $sos
        return
    fi

    cache=$COMMAND_CACHE_PATH/cache.ovs-appctl_fdb.show_${bridge}
    local rc=${cache}.rc
    ( flock -e 200
      echo 0 > $rc
      if [ -r "$cache" ]; then
          cat $cache
      else
          ovs-appctl fdb/show $bridge > $cache
          echo $? > $rc
          cat $cache
      fi
    ) 200>$LOCKPATH
    return `cat $rc`
}

get_ovsdb_client_list_dump ()
{
    local sos=${OVS_FS_DATA_SOURCE}sos_commands/openvswitch/ovsdb-client_-f_list_dump
    if [ -r "${OVS_FS_DATA_SOURCE}sos_commands" ]; then
        cat $sos
        return
    fi

    local cache=$COMMAND_CACHE_PATH/cache.ovsdb-client_-f_list_dump
    local rc=${cache}.rc
    ( flock -e 200
      echo 0 > $rc
      if [ -r "$cache" ]; then
          cat $cache
      else
          ovsdb-client -f list dump > $cache
          echo $? > $rc
          cat $cache
      fi
    ) 200>$LOCKPATH
    return `cat $rc`
}

get_ns_ip_addr_show_all ()
{
    #NOTE: this is a bit of a hack to make sos version look the same as real
    local sos=${OVS_FS_DATA_SOURCE}sos_commands/networking/ip_netns_exec_*_ip_address_show
    local cache=$COMMAND_CACHE_PATH/cache.ipnetns_all_ip_addr_show
    local rc=${cache}.rc

    tmp=`mktemp`
    echo 0 > $tmp
    ( flock -e 200
      echo 0 > $rc
      if [ -r "$cache" ]; then
          cat $cache
          echo 1 > $tmp
      fi
    ) 200>$LOCKPATH

    if ((`cat $tmp`)); then
        rm $tmp
        return
    elif [ -r "${OVS_FS_DATA_SOURCE}sos_commands" ]; then
        readarray -t namespaces<<<"`get_ip_netns`"
        if ((${#namespaces[@]})) && [ -n "${namespaces[0]}" ]; then
            for ns in "${namespaces[@]}"; do
                # NOTE: sometimes ip netns contains (id: <id>) and sometimes it doesn't
                ns=${ns%% *}
                echo "netns: $ns"
                get_ns_ip_addr_show $ns
                echo $? > $rc
            done > $tmp
        else
            return
        fi
    else
        ip -all netns exec ip addr show > $tmp
        echo $? > $rc
    fi

    ( flock -e 200
        mv $tmp $cache
        cat $cache
    ) 200>$LOCKPATH
    return `cat $rc`
}
