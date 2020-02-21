# **
# Linux-cluster-test
# Copyright (c) 2020 Enio Carboni
# Distributed under the GNU GPL v3. For full terms see the file LICENSE.
# **
# Description: script for vagrant provision used by each cluster node as a workaround to possible bug.
# - check if this linux distribution vagrant box as problem with dbus locking operation:
#   some container, seen on centos 7 on lxd, has /var/run not symbolic linked to /run.
#   - move all in /var/run/* to /run
#   - remove /var/run/
#   - create symbolic link to /run in /var/run
#   - touch file /removeSomeKnowProblems so all provision script exit if not manually restart vm
#   - when restart remove /removeSomeKnowProblems
# **
# Provision order: 
# 00-workarounds.sh (this file)
# 10-node_configuration.sh
# 30-stonith-fence_node_configuration.sh
# 90-single-cluster_configuration.sh (only on node 1)
# 92-single-stonith-fence_cluster_configuration.sh (only on node 1)
# 99-single-show-cluster-status.sh (only on node 1)
# **
# Provision trigger
# - trigger_before_destroy.sh (before destroy a node)
# **

# == START functions ==

# removeSomeKnowProblems()
# Description: 
#  check if /var/run is not a symbolic link to /run: dbus.socket service lock on some centos 7
#  in case of problem, migrate file in /run and do the symbolic link but we need a manual reboot
# Global Vars:
# input :
# output:
# return value: 0
removeSomeKnowProblems() {
  if [ ! -L "/var/run" -a -d "/var/run" ]; then
    echo -e "/var/run is not a symbolic link to /run! This may craete lock problem on dbus.socket"
    echo -e "\tTo limit the problem on dbus I do the symbolic link between /var/run and /run"
    mv -f /var/run/* /run
    rm -rf /var/run
    ln -s /run /var/run
    touch /remove_some_know_problems
    echo -e "\t  now you need to manually relaunch 'vagrant reload && vagrant provision'"
  elif [ -f "/remove_some_know_problems" ]; then
    rm -f "/remove_some_know_problems"
  fi
}

# == END functions ==
# == START main ==

# Input params:
debug="$1"
NUM_CLUSTER_NODES="$2"
PRIV_NET_CLUSTER="$3"
PRIV_NETMASK_CLUSTER="$4"
PRIV_NET_START="$5"
NET_RESOURCES="$6"
NET_RESOURCES_START="$7"
SOFTWARE_UPDATE="$8"
SECURE_VAGRANT_USER_PWD="$9"
hacluster_pwd="${10}"
vagrant_user_pwd="${11}"

if [ "$debug" = "true" ]; then
  echo "[DEBUG] Input params: "
  echo "  debug=$debug, NUM_CLUSTER_NODES=$NUM_CLUSTER_NODES, PRIV_NET_CLUSTER=$PRIV_NET_CLUSTER, PRIV_NETMASK_CLUSTER=$PRIV_NETMASK_CLUSTER, PRIV_NET_START=$PRIV_NET_START, NET_RESOURCES=$NET_RESOURCES, NET_RESOURCES_START=$NET_RESOURCES_START, SOFTWARE_UPDATE=$SOFTWARE_UPDATE, SECURE_VAGRANT_USER_PWD=$SECURE_VAGRANT_USER_PWD, hacluster_pwd=$hacluster_pwd, vagrant_user_pwd=$vagrant_user_pwd"
fi
removeSomeKnowProblems
