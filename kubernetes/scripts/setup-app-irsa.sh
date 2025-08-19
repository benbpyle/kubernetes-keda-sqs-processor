#!/bin/bash
set -e

# Script to set up IAM Roles for Service Accounts (IRSA) for the SQS Processor application
# This script assumes you have the AWS CLI installed and configured

# Variables - replace these with your own values
CLUSTER_NAME="sandbox"
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

# Associate IAM OIDC provider with the cluster if not already associated
echo "Checking if IAM OIDC provider is associated with the cluster..."
if ! eksctl utils describe-stacks --region=$AWS_REGION --cluster=$CLUSTER_NAME | grep -q "IAMOIDCProvider"; then
    echo "No IAM OIDC provider found. Associating IAM OIDC provider with the cluster..."
    eksctl utils associate-iam-oidc-provider --region=$AWS_REGION --cluster=$CLUSTER_NAME --approve
else
    echo "IAM OIDC provider is already associated with the cluster."
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
                "Resource": "arn:aws:sqs:$AWS_REGION:$AWS_ACCOUNT_ID:sqs-processor-queue"
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

# Get the ARN of the created role
APP_ROLE_ARN=$(kubectl get serviceaccount $SERVICE_ACCOUNT_NAME -n $NAMESPACE -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')
if [ -z "$APP_ROLE_ARN" ]; then
    echo "❌ Failed to get the role ARN from the service account"
    exit 1
fi

echo "Application service account created with role ARN: $APP_ROLE_ARN"

# Check if KEDA operator service account exists and set up cross-role trust
if kubectl get serviceaccount keda-operator -n keda &> /dev/null; then
    echo ""
    echo "🔗 Setting up cross-role trust relationship with KEDA..."
    
    KEDA_ROLE_ARN=$(kubectl get serviceaccount keda-operator -n keda -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')
    if [ -z "$KEDA_ROLE_ARN" ]; then
        echo "⚠️  KEDA operator service account exists but doesn't have IRSA annotation."
        echo "Please run ./kubernetes/scripts/setup-keda-irsa.sh first"
    else
        # Extract role name from ARN
        APP_ROLE_NAME=$(echo $APP_ROLE_ARN | cut -d'/' -f2)
        
        # Get the OIDC issuer URL for the cluster
        OIDC_ISSUER=$(aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --query "cluster.identity.oidc.issuer" --output text)
        OIDC_HOST=$(echo $OIDC_ISSUER | sed 's|https://||')

        # Create a trust policy document that allows both OIDC (for app) and KEDA role to assume the app role
        TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::$AWS_ACCOUNT_ID:oidc-provider/$OIDC_HOST"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "$OIDC_HOST:sub": "system:serviceaccount:$NAMESPACE:$SERVICE_ACCOUNT_NAME",
          "$OIDC_HOST:aud": "sts.amazonaws.com"
        }
      }
    },
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "$KEDA_ROLE_ARN"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
        )

        # Update the trust policy of the app role
        echo "Updating trust policy to allow both OIDC and KEDA access..."
        aws iam update-assume-role-policy --role-name $APP_ROLE_NAME --policy-document "$TRUST_POLICY"
        
        echo "✅ Cross-role trust relationship configured!"
        echo "KEDA can now assume this application role for SQS metrics access."
    fi
else
    echo ""
    echo "⚠️  KEDA operator service account not found."
    echo "Cross-role trust will be set up when you run setup-keda-irsa.sh"
fi

echo ""
echo "✅ Application IRSA setup complete!"
echo ""
echo "📝 Next steps:"
echo "1. Verify your deployment uses the service account:"
echo "   Check that kubernetes/keda-service/deployment.yaml contains:"
echo "   serviceAccountName: $SERVICE_ACCOUNT_NAME"
echo ""
echo "2. Apply your Kubernetes manifests:"
echo "   kubectl apply -f kubernetes/keda-service/"
echo ""
echo "3. Verify the ScaledObject is working:"
echo "   kubectl get scaledobject sqs-processor-scaler -n default"
