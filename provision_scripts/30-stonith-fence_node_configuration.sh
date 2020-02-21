# **
# Linux-cluster-test
# Copyright (c) 2020 Enio Carboni
# Distributed under the GNU GPL v3. For full terms see the file LICENSE.
# **
# Description: script for vagrant provision used for each node of cluster to enable stonith fence agent
# - check if node need a manual reboot
# - if $FENCE_AGENT on Vagrant file is false remove all fence configuration and exit
# - enable and configure fence network on third interface (not loopback)
# - install all packages needs for cluster fence
# - update /etc/hosts with ip and name of cluster nodes fence
# - install fence test agent for nodes that use ssh
# - create and configure user "fence" to shutdown vm in case of node problem
# **
# Provision order: 
# 00-workarounds.sh
# 10-node_configuration.sh
# 30-stonith-fence_node_configuration.sh (this file)
# 90-single-cluster_configuration.sh (only on node 1)
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

# removeFencePackages()
# Description:
#  Remove fence agents
# Global Vars: os, FENCE_AGENT
# Input : 
# Output: 
# Return value: 0
removeFencePackages() {
  if [ "$os" = "centos7" ]; then
    rpm -q --quiet fence-agents-all >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      echo "[FENCE_AGENT=$FENCE_AGENT] removing package fence-agents-all [yum remove -y -q fence-agents-all]"
      yum remove -y -q fence-agents-all
    fi
  fi
}


