#!/bin/bash
#Owner Sandesh KV
set -e

# Variables
MASTER_NODE="k8s-master"
WORKER_NODE1="k8s-worker1"
WORKER_NODE2="k8s-worker2"
CILIUM_VERSION="1.16.8"  # Specify the Cilium version

# Launch the instances
multipass launch --name $MASTER_NODE --cpus 2 --memory 2G --disk 10G
multipass launch --name $WORKER_NODE1 --cpus 2 --memory 2G --disk 10G
multipass launch --name $WORKER_NODE2 --cpus 2 --memory 2G --disk 10G

# Function to install containerd, kubeadm, kubelet and kubectl

base_node_setup() {
    local NODE=$1
    multipass exec $NODE -- bash -c "
    set -e

    # Load necessary kernel modules
    echo 'overlay' | sudo tee /etc/modules-load.d/k8s.conf
    echo 'br_netfilter' | sudo tee -a /etc/modules-load.d/k8s.conf

    sudo modprobe overlay
    sudo modprobe br_netfilter

    # Set sysctl parameters required by Kubernetes
    cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

    # Apply sysctl parameters
    sudo sysctl --system

    # Install containerd
    sudo apt-get update
    sudo apt-get install -y containerd

    # Create a default containerd configuration and modify it
    sudo mkdir -p /etc/containerd
    sudo containerd config default | sudo tee /etc/containerd/config.toml

    # Use systemd as the cgroup driver
    sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

    # Restart containerd to apply changes
    sudo systemctl restart containerd
    sudo systemctl enable containerd
    "
}

install_k8s_tools() {
    local NODE=$1
    multipass exec $NODE -- bash -c "
    set -e

    # Update package list
    sudo apt-get update -y

    # Install required packages
    sudo apt-get install -y apt-transport-https ca-certificates curl gpg software-properties-common jq

    # Add Kubernetes apt repository
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

    sudo mkdir -p /etc/apt/keyrings
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

    # Update package list again after adding the Kubernetes repository
    sudo apt-get update -y

    # Install Kubernetes components
    sudo apt-get install -y kubelet kubeadm kubectl

    # Prevent these packages from being automatically upgraded
    sudo apt-mark hold kubelet kubeadm kubectl

    # Create crictl configuration file
    cat <<EOF | sudo tee /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
EOF

    # Enable and start kubelet
    sudo systemctl enable --now kubelet

#    # Optionally, copy the admin.conf for kubectl access
#sudo cp /etc/kubernetes/admin.conf /home/ubuntu/
#    sudo chown ubuntu:ubuntu /home/ubuntu/admin.conf
#    chmod 600 /home/ubuntu/admin.conf
    "
}

initialize_kubernetes() {
    local MASTER_NODE=$1
    multipass exec $MASTER_NODE -- bash -c "
    # Initialize Kubernetes
    sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=\$(hostname -I | awk '{print $1}') --cri-socket=unix:///run/containerd/containerd.sock

    # Setup kubeconfig for the default user
    mkdir -p \$HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config
    sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config
    "
}

install_k8s_tools2() {
    local NODE=$1
    multipass exec $NODE -- bash -c "
    set -e

    # Update package list
    sudo apt-get update -y

    # Install required packages
    sudo apt-get install -y apt-transport-https ca-certificates curl gpg software-properties-common jq

    # Add Kubernetes apt repository
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

    sudo mkdir -p /etc/apt/keyrings
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

    # Update package list again after adding the Kubernetes repository
    sudo apt-get update -y

    # Install Kubernetes components
    sudo apt-get install -y kubelet kubeadm kubectl

    # Prevent these packages from being automatically upgraded
    sudo apt-mark hold kubelet kubeadm kubectl

    # Configure crictl to use containerd
    sudo crictl config runtime-endpoint=unix:///run/containerd/containerd.sock
    sudo crictl config image-endpoint=unix:///run/containerd/containerd.sock

    # Enable and start kubelet
    sudo systemctl enable --now kubelet

    # Optionally, copy the admin.conf for kubectl access
    sudo cp /etc/kubernetes/admin.conf /home/ubuntu/
    sudo chown ubuntu:ubuntu /home/ubuntu/admin.conf
    chmod 600 /home/ubuntu/admin.conf
    "
}


base_node_setup $MASTER_NODE
base_node_setup $WORKER_NODE1
base_node_setup $WORKER_NODE2
# Install Kubernetes tools on all nodes
install_k8s_tools $MASTER_NODE
install_k8s_tools $WORKER_NODE1
install_k8s_tools $WORKER_NODE2

# Initialize Kubernetes on the master node
multipass exec $MASTER_NODE -- bash -c "sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=$(multipass list | grep $MASTER_NODE | awk '{print $3}') --cri-socket=/run/containerd/containerd.sock"

# Setup kubeconfig on master
multipass exec $MASTER_NODE -- bash -c "mkdir -p \$HOME/.kube && sudo cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config && sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config"

# Get join command
JOIN_COMMAND=$(multipass exec $MASTER_NODE -- kubeadm token create --print-join-command)
#JOIN_COMMAND=$(multipass exec $MASTER_NODE -- kubeadm token create --print-join-command --cri-socket /run/containerd/containerd.sock)

# Join worker nodes to the cluster
multipass exec $WORKER_NODE1 -- bash -c "sudo $JOIN_COMMAND "
multipass exec $WORKER_NODE2 -- bash -c "sudo $JOIN_COMMAND "

# Install Helm on master node
multipass exec $MASTER_NODE -- bash -c "curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash"

# Add Cilium Helm repository and install Cilium
multipass exec $MASTER_NODE -- bash -c "helm repo add cilium https://helm.cilium.io/"
multipass exec $MASTER_NODE -- bash -c "helm repo update"
multipass exec $MASTER_NODE -- bash -c "helm install cilium cilium/cilium --version $CILIUM_VERSION --namespace kube-system --set kubeProxyReplacement=true --set k8sServiceHost=$(multipass list | grep $MASTER_NODE | awk '{print $3}') --set k8sServicePort=6443"

echo "Kubernetes cluster setup is complete. Control plane is running on $MASTER_NODE, with worker nodes $WORKER_NODE1 and $WORKER_NODE2."
