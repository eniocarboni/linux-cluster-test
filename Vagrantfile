# **
# Linux-cluster-test
# Copyright (c) 2020 Enio Carboni (enio.carboni __at__ gmail.com)
# Distributed under the GNU GPL v3. For full terms see the file LICENSE.
# **
# Description: Simulate a linux N node cluster with cps, Pacemaker and Corosync in Centos 7 ior Ubuntu 1804 lts vms
# **

# DEBUG_SCRIPT: if true enable debug on provision scripts
$DEBUG_SCRIPT=false
# NUM_CLUSTER_NODES: Number of Cluster Nodes VM we must create
$NUM_CLUSTER_NODES=3
# ALWAYS_CHANGE_ALL_PASSWORD: If true, all passwords will be changed, otherwise those already present in the vagrant_pwd directory will be used
# [ default: false ]
$ALWAYS_CHANGE_ALL_PASSWORD=false
# Enable or not a test ssh fence agent on a hostonly private net
# See vagrant_pwd/.fencecluster for fence user password
# if change $FENCE_AGENT from false to true you must restart vms to attach hostonly private net (or use "vagrant reload && vagrant provision")
$FENCE_AGENT=true
# SOFTWARE_UPDATE: if we must update all software during vm provision [ default to false for no update ]
$SOFTWARE_UPDATE=false
# Securing user vagrant password? (Vagrant default disable ssh password auth but the password is default!)
# See vagrant_pwd/.vagrant_pwd file
$SECURE_VAGRANT_USER_PWD=true
# I found problem on lxd in parallel mode (lock problem)
ENV["VAGRANT_NO_PARALLEL"]="1"
# Start: OS
# ----------------------
# Don't change $OS after first provision
# $OS: Operating system: centos7 or ubuntu1804
$OS="centos7"
#$OS="ubuntu1804"
if $OS == 'centos7'
  $BOX="generic/centos7"
  $BOX_LXD="capensis/centos7"
  $PRE_NODE_NAME="cl-c7-node-"
  $PRIV_NET_START=10
else
  $BOX="ubuntu/bionic64"
  $BOX_LXD="capensis/ubuntu18.04.x86_64"
  $PRE_NODE_NAME="cl-u18-node-"
  $PRIV_NET_START=100
end 
# End: OS
# ----------------------
# Start: Networks envs:
# ---------------------
# Private Network cluster
$PRIV_NET_CLUSTER="192.168.33"
# Private netmask for network cluster $PRIV_NET_CLUSTER
$PRIV_NETMASK_CLUSTER="255.255.255.0"
# Network for cluster resource ip (IPaddr2)
$NET_RESOURCES="192.168.33"
# Network for cluster resource ip start from ip $NET_RESOURCES_START + $PRIV_NET_START from net $NET_RESOURCES
$NET_RESOURCES_START="30"
# Private Network fence (stonith) cluster
$PRIV_NET_FENCE_CLUSTER="192.168.43"
# Private netmask for network cluster $PRIV_NET_FENCE_CLUSTER
$PRIV_NETMASK_FENCE_CLUSTER="255.255.255.0"
# End: Networks envs:
# ----------------------

require_relative 'vagrant_include/vagrant_passwords.rb'

$SCRIPT_ARGS="'#{$DEBUG_SCRIPT}' '#{$NUM_CLUSTER_NODES}' '#{$PRIV_NET_CLUSTER}' '#{$PRIV_NETMASK_CLUSTER}' '#{$PRIV_NET_START}' '#{$NET_RESOURCES}' '#{$NET_RESOURCES_START}' '#{$SOFTWARE_UPDATE}' '#{$SECURE_VAGRANT_USER_PWD}' '#{$hacluster_pwd}' '#{$vagrant_user_pwd}'"
$SCRIPT_ARGS_fence=$SCRIPT_ARGS + " '#{$FENCE_AGENT}' '#{$PRIV_NET_FENCE_CLUSTER}' '#{$PRIV_NETMASK_FENCE_CLUSTER}' '#{$fencecluster_pwd}'"
vm_order=(2..$NUM_CLUSTER_NODES).to_a << 1
Vagrant.configure("2") do |config|
  vm_order.each do |i|
    config.vm.define "#{$PRE_NODE_NAME}#{i}" do |node|
      node.vm.box = $BOX
      # Cluster private net for Carousync
      node.vm.network "private_network", ip: "#{$PRIV_NET_CLUSTER}.#{i + $PRIV_NET_START}", auto_config: false
      if $FENCE_AGENT
        # private net for fencing (pcs stonith)
         node.vm.network "private_network", ip: "#{$PRIV_NET_FENCE_CLUSTER}.#{i + $PRIV_NET_START}", auto_config: false
      end
      node.vm.hostname = "cluster-#{$PRE_NODE_NAME}#{i}"
      node.vm.synced_folder ".", "/vagrant", disabled: true
      node.vm.provider "virtualbox" do |vb, override|
        vb.name = "#{$PRE_NODE_NAME}#{i}"
        vb.memory = "1024"
        vb.customize ["modifyvm", :id, "--groups", "/cluster/#{$OS}"]
        vb.linked_clone = true if Gem::Version.new(Vagrant::VERSION) >= Gem::Version.new('1.8.0')
      end
      node.vm.provider 'lxd' do |lxd, override|
        override.vm.box = $BOX_LXD
        lxd.name = "#{$PRE_NODE_NAME}#{i}"
        lxd.api_endpoint = 'https://127.0.0.1:8443'
        lxd.profiles = ['default']
        lxd.environment = {}
        lxd.config = {}
        lxd.devices = {
          eth1: { name: 'eth1', nictype: 'macvlan', parent: 'eno1', type: 'nic' },
          eth2: { name: 'eth2', nictype: 'macvlan', parent: 'eno1', type: 'nic' }
        }
      end
      node.vm.provision "Test if we need some workarounds", 
        type: "shell", 
        path: "provision_scripts/00-workarounds.sh", 
        args: $SCRIPT_ARGS
      node.vm.provision "Update software and configure node", 
        type: "shell", 
        path: "provision_scripts/10-node_configuration.sh", 
        args: $SCRIPT_ARGS
      node.vm.provision "Prepare to cluster fence agent", 
        type: "shell", 
        path: "provision_scripts/30-stonith-fence_node_configuration.sh", 
        args: $SCRIPT_ARGS_fence
      if i == 1
        node.vm.provision "Configuring Cluster via pcs on all nodes", 
          type: "shell", 
          path: "provision_scripts/90-single-cluster_configuration.sh", 
          args: $SCRIPT_ARGS
        node.vm.provision "Configuring Cluster fence agent on all nodes", 
          type: "shell", 
          path: "provision_scripts/92-single-stonith-fence_cluster_configuration.sh", 
          args: $SCRIPT_ARGS_fence
        node.vm.provision "Show Cluster status", 
          type: "shell", 
          path: "provision_scripts/99-single-show-cluster-status.sh", 
          args: $SCRIPT_ARGS, 
          keep_color: true
      end
      node.trigger.before :destroy do |trigger|
        trigger.warn = "Remove this node to cluster members before destroy it"
        trigger.on_error = :continue
        trigger.run_remote = {
          path: "provision_scripts/triggers/trigger_before_destroy.sh",
          args: $SCRIPT_ARGS
          }
      end
    end
  end
end
