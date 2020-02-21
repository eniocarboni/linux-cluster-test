# **
# Linux-cluster-test
# Copyright (c) 2020 Enio Carboni
# Distributed under the GNU GPL v3. For full terms see the file LICENSE.
# **
# Description: script for vagrant trigger provision used for each node of cluster before is destroyed
# - remove any fence stonith resource for this node
# - remove this node from cluster
# **
# Provision order: 
# 00-workarounds.sh
# 10-node_configuration.sh
# 30-stonith-fence_node_configuration.sh
# 90-single-cluster_configuration.sh (only on node 1)
# 92-single-stonith-fence_cluster_configuration.sh (only on node 1)
# 99-single-show-cluster-status.sh (only on node 1)
# **
# Provision trigger
# - trigger_before_destroy.sh (before destroy a node) # this node
# **
# == START functions ==

# getOS()
# Description:
#  find the OS in this vm
# Global Vars:
# Input : 
# Output: the OS distribution
# Return value: 0
getOS() {
  if [ -f "/etc/redhat-release" ]; then
    echo "centos7"
  elif [ -f "/etc/lsb-release" ]; then
    echo "ubuntu1804"
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
HOSTNAME=$(hostname)
HOSTID=$(echo $HOSTNAME | sed 's/.*-//')
pre_node=$(echo $HOSTNAME | sed -e 's/^cluster-//' -e 's/[0-9]*$//')
os=$(getOS)

if [ "$debug" = "true" ]; then
  echo "[DEBUG] HOSTNAME=$HOSTNAME, HOSTID=$HOSTID, pre_node=$pre_node, os=$os"
fi

echo -e "\tremoving any fence stonith resource for this node"
pcs stonith delete stonith-ssh-${HOSTID} --force >/dev/null 2>&1
echo -e "\tremoving this node from cluster"
pcs cluster node remove ${HOSTNAME} --force >/dev/null 2>&1
sleep 5
exit 0
