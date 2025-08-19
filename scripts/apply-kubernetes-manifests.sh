#!/bin/bash
set -e

# Script to apply Kubernetes manifests for the SQS Processor

echo "Applying Kubernetes manifests for SQS Processor..."

# Create the namespace if it doesn't exist
kubectl create namespace default --dry-run=client -o yaml | kubectl apply -f -

# Apply the ConfigMap
echo "Applying ConfigMap..."
kubectl apply -f kubernetes/keda-service/configmap.yaml

# Apply the Deployment
echo "Applying Deployment..."
kubectl apply -f kubernetes/keda-service/deployment.yaml

# Apply the ScaledObject
echo "Applying ScaledObject..."
kubectl apply -f kubernetes/keda-service/scaled-object.yaml

# Apply the TriggerAuthentication
echo "Applying TriggerAuthentication..."
kubectl apply -f kubernetes/keda-service/trigger-authentication.yaml

echo "All manifests applied successfully."
echo "You can check the status with: kubectl get pods"
echo "To view the logs: kubectl logs -l app=sqs-processor"
