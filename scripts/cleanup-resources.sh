#!/bin/bash
set -e

# Script to delete/unroll all resources created by the SQS Processor project
# This includes:
# - KEDA installation
# - IAM roles and policies for KEDA and the application
# - EKS cluster
# - SQS queue

# Default values
CLUSTER_NAME="sandbox"
AWS_REGION="us-west-2"
STACK_NAME="sqs-processor-stack"
NAMESPACE="default"
APP_SERVICE_ACCOUNT_NAME="sqs-processor-sa"
KEDA_SERVICE_ACCOUNT_NAME="keda-operator"
KEDA_NAMESPACE="keda"
APP_POLICY_NAME="SQSProcessorPolicy"
KEDA_POLICY_NAME="KEDASQSPolicy"

# Resource flags (default: don't clean up any resources unless specified)
CLEAN_KEDA=false
CLEAN_IAM=false
CLEAN_EKS=false
CLEAN_SQS=false
CLEAN_ALL=false

# Function to display usage information
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --cluster-name NAME    EKS cluster name (default: $CLUSTER_NAME)"
    echo "  --region REGION        AWS region (default: $AWS_REGION)"
    echo "  --stack-name NAME      CloudFormation stack name for SQS queue (default: $STACK_NAME)"
    echo "  --clean-keda           Clean up KEDA installation"
    echo "  --clean-iam            Clean up IAM roles and policies"
    echo "  --clean-eks            Clean up EKS cluster"
    echo "  --clean-sqs            Clean up SQS queue (CloudFormation stack)"
    echo "  --clean-all            Clean up all resources"
    echo "  --help                 Display this help message"
    echo ""
    echo "If no resource flags are specified, no resources will be cleaned up."
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --stack-name)
            STACK_NAME="$2"
            shift 2
            ;;
        --clean-keda)
            CLEAN_KEDA=true
            shift
            ;;
        --clean-iam)
            CLEAN_IAM=true
            shift
            ;;
        --clean-eks)
            CLEAN_EKS=true
            shift
            ;;
        --clean-sqs)
            CLEAN_SQS=true
            shift
            ;;
        --clean-all)
            CLEAN_ALL=true
            CLEAN_KEDA=true
            CLEAN_IAM=true
            CLEAN_EKS=true
            CLEAN_SQS=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [ $? -ne 0 ]; then
    echo "Error: Failed to get AWS account ID. Make sure AWS CLI is configured correctly."
    exit 1
fi

# Function to check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Check if required commands exist
if ! command_exists aws; then
    echo "Error: AWS CLI is not installed. Please install it first."
    exit 1
fi

if ! command_exists kubectl; then
    echo "Error: kubectl is not installed. Please install it first."
    exit 1
fi

if ! command_exists helm; then
    echo "Error: Helm is not installed. Please install it first."
    exit 1
fi

if ! command_exists eksctl; then
    echo "Error: eksctl is not installed. Please install it first."
    exit 1
fi

# Function to confirm action
confirm() {
    read -p "$1 (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operation cancelled."
        exit 0
    fi
}

# Check if any resource flags are set
if [[ "$CLEAN_KEDA" == "false" && "$CLEAN_IAM" == "false" && "$CLEAN_EKS" == "false" && "$CLEAN_SQS" == "false" && "$CLEAN_ALL" == "false" ]]; then
    echo "No resources specified for cleanup. Use --clean-keda, --clean-iam, --clean-eks, --clean-sqs, or --clean-all to specify resources to clean up."
    echo "Run '$0 --help' for more information."
    exit 0
fi

# Main confirmation
echo "The following resources will be cleaned up:"
[[ "$CLEAN_KEDA" == "true" ]] && echo "- KEDA installation"
[[ "$CLEAN_IAM" == "true" ]] && echo "- IAM roles and policies"
[[ "$CLEAN_EKS" == "true" ]] && echo "- EKS cluster"
[[ "$CLEAN_SQS" == "true" ]] && echo "- SQS queue (CloudFormation stack)"

confirm "This action cannot be undone. Do you want to continue?"

echo "Starting cleanup process..."

# Step 1: Uninstall KEDA
if [[ "$CLEAN_KEDA" == "true" ]]; then
    echo "Step 1: Uninstalling KEDA..."
    if kubectl get namespace $KEDA_NAMESPACE &> /dev/null; then
        if helm list -n $KEDA_NAMESPACE | grep -q "keda"; then
            echo "Uninstalling KEDA Helm release..."
            helm uninstall keda -n $KEDA_NAMESPACE
            if [ $? -ne 0 ]; then
                echo "Warning: Failed to uninstall KEDA Helm release. Continuing with cleanup..."
            fi
        else
            echo "KEDA Helm release not found. Skipping uninstallation."
        fi
    else
        echo "KEDA namespace not found. Skipping KEDA uninstallation."
    fi
else
    echo "Step 1: Skipping KEDA uninstallation (not selected for cleanup)."
fi

