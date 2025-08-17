#!/bin/bash
set -e

# Script to set up IAM Roles for Service Accounts (IRSA) for the SQS Processor application
# This script assumes you have the AWS CLI installed and configured

# Variables - replace these with your own values
CLUSTER_NAME="your-eks-cluster-name"
AWS_REGION="us-west-2"
NAMESPACE="default"
SERVICE_ACCOUNT_NAME="sqs-processor-sa"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "Setting up IAM Roles for Service Accounts (IRSA) for the SQS Processor application..."

# Check if eksctl is installed
if ! command -v eksctl &> /dev/null; then
    echo "eksctl is not installed. Please install it first."
    exit 1
fi

# Check if the cluster exists
if ! aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION &> /dev/null; then
    echo "Cluster $CLUSTER_NAME does not exist in region $AWS_REGION."
    exit 1
fi

# Create an IAM policy for the application to access SQS
POLICY_NAME="SQSProcessorPolicy"
POLICY_ARN="arn:aws:iam::$AWS_ACCOUNT_ID:policy/$POLICY_NAME"

# Check if the policy already exists
if ! aws iam get-policy --policy-arn $POLICY_ARN &> /dev/null; then
    echo "Creating IAM policy $POLICY_NAME..."
    aws iam create-policy --policy-name $POLICY_NAME --policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "sqs:ReceiveMessage",
                    "sqs:DeleteMessage",
                    "sqs:GetQueueAttributes",
                    "sqs:GetQueueUrl",
                    "sqs:ListQueues",
                    "sqs:ListQueueTags",
                    "sqs:SendMessage",
                    "sqs:ChangeMessageVisibility"
                ],
                "Resource": "*"
            }
        ]
    }'
else
    echo "IAM policy $POLICY_NAME already exists."
fi

# Create an IAM role and service account for the application
echo "Creating IAM role and service account for the SQS Processor application..."
eksctl create iamserviceaccount \
    --name $SERVICE_ACCOUNT_NAME \
    --namespace $NAMESPACE \
    --cluster $CLUSTER_NAME \
    --region $AWS_REGION \
    --attach-policy-arn $POLICY_ARN \
    --approve \
    --override-existing-serviceaccounts

echo "IAM role and service account for the SQS Processor application have been created."
echo "Now you need to update your deployment to use the service account."
echo "Add the following to your deployment.yaml file under spec.template.spec:"
echo ""
echo "serviceAccountName: $SERVICE_ACCOUNT_NAME"
echo ""
echo "Then apply the updated deployment with:"
echo "kubectl apply -f kubernetes/keda-service/deployment.yaml"