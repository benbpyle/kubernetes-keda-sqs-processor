#!/bin/bash
set -e

# Script to install KEDA in a Kubernetes cluster using Helm

echo "Installing KEDA using Helm..."

# Add the KEDA Helm repository
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

# Create the keda namespace if it doesn't exist
kubectl create namespace keda --dry-run=client -o yaml | kubectl apply -f -

# Install KEDA using Helm
helm install keda kedacore/keda --namespace keda

echo "KEDA has been successfully installed in the 'keda' namespace."
echo "You can verify the installation with: kubectl get pods -n keda"