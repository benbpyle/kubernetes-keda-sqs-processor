#!/bin/bash
set -e

# Script to install KEDA in a Kubernetes cluster using Helm

echo "Installing KEDA using Helm..."

# Add the KEDA Helm repository
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

# Create the keda namespace if it doesn't exist
kubectl create namespace keda --dry-run=client -o yaml | kubectl apply -f -

# Check if keda-values.yaml exists
#if [ -f "kubernetes/keda-values.yaml" ]; then
#    # Install KEDA using Helm with the values file
#    echo "Using keda-values.yaml to configure KEDA with IAM Roles for Service Accounts (IRSA)..."
#    helm install keda kedacore/keda --namespace keda -f kubernetes/keda-values.yaml
#else
    # Install KEDA using Helm with default settings
    echo "keda-values.yaml not found. Installing KEDA with default settings..."
    helm install keda kedacore/keda --namespace keda

    echo ""
    echo "Note: If you've set up IAM Roles for Service Accounts (IRSA) for KEDA using setup-keda-irsa.sh,"
    echo "you'll need to update KEDA to use the service account. You can do this with:"
    echo "chmod +x kubernetes/scripts/update-keda-irsa.sh"
    echo "./kubernetes/scripts/update-keda-irsa.sh"
    echo ""
    echo "Or manually with:"
    echo "helm upgrade keda kedacore/keda --namespace keda --set serviceAccount.create=false --set serviceAccount.name=keda-operator"
#fi

echo ""
echo "KEDA has been successfully installed in the 'keda' namespace."
echo "You can verify the installation with: kubectl get pods -n keda"
