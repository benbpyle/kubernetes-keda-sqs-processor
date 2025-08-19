#!/bin/bash
set -e

# Script to configure Kubernetes manifests with AWS Account ID and other variables
# This script replaces placeholders in YAML files with actual values

# Variables - can be overridden by command line arguments or environment variables
CLUSTER_NAME="${1:-${CLUSTER_NAME:-sandbox}}"
AWS_REGION="${2:-${AWS_REGION:-us-west-2}}"
QUEUE_NAME="${3:-${QUEUE_NAME:-sqs-processor-queue}}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [CLUSTER_NAME] [AWS_REGION] [QUEUE_NAME]"
    echo ""
    echo "Configure Kubernetes manifests with AWS Account ID and other variables"
    echo ""
    echo "Arguments:"
    echo "  CLUSTER_NAME   EKS cluster name (default: sandbox)"
    echo "  AWS_REGION     AWS region (default: us-west-2)"
    echo "  QUEUE_NAME     SQS queue name (default: sqs-processor-queue)"
    echo ""
    echo "Environment Variables:"
    echo "  CLUSTER_NAME   Override default cluster name"
    echo "  AWS_REGION     Override default AWS region"
    echo "  QUEUE_NAME     Override default queue name"
    echo "  AWS_ACCOUNT_ID Override AWS account ID (auto-detected if not set)"
    echo ""
    echo "Examples:"
    echo "  # Use defaults"
    echo "  $0"
    echo ""
    echo "  # Specify custom values"
    echo "  $0 my-cluster us-east-1 my-queue"
    echo ""
    echo "  # Using environment variables"
    echo "  export CLUSTER_NAME=my-cluster"
    echo "  export AWS_REGION=us-east-1"
    echo "  $0"
}

# Check for help flag
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_usage
    exit 0
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Get AWS Account ID
print_info "Getting AWS Account ID..."
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text 2>/dev/null)}
if [[ -z "$AWS_ACCOUNT_ID" ]]; then
    print_error "Could not determine AWS Account ID. Please check your AWS credentials."
    exit 1
fi

print_success "AWS Account ID: $AWS_ACCOUNT_ID"

# Display configuration
echo ""
echo "==================== Configuration ===================="
print_info "Cluster Name: $CLUSTER_NAME"
print_info "AWS Region: $AWS_REGION"
print_info "AWS Account ID: $AWS_ACCOUNT_ID"
print_info "Queue Name: $QUEUE_NAME"
echo "========================================================"
echo ""

# Manifest files to configure
MANIFESTS=(
    "kubernetes/keda-service/configmap.yaml"
    "kubernetes/keda-service/scaled-object.yaml"
    "kubernetes/keda-values.yaml"
)

# Create backup directory if it doesn't exist
BACKUP_DIR="kubernetes/.backups"
if [[ ! -d "$BACKUP_DIR" ]]; then
    mkdir -p "$BACKUP_DIR"
    print_info "Created backup directory: $BACKUP_DIR"
fi

# Function to backup and configure a file
configure_manifest() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        print_warning "File not found: $file (skipping)"
        return
    fi
    
    # Create backup
    local backup_file="$BACKUP_DIR/$(basename "$file").backup.$(date +%Y%m%d-%H%M%S)"
    cp "$file" "$backup_file"
    print_info "Backed up $file to $backup_file"
    
    # Configure the file
    print_info "Configuring $file..."
    
    # Use sed to replace placeholders
    sed -i.tmp \
        -e "s/{AWS_ACCOUNT_ID}/$AWS_ACCOUNT_ID/g" \
        -e "s/{CLUSTER_NAME}/$CLUSTER_NAME/g" \
        -e "s/{AWS_REGION}/$AWS_REGION/g" \
        -e "s/{QUEUE_NAME}/$QUEUE_NAME/g" \
        "$file"
    
    # Remove the temporary file created by sed
    rm -f "${file}.tmp"
    
    print_success "Configured $file"
}

# Configure all manifest files
print_info "Configuring Kubernetes manifests..."
echo ""

for manifest in "${MANIFESTS[@]}"; do
    configure_manifest "$manifest"
done

echo ""
print_success "All manifests configured successfully!"
echo ""

print_info "📝 Next steps:"
echo "1. Review the configured files:"
for manifest in "${MANIFESTS[@]}"; do
    echo "   - $manifest"
done
echo ""
echo "2. Apply the manifests:"
echo "   kubectl apply -f kubernetes/keda-service/"
echo ""
echo "3. Verify the configuration:"
echo "   kubectl get configmap sqs-processor-config -o yaml"
echo "   kubectl get scaledobject sqs-processor-scaler -o yaml"
echo ""

print_info "💡 To restore original files, use the backups in $BACKUP_DIR"