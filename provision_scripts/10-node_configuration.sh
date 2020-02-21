# **
# Linux-cluster-test
# Copyright (c) 2020 Enio Carboni
# Distributed under the GNU GPL v3. For full terms see the file LICENSE.
# **
# Description: script for vagrant provision used for each node of cluster
# - check if node need a manual reboot
# - set locale to en_US.utf8
# - update software catalogs
# - update software
# - Securing user vagrant password
# - Set cluster private network
# - install all packages needs for cluster use (cps, pacemaker, corousync)
# - install and configure apache web server as a test cluster resourse
# - update /etc/hosts with ip and name of cluster nodes
# - configure firewall
# - enable service to use the cluster
# - remove, if any, default cluster config installed by packages
# **
# Provision order: 
# 00-workarounds.sh
# 10-node_configuration.sh (this file)
# 30-stonith-fence_node_configuration.sh
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

# setLocale()
# Description:
#  Update locale on the vm in en_US.utf8
# Global Vars: LANG
# Input :
# Output:
# Return value: 0
setLocale() {
  echo "Update locale en_US.utf8"
  which update-locale >/dev/null 2>&1
  if [ $? = 0 ]; then
    echo -e "\tuse update-locale to update locale"
    update-locale LANG=en_US.utf8
  else
    which localectl >/dev/null 2>&1
    if [ $? = 0 ]; then
      echo -e "\tuse localectl to update locale" 
      localectl set-locale LANG=en_US.utf8
    else
      echo -e "\tneither update-locale nor localectl found ... skip locale settings"
    fi
  
  fi
  export LANG=en_US.utf8
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

# updatePackages()
# Description:
#  Update the software packages list and cache if need
# Global Vars: os
# Input : 
# Output: 
# Return value: 0
updatePackages() {
  if [ "$os" = "ubuntu1804" ]; then
    # apt-get update if /var/lib/apt/lists not exist or if last update > 86400 secs (1 day) 
    apt_update=0
    if [ ! -d "/var/lib/apt/lists" ]; then 
      apt_update=1
    else
      # time of last data modification, seconds since Epoch
      apt_last_mod=$(stat -c "%Y" /var/lib/apt/lists)
      # now in seconds since Epoch
      now=$(date "+%s")
      if [ $(( $now - $apt_last_mod )) -gt 86400 ]; then
        apt_update=1 
      fi
    fi
    if [ "$apt_update" -eq 1 ]; then
      echo -e "update software packages via apt-get update"
      # Remove interactive questions and same time lock "apt install"
      echo '* libraries/restart-without-asking boolean true' | debconf-set-selections
      apt-get update >/dev/null 2>&1
    fi
  fi
}

# updateAllSoftware()
# Description:
#  Update software to all new version a patch
# Global Vars: os
# Input : 
# Output: 
# Return value: 0
updateAllSoftware() {
  if [ "$os" = "centos7" ]; then
    echo "Updating all software via yum update -y -q"
    yum update -y -q >/dev/null 2>&1
  elif [ "$os" = "ubuntu1804" ]; then
    echo "Updating all software via "apt dist-upgrade -y -q
    apt dist-upgrade -y -q >/dev/null 2>&1
  fi
}

# existPkg()
# Description:
#  Check if a package is already installed
# Global Vars: os
# Input : $1=package to check
# Output:
# Return value: 0 if package is installed, not 0 else
existPkg() {
  pkg="$1"
  if [ "$os" = "centos7" ]; then
    rpm -q --quiet "$pkg" >/dev/null 2>&1
  elif [ "$os" = "ubuntu1804" ]; then
    dpkg -l "$pkg" 2>&1 | grep '^ii' >/dev/null 2>&1
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
      yum install -y -q "$pkg" >/dev/null 2>&1
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

# privateNet()
# Description:
#  Configure private cluster network
# Global Vars: eth2, os, PRIV_NET_CLUSTER, HOSTID, PRIV_NET_START
# Input :
# Output:
# Return value: 0
privateNet() {
  local addr
  local cidr
  echo "Check private cluster network ..."
  if [ -z ${eth2} ]; then
    echo -e "\t [ERROR] I cannot find eth2 net interface for building cluster ... exiting now"
    exit 2
  fi
  if [ "$os" = "centos7" ]; then
    if [ ! -f "/etc/sysconfig/network-scripts/ifcfg-${eth2}" ]; then
      echo -e "\tconfiguring private cluster network on ${eth2}"
      addr="${PRIV_NET_CLUSTER}.$(($HOSTID + $PRIV_NET_START))"
      cat <<EOF >/etc/sysconfig/network-scripts/ifcfg-${eth2}
DEVICE="${eth2}"
ONBOOT="yes"
BOOTPROTO=static
IPADDR=${addr}
NETMASK=${PRIV_NETMASK_CLUSTER}
NM_CONTROLLED=no
TYPE=Ethernet
EOF
      /etc/sysconfig/network-scripts/ifup ${eth2}
    else
      echo -e "\tprivate cluster network on ${eth2} already configured, skip"
    fi
  elif [ "$os" = "ubuntu1804" ]; then
    # ubuntu 1804 use netplan for networks
    if [ ! -f "/etc/netplan/60-cluster00.yaml" ]; then
      echo -e "\tconfiguring private cluster network on ${eth2}"
      cidr=$(fromNetmaskToCidr ${PRIV_NETMASK_CLUSTER})
      addr="${PRIV_NET_CLUSTER}.$(($HOSTID + $PRIV_NET_START))/${cidr}"
      cat <<EOF >/etc/netplan/60-cluster00.yaml
---
network:
  version: 2
  renderer: networkd
  ethernets:
    ${eth2}:
      addresses:
      - ${addr}
EOF
      netplan generate
      systemctl restart systemd-networkd.service
    else
      echo -e "\tprivate cluster network on ${eth2} already configured, skip"
    fi
  fi
}

# enableFirewall()
# Description:
#  Enable firewall soon and at start up 
# Global Vars: os, LANG
# Input : 
# Output: 
# Return value: 0
enableFirewall() {
  if [ "$os" = "centos7" ]; then
    firewall-cmd --state -q
    if [ $? = 0 ]; then
      echo -e "\tfirewalld firewall is already active"
    else
      echo -e "\tactiving firewalld firewall"
      systemctl unmask firewalld
      systemctl start firewalld
      systemctl enable firewalld
    fi
  elif [ "$os" = "ubuntu1804" ]; then
    LANG= ufw status | grep -q 'Status: active'
    if [ $? = 0 ]; then
      echo -e "\tufw firewall is already active"
    else
      echo -e "\tactiving ufw firewall"
      ufw --force enable >/dev/null 2>&1
    fi
  fi
}

# preRuleFirewall()
# Description:
#  Add group of rules to firewall for main service on cluster
# Global Vars: os
# Input : 
# Output: 
# Return value: 0
preRuleFirewall() {
  if [ "$os" = "ubuntu1804" ]; then
    if [ ! -f "/etc/ufw/applications.d/cluster" ]; then
      cat <<EOF >/etc/ufw/applications.d/cluster
[cluster]
title=Cluster
description=Cluster linux with Pacemaker and Corosync.
ports=2224/tcp|3121/tcp|5403/tcp|5404/udp|5405/udp|21064/tcp|9929/tcp|9929/udp
EOF
    fi
    if [ ! -f "/etc/ufw/applications.d/apache" ]; then
      cat <<EOF >/etc/ufw/applications.d/apache
[apache]
title=Apache
description=Apache web server
ports=80/tcp|443/tcp
EOF
    fi
  fi
}

# firewallAddRule()
# Description:
#  Add a rule $1 in the firewall
# Global Vars: os
# Input : $1= rule to add
# Output: 
# Return value: 0
firewallAddRule() {
  r="$1"
  if [ "$os" = "centos7" ]; then
    if [ $r = "OpenSSH" ]; then r="ssh"; fi
    if [ $r = "cluster" ]; then r="high-availability"; fi
    if [ $r = "apache" ]; then r="http"; fi
    firewall-cmd --list-services | grep "$r" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
      firewall-cmd --permanent --add-service=$r >/dev/null 2>&1
      firewall-cmd --add-service=$r >/dev/null 2>&1
      echo -e "\tadded $r rules to Firewalld"
    else
      echo -e "\t$r rules already enabled, skipping"
    fi
  elif [ "$os" = "ubuntu1804" ]; then
    ufw status | grep -q "$r" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
      ufw allow "$r" >/dev/null 2>&1
      echo -e "\tadded $r rules to ufw firewall"
    else
      echo -e "\t$r rules already enabled, skipping"
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

if [ "$debug" = "true" ]; then
  echo "[DEBUG] Input params: "
  echo "  debug=$debug, NUM_CLUSTER_NODES=$NUM_CLUSTER_NODES, PRIV_NET_CLUSTER=$PRIV_NET_CLUSTER, PRIV_NETMASK_CLUSTER=$PRIV_NETMASK_CLUSTER, PRIV_NET_START=$PRIV_NET_START, NET_RESOURCES=$NET_RESOURCES, NET_RESOURCES_START=$NET_RESOURCES_START, SOFTWARE_UPDATE=$SOFTWARE_UPDATE, SECURE_VAGRANT_USER_PWD=$SECURE_VAGRANT_USER_PWD, hacluster_pwd=$hacluster_pwd, vagrant_user_pwd=$vagrant_user_pwd"
fi

HOSTNAME=$(hostname)
HOSTID=$(echo $HOSTNAME | sed 's/.*-//')
pre_node=$(echo $HOSTNAME | sed -e 's/^cluster-//' -e 's/[0-9]*$//')
os=$(getOS)
eths=$(ip address | grep '^[0-9]' | awk '{print $2}' | uniq | grep -v lo | sed 's/://g' | sed 's/@.*$//')
eth1=$(echo $eths | awk '{print $1}')
eth2=$(echo $eths | awk '{print $2}')
eth3=$(echo $eths | awk '{print $3}')

if [ "$debug" = "true" ]; then
  echo "[DEBUG] HOSTNAME=$HOSTNAME, HOSTID=$HOSTID, pre_node=$pre_node, os=$os"
fi
echo "network interfaces found: $eth1 $eth2 $eth3"

waitReboot
setLocale
if [ "$os" = "centos7" ]; then
  packages="deltarpm pacemaker pcs httpd wget"
  httpd_conf="/etc/httpd/conf/httpd.conf"
  httpd_service="httpd"
  firewall="firewalld"
  grep -q deltarpm /etc/yum.conf >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo 'deltarpm=0' >>/etc/yum.conf
  fi
elif [ "$os" = "ubuntu1804" ]; then
  packages="pacemaker corosync-qdevice pcs apache2 wget"
  httpd_conf="/etc/apache2/apache2.conf"
  httpd_service="apache2"
  firewall="ufw"
else
  echo "OS: $os not available: use 'centos7' or 'ubuntu1804'"
  exit 2
fi

updatePackages
if [ "$SOFTWARE_UPDATE" = "true" ]; then
  updateAllSoftware
fi
if [ "$SECURE_VAGRANT_USER_PWD" = "true" ]; then
  echo "Securing vagrant password to '$vagrant_user_pwd'"
  echo "vagrant:$vagrant_user_pwd" | chpasswd
fi
privateNet
pkg_new=''
echo "Check necessary packages ..."
pcs_installed=1
existPkg pcs
if [ $? -ne 0 ]; then
  pcs_installed=0
fi
for p in $packages; do
  installPkg "$p"
done
if [ $pcs_installed -eq 0 ]; then
  echo -e "\tremoving default cluster config initialized by previous installed packages (if any)"
  pcs cluster destroy --force 
fi
apache_restart=0
echo "Checking apache configuration ..."
if [ "$os" = "centos7" ]; then
  test_prov=$(sed -n '/# :START Vagrant provision/,/# :END Vagrant provision/p' $httpd_conf)
  if [ -z "$test_prov" ]; then
    apache_restart=1
    cat <<EOF >>$httpd_conf
# :START Vagrant provision
<Location /server-status>
        SetHandler server-status
	Require local
</Location>
# :END Vagrant provision
EOF
  else
    echo "$httpd_conf Vagrant provision not necessary"
  fi
elif [ "$os" = "ubuntu1804" ]; then
  if [ ! -e "/etc/apache2/mods-enabled/status.load" ]; then
    echo -e "\tenabling mod_status"
    a2enmod status
    apache_restart=1
  fi
  if [ ! -e "/etc/apache2/sites-enabled/000-default.conf" ]; then
    echo -e "\tenabling default virtual host"
    a2ensite 000-default
    apache_restart=1
  fi
fi
if [ "$apache_restart" -eq 1 ]; then
  echo -e "\trestarting $httpd_service"
  systemctl restart "$httpd_service"
else
  echo -e "\talready configured, skip"
fi

systemctl stop "$httpd_service" >/dev/null 2>&1
systemctl disable "$httpd_service" >/dev/null 2>&1

grep -q 'Linux Cluster Test' /var/www/html/index.html >/dev/null 2>&1
if [ $? -ne 0 ]; then
  if [ -e "/var/www/html/index.html" ]; then
    mv /var/www/html/index.html /var/www/html/index.html.orig
    chmod 600 /var/www/html/index.html.orig
  fi
  cat <<EOF >>/var/www/html/index.html
<!DOCTYPE html>
<html> <head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style id='linux-text-cluster-inline-quolltech-css' type='text/css'>
  body {margin: 0;}
  #top { position:fixed; top:86px; left:72px; transform:rotate(90deg); transform-origin:0% 0%; background-color: #f94701; background-image: linear-gradient(to right,#a6a6a6,#c9c925,#1e73be,#fe36f9,#0fe22a,#fe4809); text-align:center; padding:5px; border-radius:5px; opacity:0.9;}
  #top div {font-size:14px;}
  h2 { font-size:20px; margin-bottom:10px; margin-top:10px; }
  #test_frame {width:100vw;height:99vh;border:0px hidden;margin:0;padding:0;}
</style> </head>
<body>
<div id="top"> <h2>Linux Cluster Test: Cps, Pacemaker, Corosync</h2> <div>$HOSTNAME - by Quoll Tech</div> </div>
<iframe id="test_frame" src="https://quoll.it/servizi-chiedi-un-preventivo/"></iframe>
<script type="text/javascript">
  function quoll_resize() {el=document.getElementById("top"); el_h=el.offsetHeight; el.style.left = el_h +"px";}  
  quoll_resize()
  window.onresize = quoll_resize;
</script>
</body> </html>
EOF
fi

echo "setting hapassword to '$hacluster_pwd'"
echo "hacluster:$hacluster_pwd" | chpasswd
echo "update cluster network in /etc/hosts"
sed -i '/# :START Vagrant node provision/,/# :END Vagrant node provision/d' /etc/hosts
echo -e "# :START Vagrant node provision" >> /etc/hosts
for nid in $(seq 1 $NUM_CLUSTER_NODES); do
  echo -e "${PRIV_NET_CLUSTER}.$(($nid + $PRIV_NET_START))\t ${pre_node}${nid}" >> /etc/hosts
done
echo -e "# :END Vagrant node provision" >> /etc/hosts


echo -e "Check $firewall firewall package"
existPkg "$firewall"
if [ $? -eq 0 ]; then
  enableFirewall
  echo -e "Check $firewall firewall rules"
  preRuleFirewall
  firewallAddRule OpenSSH
  firewallAddRule cluster
  firewallAddRule apache
else
  echo -e "$firewall firewall package not installed, skip"
fi

echo "Checking pcsd service ..."
systemctl is-active pcsd.service >/dev/null 2>&1
if [ $? -ne 0 ]; then
  echo -e "\tstarting pcsd.service [systemctl start pcsd.service]"
  systemctl start pcsd.service >/dev/null 2>&1
else
  echo -e "\tpcsd.service already started, skip"
fi
systemctl is-enabled pcsd.service >/dev/null 2>&1
if [ $? -ne 0 ]; then
  echo -e "\tenable pcsd.service [systemctl enable pcsd.service]"
  systemctl enable pcsd.service >/dev/null 2>&1
else
  echo -e "\tpcsd.service already enabled, skip"
fi
echo $pkg_new | grep -q pacemaker
if [ $? -eq 0 ]; then
  echo -e "\tdestroy default cluster if any (es. debian cluster)"
  pcs cluster destroy >/dev/null 2>&1
fi
