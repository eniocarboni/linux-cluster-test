# **
# Linux-cluster-test
# Copyright (c) 2020 Enio Carboni
# Distributed under the GNU GPL v3. For full terms see the file LICENSE.
# **
# Description: script for vagrant provision used only by first node after all node provision to configure cluster on all nodes
# - check if node need a manual reboot
# - inizialize the cluster on all nodes if necessary
# - add any node if in vagrant list and not in cluster nodes
# - remove any node if not in vagrant list but present in cluster nodes
# - in 2 nodes cluster set no-quorum-policy=ignore
# - create all test resources if need
# **
# Provision order: 
# 00-workarounds.sh
# 10-node_configuration.sh
# 30-stonith-fence_node_configuration.sh
# 90-single-cluster_configuration.sh (only on node 1) (this file)
# 92-single-stonith-fence_cluster_configuration.sh (only on node 1)
# 99-single-show-cluster-status.sh (only on node 1)
# **
# Provision trigger
# - trigger_before_destroy.sh (before destroy a node)
# **

# == START functions ==

# waitReboot()
# Description:
#  Check if the vm must be manually rebooted before this provision
# Global Vars:
# Input :
# Output: "waiting a reboot ..." message and exit if the vm must be manually rebooted
# Return value: 0 in case non problem
waitReboot() {
  if [ -f "/remove_some_know_problems" ]; then
    echo "waiting a reboot in this vm .. launch 'vagrant reload && vagrant provision'"
    exit 0
  fi
}

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
waitReboot

if [ "$os" = "centos7" ]; then
  httpd_conf="/etc/httpd/conf/httpd.conf"
elif [ "$os" = "ubuntu1804" ]; then
  httpd_conf="/etc/apache2/apache2.conf"
else
  echo "OS: $os not available: use 'centos7' or 'ubuntu1804'"
  exit 2
fi

cluster_nodes=''
for i in $(seq 1 $NUM_CLUSTER_NODES); do
  cluster_nodes="${cluster_nodes} ${pre_node}$i"
done
echo -e "Check Cluster"
pcs cluster status >/dev/null 2>&1
if [ $? -ne 0 ]; then
  echo -e "\tinizializing the cluster on nodes ${cluster_nodes}"
  pcs cluster auth ${cluster_nodes} -u hacluster -p "$hacluster_pwd"
  pcs cluster setup --start --name "quolltech_cluster" ${cluster_nodes} --force
  pcs cluster enable --all
  # disable stonith
  pcs property set stonith-enabled=false
else
  echo -e "\tcluster already enabled"
  # cluster already exist!
  # test if we must add/remove node
  # test: check if we must add some nodes
  for node in ${cluster_nodes}; do
    must_add=0
    corosync-cmapctl | grep nodelist.node | grep -q "$node"
    if [ $? -ne 0 ]; then
      # node not in cluster
      must_add=1
    else
      cibadmin -Q | grep node_state | grep "$node" | grep -q 'crmd="online"' >/dev/null 2>&1
      if [ $? -ne 0 ]; then
        # node is in cluster but in bad state (UNCLEAN / offline)
        must_add=1
	echo -e "\tfound $node in cluster but in bad state ... remove then add"
        pcs cluster node remove "$node" --force 2>/dev/null 2>&1
        pcs cluster node clear "$node"
        pcs cluster reload corosync
      fi
    fi
    if [ $must_add -eq 1 ]; then
      # this node is not in cluster or in bad state (UNCLEAN / offline)
      echo -e "\t** Adding $node to cluster **"
      pcs cluster auth "$node" -u hacluster -p "$hacluster_pwd"
      pcs cluster node add "$node"
      pcs cluster enable "$node"
      pcs cluster start "$node"
    fi
  done
  # test: check if we must remove some nodes
  members=$(corosync-cmapctl | grep nodelist.node | grep -v nodeid | sed 's/^.* = //')
  if [ "$debug" = "true" ]; then
    echo "[DEBUG] Cluster members:" $members
  fi
  for member in $members; do
    echo "${cluster_nodes}" | grep -q "$member"
    if [ $? -ne 0 ]; then
      # remove node $member from cluster
      echo -e "\t** Removing '$member' from cluster **"
      # insert the ip in /etc/hosts so that can be resolved and removed from cluster if is on
      id_member=${member/$pre_node}
      echo -e "# :START Vagrant node removing" >> /etc/hosts
      echo -e "${PRIV_NET_CLUSTER}.$(($id_member + $PRIV_NET_START))\t $member" >> /etc/hosts
      echo -e "# :END Vagrant node removing" >> /etc/hosts
      if [ "$debug" = "true" ]; then
        echo "[DEBUG] partial /etc/hosts for node $member"
        sed -n '/# :START Vagrant node removing/,/# :END Vagrant node removing/p' /etc/hosts
	echo "[DEBUG] end partial"
      fi
      pcs cluster node remove "$member" --force
      pcs cluster node clear "$member"
      pcs cluster reload corosync
      sed -i '/# :START Vagrant node removing/,/# :END Vagrant node removing/d' /etc/hosts
    fi
  done
fi
if [ $NUM_CLUSTER_NODES -eq 2 ]; then
  echo "Disable quorum because in 2-node cluster make no sense"
  pcs property set no-quorum-policy=ignore
else
  pcs property set no-quorum-policy=stop
fi
sleep 5
echo "Check cluster resource"
pcs resource show first_test_ip >/dev/null 2>&1
if [ $? -ne 0 ]; then
	echo -e "\tcreate resource first_test_ip (${NET_RESOURCES}.$((${NET_RESOURCES_START} + 1))) on group apachegroup"
	pcs resource create first_test_ip IPaddr2 ip=${NET_RESOURCES}.$((${NET_RESOURCES_START} + 1)) cidr_netmask=24 --group apachegroup
else
  echo -e "\tresource first_test_ip already created, skipping"
fi
pcs resource show Web1 >/dev/null 2>&1
if [ $? -ne 0 ]; then
  echo -e "\tcreate resource Web1 (apache) on group apachegroup"
  pcs resource create Web1 apache configfile="$httpd_conf" statusurl="http://127.0.0.1/server-status" --group apachegroup
else 
  echo -e "\tresource Web1 already created, skipping"
fi
pcs resource show second_test_ip >/dev/null 2>&1
if [ $? -ne 0 ]; then
	echo -e "\tcreate resource second_test_ip (${NET_RESOURCES}.$((${NET_RESOURCES_START} + 2))) on group group_second_test_ip"
	pcs resource create second_test_ip IPaddr2 ip=${NET_RESOURCES}.$((${NET_RESOURCES_START} + 2)) cidr_netmask=24 --group group_second_test_ip
else
  echo -e "\tresource second_test_ip already created, skipping"
fi
pcs resource show last_test_ip >/dev/null 2>&1
if [ $? -ne 0 ]; then
	echo -e "\tcreate resource last_test_ip (${NET_RESOURCES}.$((${NET_RESOURCES_START} + 3))) on group group_last_test_ip"
	pcs resource create last_test_ip IPaddr2 ip=${NET_RESOURCES}.$((${NET_RESOURCES_START} + 3)) cidr_netmask=24 --group group_last_test_ip
else
  echo -e "\tresource last_test_ip already created, skipping"
fi
