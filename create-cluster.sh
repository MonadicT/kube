#!/bin/bash

# Source configuration file
[[ -f "cluster.conf" ]] && source "cluster.conf"

# Configuration
MASTER_COUNT=1
WORKER_COUNT=${WORKER_COUNT:-2}
MASTER_IP_NW=${MASTER_IP_NW:-"192.168.1.0/24"}
MASTER_IP=${MASTER_IP:-"192.168.1.10"}
WORKER_IP=${WORKER_IP:-"192.168.1.#{i + 10}"}
NFS_IP=${NFS_IP:-"192.168.1.8"}

create_ansible_inventory_file() {
    # Create hosts file
    echo "[masters]" > hosts
    echo "master" >> hosts
    echo "[workers]" >> hosts
    for i in `seq 1 $WORKER_COUNT`
    do
        echo "worker$i" >> hosts
    done
    echo "[nfs_servers]" >> hosts
    echo "nfs" >> hosts
}


create_vagrantfile() {
    cat > Vagrantfile <<EOF
BOX="ubuntu/xenial64"
MASTER_COUNT=$MASTER_COUNT
WORKER_COUNT=$WORKER_COUNT
MASTER_IP="$MASTER_IP"
NFS_IP="$NFS_IP"

Vagrant.configure("2") do |config|
  # The most common configuration options are documented and commented below.
  # For a complete reference, please see the online documentation at
  # https://docs.vagrantup.com.

  # Every Vagrant development environment requires a box. You can search for
  # boxes at https://vagrantcloud.com/search.
  config.vm.provider "virtualbox" do |v|
    v.memory = 2048
    v.cpus = 2
  end

  config.vm.define "master" do |subconfig|
    subconfig.vm.box = BOX
    subconfig.vm.hostname = "master"
    subconfig.vm.network :public_network, ip: "$MASTER_IP", bridge: "$BRIDGE_IF"
  end

  config.vm.provision "shell", inline: <<-SHELL
    apt-get update
    apt-get install -y python
SHELL

  (1..WORKER_COUNT).each do |i|
    config.vm.define "worker#{i}" do |subconfig|
      subconfig.vm.box = BOX
      subconfig.vm.hostname = "worker#{i}"
      subconfig.vm.network :public_network, ip: "$WORKER_IP", bridge: "$BRIDGE_IF"
      subconfig.vm.provision "shell", inline: <<-SHELL
          apt-get update
          apt-get install -y python
SHELL
    end

  end

  config.vm.define "nfs" do |subconfig|
    subconfig.vm.box = BOX
    subconfig.vm.hostname = "nfs"
    subconfig.vm.network :public_network, ip: "$NFS_IP", bridge: "$BRIDGE_IF"
    subconfig.vm.provider "virtualbox" do |vb|
      vb.customize ["modifyvm", :id, "--memory",  4096]
      vb.customize ["modifyvm", :id, "--cpus", 2]
    end
  end
end

EOF
}

create_nfs_client_provisioner_deploy() {
    cat > deploy-nfs-cp.yml <<EOF
kind: Deployment
apiVersion: apps/v1
metadata:
  name: nfs-client-provisioner
spec:
  replicas: 1
  selector:
      matchLabels:
            app: nfs-client-provisioner
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: nfs-client-provisioner
    spec:
      serviceAccountName: nfs-client-provisioner
      containers:
        - name: nfs-client-provisioner
          image: quay.io/external_storage/nfs-client-provisioner:latest
          volumeMounts:
            - name: nfs-client-root
              mountPath: /persistentvolumes
          env:
            - name: PROVISIONER_NAME
              value: mynfs
            - name: NFS_SERVER
              value: $NFS_IP
            - name: NFS_PATH
              value: /nfs
      volumes:
        - name: nfs-client-root
          nfs:
            server: $NFS_IP
            path: /nfs

EOF
}

create_vms() {
    # Create virtual machines
    vagrant up
    vagrant ssh-config > ssh_config
}

configure_master() {
    # Run playbooks to setup cluster
    ansible-playbook kmaster.yml --extra-vars "master_ip_nw=$MASTER_IP_NW"

    # Copy cluster config to local
    ansible --verbose masters  -m fetch -b -a "src=/etc/kubernetes/admin.conf dest=./ flat=true"
}

configure_network() {
    # Create overlay network
    kubectl apply -f kube-flannel.yml
}

configure_workers() {
    # Run worker and NFS playbooks
    ansible-playbook kworker.yml

    # Join all workers to cluster
    JOIN_CMD=$(ansible masters -m shell -b -a "kubeadm token create --print-join-command 2>/dev/null"|awk '{sub(/.*>>/, "");print}')
    ansible workers -m shell -b -a "$JOIN_CMD"
}

configure_nfs() {
    ansible-playbook nfs.yml
    # Setup kubectl configuration
    export KUBECONFIG=admin.conf

    # Configure NFS Client provisioner
    kubectl apply -f rbac-nfs-cp.yml
    kubectl apply -f sc-nfs-cp.yml
    kubectl apply -f deploy-nfs-cp.yml
}

create_ansible_inventory_file
create_vagrantfile
create_nfs_client_provisioner_deploy
create_vms
configure_master
configure_network
configure_workers
configure_nfs

exit 0
