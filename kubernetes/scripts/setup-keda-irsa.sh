#!/bin/bash
set -e

# Script to set up IAM Roles for Service Accounts (IRSA) for KEDA
# This script assumes you have the AWS CLI installed and configured

# Variables - replace these with your own values
CLUSTER_NAME="sandbox"
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
                "Resource": "arn:aws:sqs:$AWS_REGION:$AWS_ACCOUNT_ID:sqs-processor-queue"
            }
        ]
    }'
else
    echo "IAM policy $POLICY_NAME already exists."
fi

# Associate IAM OIDC provider with the cluster if not already associated
echo "Checking if IAM OIDC provider is associated with the cluster..."
if ! eksctl utils describe-stacks --region=$AWS_REGION --cluster=$CLUSTER_NAME | grep -q "IAMOIDCProvider"; then
    echo "No IAM OIDC provider found. Associating IAM OIDC provider with the cluster..."
    eksctl utils associate-iam-oidc-provider --region=$AWS_REGION --cluster=$CLUSTER_NAME --approve
else
    echo "IAM OIDC provider is already associated with the cluster."
fi

# Create an IAM role and service account for KEDA
echo "Creating IAM role and service account for KEDA..."

# First delete existing service account if it exists but doesn't have IRSA annotation
if kubectl get serviceaccount keda-operator -n keda &> /dev/null; then
    EXISTING_ROLE_ARN=$(kubectl get serviceaccount keda-operator -n keda -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || echo "")
    if [ -z "$EXISTING_ROLE_ARN" ]; then
        echo "Deleting existing keda-operator service account without IRSA annotation..."
        kubectl delete serviceaccount keda-operator -n keda
    fi
fi

eksctl create iamserviceaccount \
    --name keda-operator \
    --namespace keda \
    --cluster $CLUSTER_NAME \
    --region $AWS_REGION \
    --attach-policy-arn $POLICY_ARN \
    --approve \
    --override-existing-serviceaccounts

echo "IAM role and service account for KEDA have been created."

# Verify the service account was created with the annotation
KEDA_ROLE_ARN=$(kubectl get serviceaccount keda-operator -n keda -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || echo "")
if [ -z "$KEDA_ROLE_ARN" ]; then
    echo "ERROR: Failed to create keda-operator service account with IRSA annotation"
    echo "This might be due to an existing IAM role. Please check and manually delete if needed:"
    echo "eksctl get iamserviceaccount --cluster $CLUSTER_NAME --region $AWS_REGION"
    exit 1
fi

echo "KEDA operator service account created with role ARN: $KEDA_ROLE_ARN"

# Check if the application service account exists and set up cross-role trust
if kubectl get serviceaccount sqs-processor-sa -n default &> /dev/null; then
    echo "Setting up cross-role trust relationship between KEDA and application service accounts..."

    # Get the ARN of the pod's IAM role
    POD_ROLE_ARN=$(kubectl get serviceaccount sqs-processor-sa -n default -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')
    if [ -z "$POD_ROLE_ARN" ]; then
        echo "The sqs-processor-sa service account does not have the eks.amazonaws.com/role-arn annotation."
        echo "Please run kubernetes/scripts/setup-app-irsa.sh first to create the application service account with IRSA."
    else
        # Extract the role name from the ARN
        POD_ROLE_NAME=$(echo $POD_ROLE_ARN | cut -d'/' -f2)

        echo "KEDA operator role ARN: $KEDA_ROLE_ARN"
        echo "Application role ARN: $POD_ROLE_ARN"

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
          "$OIDC_HOST:sub": "system:serviceaccount:default:sqs-processor-sa",
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

        # Update the trust policy of the pod's role
        echo "Updating the trust policy of the application role to allow both OIDC and KEDA access..."
        aws iam update-assume-role-policy --role-name $POD_ROLE_NAME --policy-document "$TRUST_POLICY"

        echo "✅ Cross-role trust relationship configured successfully!"
        echo "KEDA can now assume the application role for SQS metrics access."
        echo ""
        echo "You can verify the trust policy with:"
        echo "aws iam get-role --role-name $POD_ROLE_NAME"
    fi
else
    echo "⚠️  The sqs-processor-sa service account does not exist."
    echo "The cross-role trust relationship will be set up when you run setup-app-irsa.sh"
fi

echo ""
echo "🔧 Updating KEDA to use the IRSA service account..."

# Check if helm is installed
if ! command -v helm &> /dev/null; then
    echo "❌ Helm is not installed. Please install Helm and then run:"
    echo "helm upgrade keda kedacore/keda --namespace keda --set serviceAccount.create=false --set serviceAccount.name=keda-operator"
    exit 1
fi

# Update KEDA to use the service account
echo "Updating KEDA deployment to use keda-operator service account..."
helm upgrade keda kedacore/keda --namespace keda --set serviceAccount.create=false --set serviceAccount.name=keda-operator

if [ $? -eq 0 ]; then
    echo "✅ KEDA has been updated to use the IRSA service account."
    
    # Force restart KEDA operator to fix authentication issues
    echo "Restarting KEDA operator to apply service account changes..."
    kubectl rollout restart deployment keda-operator -n keda
    
    # Wait for KEDA operator to restart
    echo "Waiting for KEDA operator to restart..."
    kubectl rollout status deployment keda-operator -n keda --timeout=300s
    
    if [ $? -eq 0 ]; then
        echo "✅ KEDA operator is ready and using IRSA!"
        
        # Verify the operator is actually working
        echo "Verifying KEDA operator functionality..."
        sleep 10
        kubectl logs deployment/keda-operator -n keda --tail=5 | grep -q "Starting.*workers\|grpc_server"
        
        if [ $? -eq 0 ]; then
            echo "✅ KEDA operator is functioning correctly!"
        else
            echo "⚠️  KEDA operator may have issues. Check logs:"
            echo "kubectl logs deployment/keda-operator -n keda"
        fi
    else
        echo "❌ KEDA operator restart timed out. Check the deployment status:"
        echo "kubectl get pods -n keda"
        echo "kubectl logs deployment/keda-operator -n keda"
    fi
else
    echo "❌ Failed to update KEDA. You can try manually with:"
    echo "helm upgrade keda kedacore/keda --namespace keda --set serviceAccount.create=false --set serviceAccount.name=keda-operator"
    echo "kubectl rollout restart deployment keda-operator -n keda"
fi

echo ""
echo "✅ KEDA IRSA setup complete!"
echo "Next: Run ./kubernetes/scripts/setup-app-irsa.sh to set up the application IRSA"