# Step 2: Delete IAM service accounts and policies
if [[ "$CLEAN_IAM" == "true" ]]; then
    echo "Step 2: Deleting IAM service accounts and policies..."

    # Delete application service account
    echo "Deleting application service account..."
    if aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION &> /dev/null; then
        eksctl delete iamserviceaccount \
            --name $APP_SERVICE_ACCOUNT_NAME \
            --namespace $NAMESPACE \
            --cluster $CLUSTER_NAME \
            --region $AWS_REGION \
            --wait 2>/dev/null || echo "Application service account not found or already deleted."
    else
        echo "Cluster not found. Skipping application service account deletion."
    fi

    # Delete KEDA service account
    echo "Deleting KEDA service account..."
    if aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION &> /dev/null; then
        eksctl delete iamserviceaccount \
            --name $KEDA_SERVICE_ACCOUNT_NAME \
            --namespace $KEDA_NAMESPACE \
            --cluster $CLUSTER_NAME \
            --region $AWS_REGION \
            --wait 2>/dev/null || echo "KEDA service account not found or already deleted."
    else
        echo "Cluster not found. Skipping KEDA service account deletion."
    fi

    # Delete application IAM policy
    echo "Deleting application IAM policy..."
    APP_POLICY_ARN="arn:aws:iam::$AWS_ACCOUNT_ID:policy/$APP_POLICY_NAME"
    if aws iam get-policy --policy-arn $APP_POLICY_ARN &> /dev/null; then
        # First detach the policy from all entities
        for role in $(aws iam list-entities-for-policy --policy-arn $APP_POLICY_ARN --query 'PolicyRoles[*].RoleName' --output text); do
            aws iam detach-role-policy --role-name $role --policy-arn $APP_POLICY_ARN
        done

        # Then delete the policy
        aws iam delete-policy --policy-arn $APP_POLICY_ARN
        if [ $? -ne 0 ]; then
            echo "Warning: Failed to delete application IAM policy. You may need to delete it manually."
        fi
    else
        echo "Application IAM policy not found. Skipping deletion."
    fi

    # Delete KEDA IAM policy
    echo "Deleting KEDA IAM policy..."
    KEDA_POLICY_ARN="arn:aws:iam::$AWS_ACCOUNT_ID:policy/$KEDA_POLICY_NAME"
    if aws iam get-policy --policy-arn $KEDA_POLICY_ARN &> /dev/null; then
        # First detach the policy from all entities
        for role in $(aws iam list-entities-for-policy --policy-arn $KEDA_POLICY_ARN --query 'PolicyRoles[*].RoleName' --output text); do
            aws iam detach-role-policy --role-name $role --policy-arn $KEDA_POLICY_ARN
        done

        # Then delete the policy
        aws iam delete-policy --policy-arn $KEDA_POLICY_ARN
        if [ $? -ne 0 ]; then
            echo "Warning: Failed to delete KEDA IAM policy. You may need to delete it manually."
        fi
    else
        echo "KEDA IAM policy not found. Skipping deletion."
    fi
else
    echo "Step 2: Skipping IAM service accounts and policies cleanup (not selected for cleanup)."
fi

# Step 3: Delete EKS cluster
if [[ "$CLEAN_EKS" == "true" ]]; then
    echo "Step 3: Deleting EKS cluster..."
    if aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION &> /dev/null; then
        confirm "Are you sure you want to delete the EKS cluster '$CLUSTER_NAME'? This will delete all resources in the cluster."

        echo "Deleting EKS cluster $CLUSTER_NAME in region $AWS_REGION..."
        eksctl delete cluster --name=$CLUSTER_NAME --region=$AWS_REGION
        if [ $? -ne 0 ]; then
            echo "Error: Failed to delete EKS cluster. You may need to delete it manually."
        fi
    else
        echo "EKS cluster not found. Skipping deletion."
    fi
else
    echo "Step 3: Skipping EKS cluster cleanup (not selected for cleanup)."
fi

# Step 4: Delete SQS queue (CloudFormation stack)
if [[ "$CLEAN_SQS" == "true" ]]; then
    echo "Step 4: Deleting SQS queue (CloudFormation stack)..."
    if aws cloudformation describe-stacks --stack-name $STACK_NAME --region $AWS_REGION &> /dev/null; then
        confirm "Are you sure you want to delete the CloudFormation stack '$STACK_NAME' containing the SQS queue?"

        echo "Deleting CloudFormation stack $STACK_NAME in region $AWS_REGION..."
        aws cloudformation delete-stack --stack-name $STACK_NAME --region $AWS_REGION

        echo "Waiting for stack deletion to complete..."
        aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME --region $AWS_REGION

        if [ $? -ne 0 ]; then
            echo "Error: Failed to delete CloudFormation stack. You may need to delete it manually."
        else
            echo "CloudFormation stack deleted successfully."
        fi
    else
        echo "CloudFormation stack not found. Skipping deletion."
    fi
else
    echo "Step 4: Skipping SQS queue cleanup (not selected for cleanup)."
fi

echo "Cleanup process completed."
echo "Note: Some resources may still exist if they were not found or if errors occurred during deletion."
echo "Please check the AWS Management Console to ensure all resources have been properly deleted."
