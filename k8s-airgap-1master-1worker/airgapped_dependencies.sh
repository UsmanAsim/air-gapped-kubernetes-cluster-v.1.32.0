#!/bin/bash

USER=$(whoami)

# Create necessary directories
mkdir -p /home/${USER}/air-gap-k8-setup/kubernetes_rpms
mkdir -p /home/${USER}/air-gap-k8-setup/containerd_setup
mkdir -p /home/${USER}/air-gap-k8-setup/kubernetes_images
mkdir -p /home/${USER}/air-gap-k8-setup/flannel/images

# Download Kubernetes RPMs

cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.32/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.32/rpm/repodata/repomd.xml.key
EOF

sudo yum install -y yum-utils
sudo yum install -y epel-release


# Download Kubernetes RPMs
cd /home/${USER}/air-gap-k8-setup/kubernetes_rpms/
sudo yumdownloader --archlist=x86_64 --downloaddir=/home/${USER}/air-gap-k8-setup/kubernetes_rpms kubeadm kubectl kubelet kubernetes-cni cri-tools conntrack-tools
sudo yumdownloader --archlist=x86_64 --resolve --destdir=/home/${USER}/air-gap-k8-setup/kubernetes_rpms glibc-common iproute iptables-libs systemd-libs

# Download Docker RPMs
cd /home/${USER}/air-gap-k8-setup/docker_rpms/
sudo yumdownloader --archlist=x86_64 --downloaddir=/home/${USER}/air-gap-k8-setup/docker_rpms docker-ce docker-ce-cli containerd.io
sudo yumdownloader --archlist=x86_64 --resolve --destdir=/home/${USER}/air-gap-k8-setup/docker_rpms container-selinux libseccomp systemd iptables libcgroup shadow-utils tar xz


# List dependencies for Kubernetes components
repoquery --requires --resolve kubeadm
repoquery --requires --resolve kubectl
repoquery --requires --resolve kubelet
repoquery --requires --resolve kubernetes-cni
repoquery --requires --resolve cri-tools


# Installing Kubernetes components
cd /home/${USER}/air-gap-k8-setup/kubernetes_rpms
sudo yum localinstall -y *.rpm --disablerepo="*" --skip-broken

# Document link: https://github.com/containerd/containerd/blob/main/docs/getting-started.md
# link: https://github.com/containerd/containerd/releases
#reference document link: https://unix.stackexchange.com/questions/542343/docker-service-how-to-edit-systemd-service-file

# Containerd and Docker setup
cd /home/${USER}/air-gap-k8-setup/containerd_setup/
wget https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
wget https://github.com/containerd/containerd/releases/download/v2.0.1/containerd-2.0.1-linux-amd64.tar.gz

tar xzvf containerd-2.0.1-linux-amd64.tar.gz
cp bin/* /usr/local/bin
cp bin/* /usr/bin
cp -r containerd.service /etc/systemd/system/

sudo systemctl restart containerd
sudo systemctl status containerd &  # Run in the background to prevent script termination
sudo systemctl enable containerd

# Docker setup
cd /home/${USER}/air-gap-k8-setup/docker_setup/
wget https://download.docker.com/linux/static/stable/x86_64/docker-27.4.1.tgz

tar xzvf docker-27.4.1.tgz

cd /home/${USER}/air-gap-k8-setup/docker_setup/
cp docker/docker* /usr/local/bin
cp docker/runc* /usr/local/bin
cp docker/docker* /usr/bin
cp docker/runc* /usr/bin

SERVICE_PATH="/etc/systemd/system/docker.service"

cat <<EOF | sudo tee $SERVICE_PATH > /dev/null
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network.target

[Service]
Type=notify
ExecStart=/usr/local/bin/dockerd
ExecReload=/bin/kill -s HUP \$MAINPID
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity
TimeoutStartSec=0
Restart=always
RestartSec=2
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start Docker
sudo systemctl daemon-reload
sudo systemctl enable --now docker
systemctl enable docker.service
sudo systemctl status docker &  # Run in the background to prevent script termination

# Starting the kubelet
sudo systemctl restart kubelet
sudo systemctl status kubelet &  # Run in the background to prevent script termination
sudo systemctl enable kubelet.service


# Pull Kubernetes images using kubeadm for version 1.32.0
kubeadm config images list --kubernetes-version v1.32.0

# Pull Kubernetes images and save as tar
cd /home/${USER}/air-gap-k8-setup/kubernetes_images/
ctr image pull registry.k8s.io/kube-apiserver:v1.32.0
ctr image export /home/${USER}/air-gap-k8-setup/kubernetes_images/kube-apiserver-v1.32.0.tar registry.k8s.io/kube-apiserver:v1.32.0

ctr image pull registry.k8s.io/kube-controller-manager:v1.32.0
ctr image export /home/${USER}/air-gap-k8-setup/kubernetes_images/kube-controller-manager-v1.32.0.tar registry.k8s.io/kube-controller-manager:v1.32.0

ctr image pull registry.k8s.io/kube-scheduler:v1.32.0
ctr image export /home/${USER}/air-gap-k8-setup/kubernetes_images/kube-scheduler-v1.32.0.tar registry.k8s.io/kube-scheduler:v1.32.0

ctr image pull registry.k8s.io/kube-proxy:v1.32.0
ctr image export /home/${USER}/air-gap-k8-setup/kubernetes_images/kube-proxy-v1.32.0.tar registry.k8s.io/kube-proxy:v1.32.0

ctr image pull registry.k8s.io/coredns/coredns:v1.11.3
ctr image export /home/${USER}/air-gap-k8-setup/kubernetes_images/coredns-v1.11.3.tar registry.k8s.io/coredns/coredns:v1.11.3

ctr image pull registry.k8s.io/pause:3.10
ctr image export /home/${USER}/air-gap-k8-setup/kubernetes_images/pause-3.10.tar registry.k8s.io/pause:3.10

ctr image pull registry.k8s.io/etcd:3.5.16-0
ctr image export /home/${USER}/air-gap-k8-setup/kubernetes_images/etcd-3.5.16-0.tar registry.k8s.io/etcd:3.5.16-0

# Download flannel YAML and images
cd /home/${USER}/air-gap-k8-setup/flannel/
wget https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml

# Pull flannel images and save as tar
ctr image pull docker.io/flannel/flannel-cni-plugin:v1.6.0-flannel1
ctr image export /home/${USER}/air-gap-k8-setup/flannel/images/flannel-cni-plugin-v1.6.0-flannel1.tar docker.io/flannel/flannel-cni-plugin:v1.6.0-flannel1

ctr image pull docker.io/flannel/flannel:v0.26.2
ctr image export /home/${USER}/air-gap-k8-setup/flannel/images/flannel-v0.26.2.tar docker.io/flannel/flannel:v0.26.2