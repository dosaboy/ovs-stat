#!/bin/bash -u
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
#
# Origin: https://github.com/dosaboy/ovs-stat
#
# Authors:
#  - edward.hope-morley@canonical.com
#  - opentastic@gmail.com

# this is the root that can contain one or more hosts
export RESULTS_PATH_ROOT=
# this is the host dir beneath root and can have >= 1
export RESULTS_PATH_HOST=
# defines whether to delete existing host data
export FORCE_RECREATE=false
# otional datasource required if we want to create a dataset using captured
# data e.g. sosreport.
export OVS_FS_DATA_SOURCE=
export ARCHIVE_TAG=
export TREE_DEPTH=
export MAX_PARALLEL_JOBS=32
export SCRATCH_AREA=`mktemp -d`
export TMP_DATASTORE=
export HOSTNAME=
export QUERY_STR=
export CWD=$(dirname `realpath $0`)
export SCENARIO_OPENSTACK_NEUTRON=false  # fixme: find a better place for this
export ATTEMPT_VM_MAC_CONVERSION=false  # fixme: find a better place for this
CLI_CACHE=( $@ )

# can't export assoc
declare -A DO_ACTIONS=(
    [SHOW_DATASET]=false
    [CREATE_DATASET]=true
    [DELETE_DATASET]=false
    [SHOW_SUMMARY]=true
    [SHOW_FOOTER]=true
    [QUIET]=false
    [SHOW_NEUTRON_ERRORS]=false
    [COMPRESS_DATASET]=false
    [RUN_QUERY]=false
)

# See neutron/agent/linux/openvswitch_firewall/constants.py
export REG_PORT=5
export REG_NET=6
export REG_REMOTE_GROUP=7

# load lib code
for l in `find $CWD/common -type f`; do source $l; done

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

One interesting side-effect/feature of this tool is that it can sometimes simplify
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

    --openstack
        Create links between vlan flows and their expected bridge port vlan.

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

    --query <cmd>
        Run a query against the dataset. To list supported queries provide an
        empty string e.g. --query ""

    -s, --summary
        Only display summary.

    --show-neutron-errors
        Display occurences that indicate issues when Openvswitch is being used
        with Openstack Neutron.

    --attempt-vm-mac-conversion

        When searching for a port using a mac address, if port not found also
        try with mac prefix fa:16 converted to fe:16 in order to match local
        tap device attached to qemu-kvm instance.

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
        --attempt-vm-mac-conversion)
            ATTEMPT_VM_MAC_CONVERSION=true
            ;;
        --openstack|--check-flow-vlans)
            # add deprecation notice and continue
            [ "$1" = "--check-flow-vlans" ] && echo "WARNING: $1 option is deprecated, use --openstack instead"
            SCENARIO_OPENSTACK_NEUTRON=true
            # if this is openstack, show any errors detected.
            DO_ACTIONS[SHOW_NEUTRON_ERRORS]=true
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
            FORCE_RECREATE=true
            ;;
        -q|--quiet)
            DO_ACTIONS[QUIET]=true
            DO_ACTIONS[SHOW_SUMMARY]=false
            ;;
        --query)
            # --quiet
            DO_ACTIONS[QUIET]=true
            DO_ACTIONS[SHOW_SUMMARY]=false
            DO_ACTIONS[RUN_QUERY]=true
            QUERY_STR="$2"  
            shift
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
        # Add deprecated opts here to avoid backcompat issues
        --conntrack)
            [ "$1" = "--conntrack" ] && echo "WARNING: $1 option is deprecated and is now enabled always"
            ;;
        *)
            [ -d "$1" ] || { echo "ERROR: data source path '$1' does not exist"; exit 1; }
            OVS_FS_DATA_SOURCE=$1
            ;;
    esac
    shift
done

create_dataset ()
{
    ${DO_ACTIONS[SHOW_SUMMARY]} && echo -en "Creating dataset"

    # ordering is important!
    for priority in {00..99}; do
        for p in `find $CWD/dataset_factory.d -name $priority\*`; do
            $p
            ${DO_ACTIONS[SHOW_SUMMARY]} && echo -n "."
        done
        wait
    done

    ${DO_ACTIONS[SHOW_SUMMARY]} && echo "done."
}

