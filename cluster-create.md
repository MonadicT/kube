
# Table of Contents

1.  [Introduction](#org93fc546)
2.  [The TL;DR Version](#org80d340c)
3.  [Longer Version](#org5a7d5a7)
    1.  [Initial preparation](#org22fd5e0)
    2.  [Creating Virtual Machines](#org3cda5ee)
    3.  [Ansible setup](#orge7ac315)
    4.  [Ansible Inventory File](#org94a4160)
    5.  [Create Master](#orgc03f769)
    6.  [Create Workers](#org22b0e3a)
    7.  [Create Storage Provisioner](#org7635633)
    8.  [Bash it all in!](#org0466325)
4.  [Deploy Wordpress and MySql](#org793b618)
5.  [Closing Remarks](#org587f264)

    head -n 5 blurb.txt


<a id="org93fc546"></a>

# Introduction

It's really easy to provision a cluster on any of the Kubernetes
cluster providers. All it takes is a few clicks on a web page, a
loaded credit card and your cluster materializes just like that! But,
what if you want to save a few bucks and setup a cluster in a home
network, on some hardware you have lying around?

There appear to be a number of solutions that people have
developed. After taking a look at some of them, I decided to do
something that catered to my specific needs. It does feel like a bit
like NIH syndrome and if you don't like this sort of thing, please hit
the back button now!

If you are still here, great! I will show you how you can bring up a
Kubernetes cluster with Vagrant and Ansible. There are some pitfalls in
using Vagrant boxes for Kubernetes nodes. But the upside is a better
understanding of troubleshooting of Kubernetes networking
configuration. In the end, we have a single shell command which
creates the cluster and another one to install Wordpress and MySql.

My hardware is an old Sun server running Ubuntu 18.04. So, everything
here is tailored for that distribution. While it should be easy to
adapt this to suit your choice of distribution, it will require some
modifications.

All the source code is available in GitHub repo [kube](https://github.com/MonadicT/kube).


<a id="org80d340c"></a>

# The TL;DR Version

-   Clone [kube](https://github.com/MonadicT/kub) repo

    `git clone https://github.com/MonadicT/kube`

-   Review and adjust `cluster.conf` file to suit your needs

<table border="2" cellspacing="0" cellpadding="6" rules="groups" frame="hsides">


<colgroup>
<col  class="org-left" />

<col  class="org-left" />

<col  class="org-left" />
</colgroup>
<thead>
<tr>
<th scope="col" class="org-left">Variable</th>
<th scope="col" class="org-left">Value</th>
<th scope="col" class="org-left">&#xa0;</th>
</tr>
</thead>

<tbody>
<tr>
<td class="org-left">BRIDGE\_IF</td>
<td class="org-left">"enp4s0f1"</td>
<td class="org-left">Host interface to use for bridge interface creation in guest</td>
</tr>


<tr>
<td class="org-left">MASTER\_IP\_NW</td>
<td class="org-left">"192.168.1.0/24"</td>
<td class="org-left">Subnet for Vagrant boxes</td>
</tr>


<tr>
<td class="org-left">MASTER\_IP</td>
<td class="org-left">"192.168.1.10"</td>
<td class="org-left">IP address of Master</td>
</tr>


<tr>
<td class="org-left">NFS\_IP</td>
<td class="org-left">"192.168.1.8"</td>
<td class="org-left">IP address of NFS server</td>
</tr>


<tr>
<td class="org-left">WORKER\_IP</td>
<td class="org-left">"192.168.1.#{i + 10}"</td>
<td class="org-left">Worker IP pattern (generates 192.168.1.11, 192.168.1.12&#x2026;)</td>
</tr>


<tr>
<td class="org-left">WORKER\_COUNT</td>
<td class="org-left">1</td>
<td class="org-left">Number of workers</td>
</tr>
</tbody>
</table>

-   Ensure you have Vagrant installed

    <https://www.vagrantup.com/docs/installation/>

-   Ensure you have Ansible installed

    `sudo apt install ansible`

-   Change directory to cloned repo

    `cd kube`

-   Build cluster with

    `./create-cluster.sh`
-   Verify cluster build with

    `./verify-cluster.sh`

-   Deploy Wordpress

    `./deploy-wordpress.sh`

Review the output from `verify-cluster.sh`. If everything worked as
expected, you should have a fully functional Kubernetes cluster on
hand. Your Wordpress deployment can be viewed at
`http://<MASTER_IP>:31234`.


<a id="org5a7d5a7"></a>

# Longer Version


<a id="org22fd5e0"></a>

## Initial preparation

-   Clone [kube](https://github.com/MonadicT/kub) repo using git.
-   Install Ansible if needed. If you are on a Ubuntu system, `sudo apt
      install ansible` should do the trick.
-   Install Vagrant if needed. Please follow the directions at
    [Vagrant Installation](https://www.vagrantup.com/docs/installation/)


<a id="org3cda5ee"></a>

## Creating Virtual Machines

Cluster formation requires nodes to run Kubernetes masters and
workers. We will create the necessary virtual machines using [Vagrant](https://www.vagrantup.com/)
and [Virtual Box](https://www.virtualbox.org/). Our cluster will have a single master (not something
you would ever do in a production environment), three worker nodes and
a node for NFS server to act as an external storage provisioner.

The `cluster.conf` file can be edited to alter the number of worker
nodes created. You can also change the IP addresses of the master,
workers and NFS nodes. Note that I chose to use bridge networking and
expose all the nodes to my home LAN. I also use the address range
192.168.1.8 to 192.168.1.13 which are static IP addresses in my
environment. You can change these to suit your networking environment
by editing the Vagrant file.

`vagrant up` will bring up all the nodes.

Note that `Vagrantfile` is recreated when you run
`create-cluster.sh`. Any manual changes made directly to `Vagrantfile`
will be lost!


<a id="orge7ac315"></a>

## Ansible setup

Ansible happens to be a great tool for automating commands and is
invaluable when you need to work with multiple machines as we do
here. Ansible can be installed on most OS and for my Ubuntu host
machine, the following does the trick.

    sudo apt install ansible

When vagrant creates boxes, it sets up a configuration directory in
`.vagrant` with SSH connection details for all the machines. This lets
you connect to a Vagrant box with `vagrant ssh master`. However,
Ansible requires a more traditional SSH access to nodes. Luckily,
`vagrant ssh-config` command outputs a configuration that is usable by
OpenSSH clients. Our streak of luck continues with Ansible which
allows customization of SSH command. We specify the location of
`ssh_config` with `-F` option and Ansible can execute SSH commands.

This creates our SSH config file `ssh_config`.

    vagrant ssh-config > ssh_config

This informs Ansible to use `ssh_config`.

    [ssh_connection]
    ssh_args = -C -o ControlMaster=auto -o ControlPersist=60s -F ssh_config

With this accomplished, we can run the playbooks to install Kubernetes
software on the nodes.


<a id="org94a4160"></a>

## Ansible Inventory File

Ansible's configurartion file resides in
`/etc/ansible/ansible.cfg`. By default, Ansible operates on the
inventory of machines maintained in `/etc/ansible/hosts`. With a local
copy of `ansible.cfg`, we can modify Ansible's behavior as
needed. Here is the changed part of the configuration that lets us
maintain the inventory of files in `hosts` file.

    [defaults]

    # some basic default values...

    inventory      = hosts

Note that `hosts` file is recreated when you execute
`create-cluster.sh`. To change the number of workers, `cluster.conf`
file should modified.


<a id="orgc03f769"></a>

## Create Master

Executing the following command configures Kubernetes master.

    ansible-playbook kmaster.yml

There are a few things worth noting in `master.yml`.

    - name: Pick IP from the same network as master
      set_fact: hostip="{{ ansible_all_ipv4_addresses|ipaddr(master_ip_nw) }}"

The task above is selecting an IPv4 address from the network specified
in `master_ip_nw` in `cluster.conf`. Vagrant creates two Ethernet
interfaces, `enp0s3` and `enp0s8`. Flannel, the POD network that I am
using in the cluster, selects the first network interface `enp0s3`
which is Vagrant's NAT network interface and unsuitable for
Kubernetes. We need Flannel to use `enp0s8` interface so that packets
get routed as expected.

The following Ansible task instructs the kernel to send the packets
received by Virtual Box bridge interface to `iptables` for processing.

    - name: Send bridge packets to iptables for processing
      block:
      - lineinfile:
          path: /etc/sysctl.conf
          line: net.bridge.bridge-nf-call-iptables=1
          create: yes
      - lineinfile:
          path: /etc/sysctl.conf
          line: net.bridge.bridge-nf-call-ip6tables=1
          create: yes
      - command: sysctl net.bridge.bridge-nf-call-iptables=1
      - command: sysctl net.bridge.bridge-nf-call-ip6tables=1
      become: true

Lastly, here we initialize the cluster and inform the pod network CIDR
and the IP address API server should listen at.

    - name: Initialize cluster
      command: kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address "{{ hostip[0] }}"
      when: inited.rc > 0
      become: true


<a id="org22b0e3a"></a>

## Create Workers

    ansible-playbook kworker.yml

`kworker.yml` is the Ansible playbook to configure `worker<N>`
nodes. This prepares the worker nodes by installing Kubernetes software and NFS client software.

Note that worker playbook doesn't run the cluster join command. After
the execution of the playbook, `create-cluster.sh` obtains the token
needed to join the cluster and runs it on each worker node as shown below.

    # Join all workers to cluster
    JOIN_CMD=$(ansible masters -m shell -b -a "kubeadm token create --print-join-command"|awk '{sub(/.*>>/, "");print}')
    ansible workers -m shell -b -a "$JOIN_CMD"


<a id="org7635633"></a>

## Create Storage Provisioner

A storage provisioner is handy to have in our cluster. I chose NFS as
the external storage provisioner. The `nfs.yml` playbook configures
the `nfs` box.


<a id="org0466325"></a>

## Bash it all in!

The above steps are the major building blocks of my approach to
creating a cluster. [create-cluster.sh](https://github.com/MonadicT/kube/blob/master/create_cluster.sh), has all the glue
to pull them together so that we can create the cluster using the
following command.

Once we have the cluster created, we can run the command below and
examine the output produced for any errors. In particular, DNS lookups
must work or our cluster will be unusable.

    ./verify-cluster.sh


<a id="org793b618"></a>

# Deploy Wordpress and MySql

Execute `./deploy-wordpress.sh` to deploy Wordpress and MySql in your
cluster. Once completed, you can navigate to `http:<MASTER_IP>:31234`
and proceed with installing Wordpress and configuration.


<a id="org587f264"></a>

# Closing Remarks

So, that concludes our foray into provisioning a Kubernetes
cluster. Being able to create and destroy clusters (`vagrant destroy
-f`) at will has been very useful in my work. Hopefully, you will give
this a try.
