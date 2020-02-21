# **
# Linux-cluster-test
# Copyright (c) 2020 Enio Carboni
# Distributed under the GNU GPL v3. For full terms see the file LICENSE.
# **
# Description: script for vagrant provision used only by first node to configure fence cluster agents
# - check if node need a manual reboot
# - if $FENCE_AGENT is false in Vagrant file:
#   - remove any stonith fence agents existing 
#   - cleanup history error/warning log of stonith created during change $FENCE_AGENT from "true" to "false"
#   - disable stonith on cluster (stonith-enabled=false)
#   - exit soon
# - configure all "fence" user on all node with same ssh certificates so that any node can connect to any other via ssh and "fence" user.
# - cleanup history error/warning log of stonith
# - create all stonith fence resources
# - create constraint for stonith fence resources
# - remove any unneed stonith fence resources
# -  enable stonith on cluster (stonith-enabled=true)
# **
# Provision order: 
# 00-workarounds.sh
# 10-node_configuration.sh
# 30-stonith-fence_node_configuration.sh
# 90-single-cluster_configuration.sh (only on node 1)
# 92-single-stonith-fence_cluster_configuration.sh (only on node 1) (this file)
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
  
# installPkg()
# Description:
#  Install the package in $1
# Global Vars: os
# Input : $1= package to install
# Output: 
# Return value: 0
installPkg() {
  pkg="$1"
  if [ "$os" = "centos7" ]; then
    rpm -q --quiet "$pkg" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
      echo -e "\tinstalling $pkg [yum install -y -q $pkg]"
      yum install -y -q "$pkg"
    else
      echo -e "\t$pkg already installed, skip"
    fi
  elif [ "$os" = "ubuntu1804" ]; then
    dpkg -l "$pkg" 2>&1 | grep '^ii' >/dev/null 2>&1
    if [ $? -ne 0 ]; then
      echo -e "\tinstalling $pkg [apt install -y -q $pkg]"
      apt install -y -q "$pkg" >/dev/null 2>&1
    else
      echo -e "\t$pkg already installed, skip"
    fi
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
# fence input params:
FENCE_AGENT="${12}"
PRIV_NET_FENCE_CLUSTER="${13}"
PRIV_NETMASK_FENCE_CLUSTER="${14}"
fencecluster_pwd="${15}"

if [ "$debug" = "true" ]; then
  echo "[DEBUG] Input params: "
  echo "  debug=$debug, NUM_CLUSTER_NODES=$NUM_CLUSTER_NODES, PRIV_NET_CLUSTER=$PRIV_NET_CLUSTER, PRIV_NETMASK_CLUSTER=$PRIV_NETMASK_CLUSTER, PRIV_NET_START=$PRIV_NET_START, NET_RESOURCES=$NET_RESOURCES, NET_RESOURCES_START=$NET_RESOURCES_START, SOFTWARE_UPDATE=$SOFTWARE_UPDATE, SECURE_VAGRANT_USER_PWD=$SECURE_VAGRANT_USER_PWD, hacluster_pwd=$hacluster_pwd, vagrant_user_pwd=$vagrant_user_pwd"
  echo "  FENCE_AGENT=$FENCE_AGENT, PRIV_NET_FENCE_CLUSTER=$PRIV_NET_FENCE_CLUSTER, PRIV_NETMASK_FENCE_CLUSTER=$PRIV_NETMASK_FENCE_CLUSTER, fencecluster_pwd=$fencecluster_pwd"
fi
HOSTNAME=$(hostname)
HOSTID=$(echo $HOSTNAME | sed 's/.*-//')
pre_node=$(echo $HOSTNAME | sed -e 's/^cluster-//' -e 's/[0-9]*$//')
os=$(getOS)

waitReboot
if [ "$FENCE_AGENT" != "true" ]; then
  members=$(pcs stonith show| grep -v 'NO stonith devices' | awk '{print $1}')
  for member in $members; do
    echo "[FENCE_AGENT=$FENCE_AGENT] Removing stonith resourse ${member}"
    pcs stonith delete "${member}" --force
  done
  stonith_admin --cleanup --history "*" >/dev/null 2>&1
  pcs property set stonith-enabled=false
  exit
fi
cluster_nodes=''
cluster_fence_nodes=''
cluster_nodes_but_this=''
for i in $( seq 1 $NUM_CLUSTER_NODES ); do
  cluster_nodes="${cluster_nodes} ${pre_node}$i"
  cluster_fence_nodes="${cluster_fence_nodes} ${pre_node}fence-$i"
  if [ $i -ne 1 ]; then
    cluster_nodes_but_this="${cluster_nodes_but_this} ${pre_node}$i"
  fi
done
echo "Configuring fence users on all nodes ..."
installPkg "sshpass"
cd /root
rm -rf .ssh
echo -e "\tgenerating ssh key to auto login in fence user and moving it in /home/fence/.ssh"
ssh-keygen -q -C "fence_agent_key" -f /root/.ssh/id_rsa -N ''
cp -a .ssh/id_rsa.pub .ssh/authorized_keys
cat <<EOF >.ssh/config
Host 192.168.43.* ${pre_node}fence-*
   StrictHostKeyChecking no
EOF
rm -rf /home/fence/.ssh
mv -f .ssh/ /home/fence/
chown -R fence:fence /home/fence/.ssh
cd /home/fence
for nodeid in ${cluster_nodes_but_this}; do
  echo -e "\tcopying fence ssh key (id_rsa,id_rsa.pub,authorized_keys,config) on fence@${nodeid}"
  # enable auto ssh on fence user on each cluster node
  tar cf - .ssh/ | sshpass -p "$fencecluster_pwd" ssh -i /home/fence/.ssh/id_rsa -o StrictHostKeyChecking=no -o LogLevel=ERROR fence@${nodeid} tar xf - --warning=no-timestamp
  echo -e "\tsecure ssh login on $nodeid disabling PasswordAuthentication and restart sshd service"
  ssh -i /home/fence/.ssh/id_rsa -o StrictHostKeyChecking=no -o LogLevel=ERROR fence@${nodeid} sudo /tmp/secure_ssh.sh
done
echo -e "\tsecure ssh login on this node ($(hostname)) disabling PasswordAuthentication and restart sshd service"
/tmp/secure_ssh.sh
echo -e "Checking for stonith resources and constraints..."
echo -e "\tcleanup old fence logs"
stonith_admin --cleanup --history "*" >/dev/null 2>&1
for i in $( seq 1 $NUM_CLUSTER_NODES ); do
  pcs stonith show stonith-ssh-$i >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo -e "\tcreate stonith fence resource stonith-ssh-$i (fence_ssh) to fence node ${pre_node}fence-$i"
    pcs stonith create stonith-ssh-$i fence_ssh user=fence sudo=true private-key="/home/fence/.ssh/id_rsa" hostname="${pre_node}fence-$i" pcmk_host_list="${pre_node}$i" --force --disabled >/dev/null 2>&1
  else
    echo -e "\tstonith fence stonith-ssh-$i already created, skipping"
  fi
  pcs constraint |grep stonith-ssh-$i >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo -e "\tcreate constraint for stonith-ssh-$i to avoids on node ${pre_node}$i"
    pcs constraint location stonith-ssh-$i avoids ${pre_node}$i
  else 
    echo -e "\tconstraint location stonith-ssh-$i already created, skipping"
  fi
  pcs stonith enable stonith-ssh-$i
done
# test: check if we must remove some stonith resources
members=$(pcs stonith show| grep -v 'NO stonith devices'| awk '{print $1}')
if [ "$debug" = "true" ]; then
  echo "[DEBUG] stonith resources:" $members
fi
for member in $members; do
  id_member=${member/stonith-ssh-}
  echo "${cluster_nodes}" | grep -q "${pre_node}${id_member}"
  if [ $? -ne 0 ]; then
    # remove $member associate with this $member
    echo -e "\tremoving stonith resourse ${member}"
    pcs stonith delete "${member}" --force >/dev/null 2>&1
  fi
done
echo -e "Enabling stonith on this cluster"
pcs property set stonith-enabled=true
