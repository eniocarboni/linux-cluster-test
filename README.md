## Linux-cluster-test

[![GPL License](https://img.shields.io/badge/license-GPL-blue.svg)](https://www.gnu.org/licenses/)
[![Release v 0.1](https://img.shields.io/badge/release-v.0.1-green.svg)](https://github.com/eniocarboni/Linux-cluster-test)
[![Donate](https://img.shields.io/badge/Donate-PayPal-green.svg)](https://www.paypal.me/EnioCarboni/5)

**Linux-cluster-test** is a Vagrant environment test for Linux cluster based on Pacemaker and Corousync using pcs CLI interface.
It use a Centos 7 or Ubuntu 1804 lts vm

## Installation

```
mkdir linux-cluster-test
cd linux-cluster-test
git clone https://github.com/eniocarboni/linux-cluster-test .
```

## Use

First, check the Vagrant file.
```
vagrant up
vagrant up
vagrant provision
```
By default, use 3 cluster node and a simple fence ssh agent (see https://github.com/nannafudge/fence_ssh).

### Vagrantfile config variables

In Vagrantfile you can configure the following variables:
* **$DEBUG_SCRIPT**: if true enable debug on provision scripts `[default false]`
* **$NUM_CLUSTER_NODES**: number of cluster nodes we must create `[default 3]`
* **$ALWAYS_CHANGE_ALL_PASSWORD=**: if true, all passwords will be changed, otherwise those already present in the vagrant_pwd directory will be used `[default false]`
* **$FENCE_AGENT**: enable or not a test ssh fence agent on a hostonly private net `[default false]`
* **$SOFTWARE_UPDATE**: if we must update all software during vm provision `[default false]`
* **$SECURE_VAGRANT_USER_PWD**: securing user vagrant password? (Vagrant default disable ssh password auth but the password is default!) `[default true]`
* **$OS**: choose between centos7 and ubuntu1804 `[default centos7]`
Networks envs:
* **$PRIV_NET_CLUSTER**: Private Network cluster `[default 192.168.33]`
* **$PRIV_NETMASK_CLUSTER**: Private netmask for network cluster **$PRIV_NET_CLUSTER** `[default 255.255.255.0]`
* **$NET_RESOURCES**: Network for cluster resource ip (IPaddr2) `[default 192.168.33]`
* **$NET_RESOURCES_START**: Network for cluster resource ip start from ip **$NET_RESOURCES_START** + **$PRIV_NET_START** from net **$NET_RESOURCES** `[default 30]`
* **$PRIV_NET_FENCE_CLUSTER**: Private Network fence (stonith) cluster `[default 192.168.43]`
* **$PRIV_NETMASK_FENCE_CLUSTER**: Private netmask for network cluster **$PRIV_NET_FENCE_CLUSTER** `[default 255.255.255.0]`

You can also run the "vagrant provision" command several times without worrying about the consequences on vms or on the cluster since the scripts in provision are smart enough to notice the operations already done.
If you need it you can change the variable **$NUM_CLUSTER_NODES** and **$FENCE_AGENT** even after the cluster has been activated in order to test it with multiple nodes and with or without "fence" agents.

### Add new nodes to cluster

You can add a node by changing the variable **$NUM_CLUSTER_NODES** for example from 3 to 4.
At this point you just need to relaunch "vagrant up && vagrant provision"

### Remove a node from cluster

Suppose we start with the default cluster with 3 nodes (Centos 7).
To decrease the cluster by one node you must:
* [optional] run "pcs cluster node remove cl-c7-node-3" from a node other than 3;
* [optional] run "pcs stonith delete stonith-ssh-3 --force" from a node other than 3
* [optional if 2 nodes remain] run "pcs property set no-quorum-policy = ignore"
* launch "vagrant destroy cl-c7-node-3"
* update the Vagrantfile by decreasing the $NUM_CLUSTER_NODES variable by one (put it at 2)
* launch "vagrant reload && vagrant provision"
However, all optional operations are fixed with "vagrant reload && vagrant provision"

### Restoring a node for problems

Suppose we want to restore a problematic node, for example node 2:
* launch "vagrant destroy cl-c7-node-2"
* launch "vagrant up cl-c7-node-2 && vagrant provision"
This operation can be done on all nodes except node 1 because it is the one that manages the cluster. If you need to do this, it will completely reset the cluster rebuilding it as new.


## Notes on operation

### Passwords

Vagrant will save the random passwords of users "vagrant", "hacluster" and "fence" in the respective files "vagrant_pwd/.vagrant_pwd", "vagrant_pwd/.hacluster_pwd" and "vagrant_pwd/.fencecluster_pwd".
During subsequent "provision" the same passwords will be used unless the **$ALWAYS_CHANGE_ALL_PASSWORD** variable is true.

### Note about the cluster resources created

The provision scripts create 4 cluster resource groupped in 3 resources:
* group apachegroup:
  * resource first_test_ip (`ocf::heartbeat:IPaddr2`)
  * resource Web1 (`ocf::heartbeat:apache`)
* group group_second_test_ip
  * resource second_test_ip (`ocf::heartbeat:IPaddr2`)
* group group_last_test_ip
  * resource last_test_ip (`ocf::heartbeat:IPaddr2`)

If **$FENCE_AGENT** is true the provision scripts create one fence resource for each node:
* stonith-ssh-1 (for node 1)
* stonith-ssh-2 (for node 2)
* stonith-ssh-3 (for node 3)
and a constraint resource for each fence resource so that to not start in the same node relative to the fence:
* stonith-ssh-1 not start on node 1
* stonith-ssh-2 not start on node 2
* stonith-ssh-3 not start on node 3

### Note on firewall

On Centos 7 use **firewalld** while on Ubuntu 1804 lts use "ufw"

## COPYRIGHT

Copyright (c) 2020 Enio Carboni - Italy

This file is part of **Linux-cluster-test**.

**Linux-cluster-test** is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

**Linux-cluster-test** is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with **Linux-cluster-test**. If not, see <http://www.gnu.org/licenses/>.
