#!/bin/bash
set -e

############################################
# Kubernetes Air-Gapped Node Setup Script
# Works for both Master & Worker nodes
############################################

echo "[Step 1] Setting Hostname"
sudo hostnamectl set-hostname k8-node

############################################
# Firewall Rules
############################################
echo "[Step 2] Configuring Firewall Rules"
sudo firewall-cmd --permanent --add-port=2379/tcp
sudo firewall-cmd --permanent --add-port=2380/tcp
sudo firewall-cmd --permanent --add-port=6443/tcp
sudo firewall-cmd --permanent --add-port=10248/tcp
sudo firewall-cmd --permanent --add-port=10250/tcp
sudo firewall-cmd --permanent --add-port=10257/tcp
sudo firewall-cmd --permanent --add-port=10259/tcp
sudo firewall-cmd --reload
sudo firewall-cmd --list-ports

############################################
# Disable SELinux & Swap, Configure Networking
############################################
echo "[Step 3] Disabling SELinux, Swap & Configuring Networking"
sudo swapoff -a
sudo setenforce 0 || true

# Kernel modules
sudo modprobe overlay
sudo modprobe br_netfilter

# Load modules permanently
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

# Configure sysctl
cat <<EOF | sudo tee -a /etc/sysctl.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sudo sysctl --system

# Disable SELinux permanently
sudo sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config

############################################
# Setup Containerd
############################################
echo "[Step 4] Installing Containerd"

cd /home/k8/air-gap-k8-setup/containerd_setup

tar xzvf containerd-2.0.1-linux-amd64.tar.gz

sudo cp bin/* /usr/local/bin
sudo cp bin/* /usr/bin
sudo cp runc /usr/local/bin
sudo cp runc /usr/bin
sudo cp containerd.service /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable --now containerd
sudo systemctl status containerd --no-pager

############################################
# Install Kubernetes Components
############################################
echo "[Step 5] Installing Kubernetes RPMs"

cd /home/k8/air-gap-k8-setup/kubernetes_rpms
sudo yum localinstall -y *.rpm --disablerepo="*" --skip-broken --allowerasing --best

echo "[Step 6] Checking Versions"
kubectl version --client
kubeadm version
kubelet --version

echo "✅ Setup complete. You can now proceed with kubeadm init (master)"

#!/bin/bash
set -e

############################################
# Kubernetes Master Node Setup Script
############################################

echo "[Step 7] Initializing Kubernetes Control Plane"
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --ignore-preflight-errors=all --v=5

echo "[Step 8] Setting up kubeconfig for kubectl"
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

echo "[Step 9] Waiting for Kubernetes components to stabilize (2 minutes)"
sleep 120

############################################
# Install Flannel CNI
############################################
echo "[Step 10] Importing Flannel images into containerd"
cd /home/k8/air-gap-k8-setup/flannel/images
for img in *.tar; do
    sudo ctr -n k8s.io images import "$img"
done

echo "[Step 11] Deploying Flannel CNI"
cd /home/k8/air-gap-k8-setup/flannel
kubectl apply -f kube-flannel.yml

echo "[Step 12] Cluster Status"
kubectl get nodes -o wide
kubectl get pods -n kube-system -o wide

echo "✅ Master node setup complete."
echo "👉 Copy the kubeadm join command output above and run it on your worker node."