# fromNetmaskToCidr()
# Description
#  Convert input netmask to CIDR
#  es. netmask=255.255.255.0 convert in CIDR=24
#      netmask=255.255.0.0 convert in CIDR=16
#      netmask=255.255.255.224 convert in CIDR=27
# Global Vars:
# Input : $1= netmask to convert
# Output: cidr
# Return value: 0
fromNetmaskToCidr() {
  local netmask=$1
  local bin=({0..1}{0..1}{0..1}{0..1}{0..1}{0..1}{0..1}{0..1})
  local b=''
  local n
  local cidr
  echo "$netmask" | grep -q -P '^255\.\d{1,3}\.\d{1,3}\.\d{1,3}$'
  if [ $? -ne 0 ]; then
    echo -e "\t[ERROR] netmask format error '$netmask'. It must be 255.ddd.ddd.ddd such as 255.255.255.0. I will use 255.25.255.0"
    netmask="255.255.255.0"
  fi
  
  for n in ${netmask//./ }; do 
     if [ $n -gt 255 ]; then 
       echo -e "\t[ERROR] netmask $netmask format error in '.$n'. I will use .255 insted of .$n"
       n=255
     fi
     if [ $n -ne 0 -a $n -ne 128 -a $n -ne 192 -a $n -ne 224 -a $n -ne 240 -a $n -ne 248 -a $n -ne 252 -a $n -ne 254 -a $n -ne 255 ]; then
       echo -e "\t[ERROR] netmask $netmask format error in '.$n' (it must be 0,128,192,224,240,248,252,254,255). I will use .255 insted of .$n"
       n=255
     fi
     # $b is the binary of $netmask
     b=${b}${bin[$n]}
  done
  # remove right "0" bits from $b
  b=${b/%0*}
  cidr=${#b}
  echo $cidr
}

# privateFenceNet()
# Description:
#  Configure private stonith fence cluster network
# Global Vars: eth3, os, PRIV_NET_FENCE_CLUSTER, HOSTID, PRIV_NET_START, PRIV_NETMASK_FENCE_CLUSTER, debug
# Input :
# Output:
# Return value: 0
privateFenceNet() {
  local addr
  local cidr
  echo "Check private fence cluster network ..."
  if [ "$FENCE_AGENT" != "true" ]; then
    # cluster stonith fence agent is disable by config environment $FENCE_AGENT
    if [ -n "${eth3}" ]; then
      ip link show ${eth3} up 2>/dev/null | grep -q ${eth3}
      if [ $? -eq 0 ]; then
        echo -e "\tremoving fence ip address on ${eth3} and set set dev down"
        ip link set dev ${eth3} down
        ip addr del ${PRIV_NET_FENCE_CLUSTER}.$(($HOSTID + $PRIV_NET_START))/${PRIV_NETMASK_FENCE_CLUSTER} dev ${eth3} >/dev/null 2>&1
        if [ "$debug" = "true" ]; then
          echo -e "\t[DEBUG]: ip link show dev ${eth3}"
  	  ip link show dev ${eth3} | sed 's/^/\t/'
        fi
      fi
    fi
    if [ -f "/etc/sysconfig/network-scripts/ifcfg-${eth3}" ]; then
      echo -e "\tremoving net configuration for ${eth3} dev in /etc/sysconfig/network-scripts/ifcfg-${eth3}"
      rm -f /etc/sysconfig/network-scripts/ifcfg-${eth3}
    fi
    if [ -f "/etc/netplan/60-cluster05-fence.yaml" ]; then
      echo -e "\tremoving net configuration for ${eth3} dev in /etc/netplan/60-cluster05-fence.yaml"
      rm -f /etc/netplan/60-cluster05-fence.yaml
      netplan generate
    fi
  elif [ "$os" = "centos7" ]; then
    if [ ! -f "/etc/sysconfig/network-scripts/ifcfg-${eth3}" ]; then
      echo -e "\tconfiguring private fence cluster network on ${eth3}"
      cat <<EOF >/etc/sysconfig/network-scripts/ifcfg-${eth3}
DEVICE="${eth3}"
ONBOOT="yes"
BOOTPROTO=static
IPADDR=${PRIV_NET_FENCE_CLUSTER}.$(($HOSTID + $PRIV_NET_START))
NETMASK=${PRIV_NETMASK_FENCE_CLUSTER}
NM_CONTROLLED=no
TYPE=Ethernet
EOF
      /etc/sysconfig/network-scripts/ifup ${eth3}
    else 
      echo -e "\tprivate cluster fence network on ${eth3} already configured, skip"
    fi
  elif [ "$os" = "ubuntu1804" ]; then
    # ubuntu 1804 use netplan for networks
    if [ ! -f "/etc/netplan/60-cluster05-fence.yaml" ]; then
      echo -e "\tconfiguring private fence cluster network on ${eth3}"
      cidr=$(fromNetmaskToCidr ${PRIV_NETMASK_FENCE_CLUSTER})
      addr="${PRIV_NET_FENCE_CLUSTER}.$(($HOSTID + $PRIV_NET_START))/${cidr}"
      cat <<EOF >/etc/netplan/60-cluster05-fence.yaml
---
network:
  version: 2
  renderer: networkd
  ethernets:
    ${eth3}:
      addresses:
      - ${addr}
EOF
      netplan generate
      systemctl restart systemd-networkd.service
    else
      echo -e "\tprivate cluster fence network on ${eth3} already configured, skip"
    fi
  fi
}

# installFencePkg()
# Description:
#  Install the ifence agents package
# Global Vars: os
# Input :
# Output: 
# Return value: 0

installFencePackages() {
  pkg="fence-agents-all"
  if [ "$os" = "centos7" ]; then
    rpm -q --quiet "$pkg" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
      echo -e "\tinstalling $pkg [yum install -y -q $pkg]"
      yum install -y -q "$pkg"
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
eths=$(ip address | grep '^[0-9]' | awk '{print $2}' | uniq | grep -v lo | sed 's/://g' | sed 's/@.*$//')
eth1=$(echo $eths | awk '{print $1}')
eth2=$(echo $eths | awk '{print $2}')
eth3=$(echo $eths | awk '{print $3}')
waitReboot

if [ "$debug" = "true" ]; then
  echo "[DEBUG] HOSTNAME=$HOSTNAME, HOSTID=$HOSTID, pre_node=$pre_node, os=$os"
  echo "[DEBUG] network interfaces found: $eth1 $eth2 $eth3"
fi

if [ "$FENCE_AGENT" != "true" ]; then
  if [ -e "/etc/sudoers.d/fence_tmp" ]; then
    echo "[FENCE_AGENT=$FENCE_AGENT] remove file /etc/sudoers.d/fence_tmp"
    rm -f /etc/sudoers.d/fence_tmp
  fi
  if [ -e "/etc/sudoers.d/fence" ]; then
    echo "[FENCE_AGENT=$FENCE_AGENT] remove file /etc/sudoers.d/fence"
    rm -f /etc/sudoers.d/fence
  fi
  id fence >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo "[FENCE_AGENT=$FENCE_AGENT] remove user 'fence'"
    userdel -rf fence >/dev/null 2>&1
  fi
  if [ -e "/usr/sbin/fence_ssh" ]; then
    echo "[FENCE_AGENT=$FENCE_AGENT] remove agent fence fence_ssh at /usr/sbin/fence_ssh"
    rm -f /usr/sbin/fence_ssh
  fi
  test_host_fence=$(sed -n '/# :START Vagrant node fence provision/,/# :END Vagrant node fence provisionf/p' /etc/hosts)
  if [ -n "$test_host_fence" ]; then
    echo "[FENCE_AGENT=$FENCE_AGENT] remove fence host in /etc/hosts"
    sed -i '/# :START Vagrant node fence provision/,/# :END Vagrant node fence provision/d' /etc/hosts 
  fi
  removeFencePackages
  privateFenceNet
  exit
fi

privateFenceNet
installFencePackages
echo "update cluster stonith fence network in /etc/hosts"
sed -i '/# :START Vagrant node fence provision/,/# :END Vagrant node fence provision/d' /etc/hosts
echo -e "# :START Vagrant node fence provision" >> /etc/hosts
for nodeid in $(seq 1 $NUM_CLUSTER_NODES); do
  echo -e "${PRIV_NET_FENCE_CLUSTER}.$(($nodeid + $PRIV_NET_START))\t ${pre_node}fence-${nodeid}" >> /etc/hosts
done
echo -e "# :END Vagrant node fence provision" >> /etc/hosts
if [ ! -f /usr/sbin/fence_ssh ]; then
  echo "Downloding fence_ssh to /usr/sbin [see https://github.com/nannafudge/fence_ssh]"
  wget -q -O /usr/sbin/fence_ssh https://raw.githubusercontent.com/nannafudge/fence_ssh/master/fence_ssh
fi
chmod +x /usr/sbin/fence_ssh
id fence >/dev/null 2>&1
if [ $? -ne 0 ]; then
  echo -e "Add fence ssh user for stonith"
  useradd -c "Fence ssh user" -m -s /bin/bash fence
fi
echo "setting fence password to '$fencecluster_pwd'"
echo "fence:$fencecluster_pwd" | chpasswd
cat <<EOF >/etc/sudoers.d/fence
fence   ALL = NOPASSWD: /sbin/shutdown
EOF
chmod 440 /etc/sudoers.d/fence
# Add sudo temporary permission during Vagrant provision
cat <<EOF >/etc/sudoers.d/fence_tmp
fence   ALL = NOPASSWD: /tmp/secure_ssh.sh
EOF
chmod 440 /etc/sudoers.d/fence_tmp
cat <<EOF >/tmp/secure_ssh.sh
#! /bin/bash
# disable ssh PasswordAuthentication and restart sshd
sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd
# remove sudo temporary permission during Vagrant provision
rm /etc/sudoers.d/fence_tmp
# remove this script
rm /tmp/secure_ssh.sh
EOF
chmod u+x /tmp/secure_ssh.sh
# enable ssh PasswordAuthentication during Vagrant provision 
sed -i 's/^PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
# restart sshd
systemctl restart sshd
