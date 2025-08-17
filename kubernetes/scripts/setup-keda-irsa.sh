#!/bin/bash
set -e

# Script to set up IAM Roles for Service Accounts (IRSA) for KEDA
# This script assumes you have the AWS CLI installed and configured

# Variables - replace these with your own values
CLUSTER_NAME="your-eks-cluster-name"
AWS_REGION="us-west-2"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "Setting up IAM Roles for Service Accounts (IRSA) for KEDA..."

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

# Create an IAM policy for KEDA to access SQS
POLICY_NAME="KEDASQSPolicy"
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
                    "sqs:GetQueueAttributes",
                    "sqs:GetQueueUrl",
                    "sqs:ListQueues",
                    "sqs:ListQueueTags",
                    "sqs:ReceiveMessage"
                ],
                "Resource": "*"
            }
        ]
    }'
else
    echo "IAM policy $POLICY_NAME already exists."
fi

# Create an IAM role and service account for KEDA
echo "Creating IAM role and service account for KEDA..."
eksctl create iamserviceaccount \
    --name keda-operator \
    --namespace keda \
    --cluster $CLUSTER_NAME \
    --region $AWS_REGION \
    --attach-policy-arn $POLICY_ARN \
    --approve \
    --override-existing-serviceaccounts

echo "IAM role and service account for KEDA have been created."
echo "Now you need to update your KEDA installation to use the service account."
echo "If you're using Helm, you can update your values.yaml file to include:"
echo ""
echo "serviceAccount:"
echo "  create: false"
echo "  name: keda-operator"
echo ""
echo "Then update your KEDA installation with:"
echo "helm upgrade keda kedacore/keda --namespace keda -f values.yaml"