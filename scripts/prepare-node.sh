#!/usr/bin/env bash
set -euo pipefail

echo "==> Starting Kubernetes node preparation on $(hostname)"

echo "==> Updating apt package index"
sudo apt-get update -y

echo "==> Disabling swap now"
sudo swapoff -a || true

echo "==> Disabling swap permanently"

sudo cp /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d%H%M%S)" || true

sudo sed -i '/ swap / s/^/# DISABLED_FOR_KUBERNETES /' /etc/fstab || true
sudo sed -i '/swapfile/ s/^/# DISABLED_FOR_KUBERNETES /' /etc/fstab || true
sudo sed -i '/\/swap.img/ s/^/# DISABLED_FOR_KUBERNETES /' /etc/fstab || true

sudo systemctl mask swap.target || true

echo "==> Swap status"
free -h

echo "==> Loading Kubernetes kernel modules"

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf >/dev/null
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

echo "==> Applying Kubernetes networking sysctl settings"

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf >/dev/null
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system >/dev/null

echo "==> Installing containerd and prerequisites"

sudo apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  apt-transport-https \
  containerd

echo "==> Configuring containerd with systemd cgroup driver"

sudo mkdir -p /etc/containerd

containerd config default | sudo tee /etc/containerd/config.toml >/dev/null

sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

echo "==> Restarting and enabling containerd"

sudo systemctl restart containerd
sudo systemctl enable containerd >/dev/null

echo "==> Adding Kubernetes v1.36 apt key"

sudo mkdir -p -m 755 /etc/apt/keyrings

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key \
  | sudo gpg --batch --yes --dearmor \
  -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "==> Adding Kubernetes v1.36 apt repository"

cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /
EOF

echo "==> Installing kubelet kubeadm kubectl"

sudo apt-get update -y

sudo apt-get install -y \
  kubelet \
  kubeadm \
  kubectl

echo "==> Holding Kubernetes packages"

sudo apt-mark hold kubelet kubeadm kubectl

echo "==> Enabling kubelet"

sudo systemctl enable kubelet >/dev/null

echo "==> Verifying versions"

containerd --version
kubeadm version
kubectl version --client
hostname

echo "==> Node role"

cat /etc/kl-node-role || true

echo "==> Node preparation complete"