show_summary ()
{
    summary=`get_scratch_path pretty_summary`
    (
    echo "| Bridge | Tables | Rules | Cookies | Registers | Ports | Vlans | Ports@vlan | Ports@ns | Ports@veth-peer |"
    for bridge in `ls $RESULTS_PATH_HOST/ovs/bridges`; do
        bridge_path=$RESULTS_PATH_HOST/ovs/bridges/$bridge
        echo -n "| $bridge "
        echo -n "| `ls $bridge_path/flowinfo/tables 2>/dev/null| wc -l` "
        echo -n "| `wc -l $bridge_path/flows 2>/dev/null| awk '{print $1}'` "
        echo -n "| `ls $bridge_path/flowinfo/cookies 2>/dev/null| wc -l` "
        echo -n "| `ls -d $bridge_path/flowinfo/registers/* 2>/dev/null| wc -l` "
        echo -n "| `ls $bridge_path/ports 2>/dev/null| wc -l` "
        echo -n "| `readlink -f $bridge_path/ports/*/vlan 2>/dev/null| sort -u| wc -l` "
        echo -n "| `ls -d $bridge_path/ports/*/vlan 2>/dev/null| wc -l` "
        readarray -t _ns<<<"`readlink -f $RESULTS_PATH_HOST/ovs/ports/*/namespace| sort -u`"
        echo -n "| `for ns in ${_ns[@]}; do readlink -f $ns/*/*/bridge; done| grep $bridge| wc -l` "
        echo -n "| `ls -d $bridge_path/ports/*/hostnet/veth_peer 2>/dev/null| wc -l` "
        echo "|"
    done
    ) | column -t > $summary

    echo -e "\nSummary:"
    prettytable $summary
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
    [ -d "$COMMAND_CACHE_PATH" ] && rm -rf $COMMAND_CACHE_PATH
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

if [ -n "$OVS_FS_DATA_SOURCE" ]; then
    # Ensure trailing slash
    if ! [ "${OVS_FS_DATA_SOURCE:(-1)}" = "/" ]; then
        OVS_FS_DATA_SOURCE="${OVS_FS_DATA_SOURCE}/"
    fi
fi

if ! ${DO_ACTIONS[CREATE_DATASET]} && ! [ -d $RESULTS_PATH_ROOT ]; then
    # no dataset found and not creating
    echo "ERROR: no dataset found at $RESULTS_PATH_ROOT"
elif ${DO_ACTIONS[CREATE_DATASET]} && [ -d $RESULTS_PATH_ROOT ] && \
        ! [ -w $RESULTS_PATH_ROOT ]; then
    # dataset found but not writeable
    echo "ERROR: insufficient permissions to write to $RESULTS_PATH_ROOT"
    exit 1
elif ${DO_ACTIONS[CREATE_DATASET]} && [ -d $RESULTS_PATH_ROOT ] && \
        [ -z "$TMP_DATASTORE" ]; then

    readarray -t dataset_hosts<<<"`ls -A $RESULTS_PATH_ROOT`"
    num_dataset_hosts=${#dataset_hosts[@]}

    if $FORCE_RECREATE; then
        path_to_delete=
        # dataset found and we want to recreate it
        if ((num_dataset_hosts>1)); then
            if [ -n "$HOSTNAME" ]; then
                path_to_delete=$RESULTS_PATH_ROOT$HOSTNAME
            elif host_exists `get_hostname` ${dataset_hosts[@]}; then
                path_to_delete=$RESULTS_PATH_ROOT`get_hostname`
            fi
        else
            if ((num_dataset_hosts)); then
                existing_host=${dataset_hosts[0]}
                # if a host exists and --host provided, ensure we only delete --host if it exists
                if [ -n "$HOSTNAME" ]; then
                    if [ "$existing_host" = "$HOSTNAME" ]; then
                        path_to_delete=$RESULTS_PATH_ROOT
                    fi
                # if a host exists and matches the one we are about to create, delete it
                elif [ "$existing_host" = "`get_hostname`" ]; then
                    path_to_delete=$RESULTS_PATH_ROOT
                fi
            else
                # do nothing
                path_to_delete=
            fi
        fi
        if [ -n "$path_to_delete" ] && [ -d "$path_to_delete" ]; then
            ${DO_ACTIONS[QUIET]} || echo "Deleting $path_to_delete"
            rm -rf $path_to_delete
        fi
    elif [ -d "$OVS_FS_DATA_SOURCE" ] && ! [ -d "$RESULTS_PATH_ROOT`get_hostname`" ]; then
        # continue
        :
    else
        # dataset found and we want to preserve it (read-only)
        DO_ACTIONS[CREATE_DATASET]=false
        if [ -n "$HOSTNAME" ]; then
            if ! host_exists $HOSTNAME ${dataset_hosts[@]}; then
                echo "ERROR: hostname '$HOSTNAME' not found in dataset"
                exit 1
            fi
        else
            if ((num_dataset_hosts>1)); then
                echo "Multiple hosts found in $RESULTS_PATH_ROOT:"
                for ((i=0;i<num_dataset_hosts;i++)); do
                    echo "[${i}] ${dataset_hosts[$i]}"
                done
                echo -en "\nWhich would you like to use? [0-$((num_dataset_hosts-1))]"
                read answer
                echo ""
                if ((answer>num_dataset_hosts)); then
                    echo "ERROR: invalid host id $answer (allowed=0-$((num_dataset_hosts-1)))"
                    exit 1
                fi
                HOSTNAME=${dataset_hosts[$answer]}
            else
                HOSTNAME=${dataset_hosts[0]}
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
    ensure_snap_interfaces

    # create top-level structure and next-level, the rest is created dynamically
    for path in $RESULTS_PATH_HOST $RESULTS_PATH_HOST/ovs/{bridges,ports,vlans} \
         $RESULTS_PATH_HOST/linux/{namespaces,ports}; do
        mkdir -p $path
        if (($?)); then
            echo "ERROR: unable to create directory $path - insufficient permissions?"
            exit 1
        fi
    done

    # keep copy of cli command used to create dataset
    echo "${CLI_CACHE[@]}" > $RESULTS_PATH_HOST/.cli_cache

    if [[ -n ${REPO_INFO_PATH:-""} ]] && [[ -r $REPO_INFO_PATH ]]; then
        # available when running as snap
        repo_info=`cat $REPO_INFO_PATH`
    else
        # fallback for running from git source
        repo_info=`git rev-parse --short HEAD 2>/dev/null` || repo_info="unknown" 
    fi
    echo "source: https://github.com/dosaboy/ovs-stat" > $RESULTS_PATH_HOST/.version
    echo "snap-version: ${SNAP_REVISION:-"development"}" >> $RESULTS_PATH_HOST/.version
    echo "repo-info: $repo_info" >> $RESULTS_PATH_HOST/.version

    # then pre-load the caches
    ${DO_ACTIONS[SHOW_SUMMARY]} && echo -en "\nPre-loading caches..."
    ${DO_ACTIONS[CREATE_DATASET]} && cache_preload
    ${DO_ACTIONS[SHOW_SUMMARY]} && echo -en "done.\n"

    # then go!
    create_dataset
fi

if ${DO_ACTIONS[SHOW_NEUTRON_ERRORS]}; then
    output=`get_scratch_path neutron_errors`
    mkdir -p $output

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
    declare -A dp_id_count=()
    for bridge in `ls -1 $RESULTS_PATH_HOST/ovs/bridges`; do
        c=`ls -1 $RESULTS_PATH_HOST/ovs/bridges/$bridge/flowinfo/cookies| wc -l`
        ((c<2)) || cookie_count[$bridge]=$c

        # Ensure that all bridges have unique datapath-id (see LP 1697243)
        dp_path=$RESULTS_PATH_HOST/ovs/bridges/$bridge/dpid
        if [[ -r $dp_path ]]; then
            dp_id=`cat $dp_path`
            if [[ -z ${dp_id_count[$dp_id]:-""} ]]; then
                dp_id_count[$dp_id]=1
            else
                c=${dp_id_count[$dp_id]}
                dp_id_count[$dp_id]=$((c+1))
            fi
        fi
    done

    dpid_warning=false
    for dpid in ${!dp_id_count[@]}; do
        ((${dp_id_count[$dpid]} > 1)) || continue
        dpid_warning=true
    done

    if $dpid_warning; then
        echo -e "WARNING: there are multiple bridges with the same datapath_id\n"
        for dpid in ${!dp_id_count[@]}; do
            echo "  $dpid (${dp_id_count[$dpid]})"
        done
        echo ""
    fi

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

    if [ -d "$RESULTS_PATH_HOST/ovs/conntrack/zones" ]; then
        grep "mark=1" $RESULTS_PATH_HOST/ovs/conntrack/zones/*/entries > $output/conntrack
        if (($?==0)); then
            errors_found=true
            echo "Found conntrack entries that have a mark=1:"
            cat $output/conntrack
        fi
    fi

    if ! $errors_found; then
        echo -e "No neutron errors found"
    fi

    if ! $SCENARIO_OPENSTACK_NEUTRON; then
        DO_ACTIONS[SHOW_SUMMARY]=false
    fi
fi

${DO_ACTIONS[SHOW_SUMMARY]} && show_summary || true

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

if ${DO_ACTIONS[RUN_QUERY]}; then
    . $CWD/plugins/run $QUERY_STR
fi

if ${DO_ACTIONS[COMPRESS_DATASET]}; then
    target=ovs-stat-${HOSTNAME}
    [ -n "$ARCHIVE_TAG" ] && target+="-$ARCHIVE_TAG"
    target+="-`date +%d%m%y.%s`.tgz"
    # snap running as root won't have access to non-root $HOME
    tar_root=`pwd`/
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

if ${DO_ACTIONS[SHOW_SUMMARY]} && ${DO_ACTIONS[SHOW_FOOTER]}; then
     echo -ne "\nINFO: see --help for more display options"
fi

