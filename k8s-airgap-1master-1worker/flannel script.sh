############################################
# Install Flannel CNI (only run on Master node)
############################################
echo "[Step 1] Importing Flannel images into containerd"
cd /home/k8/air-gap-k8-setup/flannel/images
for img in *.tar; do
    sudo ctr -n k8s.io images import "$img"
done

echo "[Step 2] Deploying Flannel CNI"
cd /home/k8/air-gap-k8-setup/flannel
kubectl apply -f kube-flannel.yml

echo "[Step 3] Cluster Status"
kubectl get nodes -o wide
kubectl get pods -n kube-system -o wide

echo "✅ Master node setup complete."
echo "👉 Copy the kubeadm join command output above and run it on your worker node."