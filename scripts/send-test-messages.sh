#!/bin/bash
set -e

# Script to send test messages to SQS queue for testing KEDA auto-scaling
# This script sends 10 JSON messages with auto-incrementing message numbers

# Default values - can be overridden by command line arguments or environment variables
DEFAULT_REGION="us-west-2"
DEFAULT_QUEUE_NAME="sqs-processor-queue"
DEFAULT_MESSAGE_COUNT=10

# Get AWS Account ID dynamically
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")}

# Construct default queue URL using account ID
DEFAULT_QUEUE_URL="https://sqs.${DEFAULT_REGION}.amazonaws.com/${AWS_ACCOUNT_ID}/${DEFAULT_QUEUE_NAME}"

# Configuration
QUEUE_URL="${1:-${SQS_QUEUE_URL:-$DEFAULT_QUEUE_URL}}"
AWS_REGION="${2:-${AWS_REGION:-$DEFAULT_REGION}}"
MESSAGE_COUNT="${3:-${MESSAGE_COUNT:-$DEFAULT_MESSAGE_COUNT}}"

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
    echo "Usage: $0 [QUEUE_URL] [AWS_REGION] [MESSAGE_COUNT]"
    echo ""
    echo "Send test messages to an SQS queue for testing KEDA auto-scaling"
    echo ""
    echo "Arguments:"
    echo "  QUEUE_URL      SQS queue URL (default: https://sqs.${DEFAULT_REGION}.amazonaws.com/{ACCOUNT_ID}/${DEFAULT_QUEUE_NAME})"
    echo "  AWS_REGION     AWS region (default: $DEFAULT_REGION)"
    echo "  MESSAGE_COUNT  Number of messages to send (default: $DEFAULT_MESSAGE_COUNT)"
    echo ""
    echo "Environment Variables:"
    echo "  SQS_QUEUE_URL  Override default queue URL"
    echo "  AWS_REGION     Override default AWS region"
    echo "  MESSAGE_COUNT  Override default message count"
    echo ""
    echo "Examples:"
    echo "  # Send 10 messages to default queue"
    echo "  $0"
    echo ""
    echo "  # Send messages to specific queue"
    echo "  $0 https://sqs.us-east-1.amazonaws.com/123456789012/my-queue"
    echo ""
    echo "  # Send 20 messages to specific queue and region"
    echo "  $0 https://sqs.us-east-1.amazonaws.com/123456789012/my-queue us-east-1 20"
    echo ""
    echo "  # Using environment variables"
    echo "  export SQS_QUEUE_URL=https://sqs.us-east-1.amazonaws.com/123456789012/my-queue"
    echo "  export MESSAGE_COUNT=5"
    echo "  $0"
}

# Check for help flag
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_usage
    exit 0
fi

# Validate inputs
if [[ -z "$QUEUE_URL" ]]; then
    print_error "Queue URL is required"
    show_usage
    exit 1
fi

if [[ ! "$MESSAGE_COUNT" =~ ^[0-9]+$ ]] || [[ "$MESSAGE_COUNT" -le 0 ]]; then
    print_error "Message count must be a positive integer"
    exit 1
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Verify AWS credentials and get account ID if not already set
print_info "Verifying AWS credentials..."
if ! aws sts get-caller-identity --region "$AWS_REGION" &> /dev/null; then
    print_error "AWS credentials not configured or invalid"
    print_info "Please configure AWS credentials using 'aws configure' or environment variables"
    exit 1
fi

# Ensure we have the AWS Account ID
if [[ -z "$AWS_ACCOUNT_ID" ]]; then
    print_info "Getting AWS Account ID..."
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    if [[ -z "$AWS_ACCOUNT_ID" ]]; then
        print_error "Could not determine AWS Account ID"
        exit 1
    fi
    # Reconstruct the default queue URL with the account ID
    DEFAULT_QUEUE_URL="https://sqs.${DEFAULT_REGION}.amazonaws.com/${AWS_ACCOUNT_ID}/${DEFAULT_QUEUE_NAME}"
    if [[ "$QUEUE_URL" == "https://sqs.${DEFAULT_REGION}.amazonaws.com//${DEFAULT_QUEUE_NAME}" ]]; then
        QUEUE_URL="$DEFAULT_QUEUE_URL"
    fi
fi

# Display configuration
echo "==================== Configuration ===================="
print_info "Queue URL: $QUEUE_URL"
print_info "AWS Region: $AWS_REGION"
print_info "Message Count: $MESSAGE_COUNT"
echo "========================================================"
echo ""

# Verify queue exists
print_info "Verifying SQS queue exists..."
if ! aws sqs get-queue-attributes --queue-url "$QUEUE_URL" --region "$AWS_REGION" &> /dev/null; then
    print_error "Failed to access SQS queue: $QUEUE_URL"
    print_info "Please verify the queue URL and your permissions"
    exit 1
fi
print_success "Queue verified successfully"

# Send messages
echo ""
print_info "Sending $MESSAGE_COUNT messages to SQS queue..."
echo ""

successful_sends=0
failed_sends=0

for i in $(seq 1 $MESSAGE_COUNT); do
    # Create JSON message with auto-incrementing messageNumber
    message_body="{\"messageNumber\":\"$i\"}"
    
    print_info "Sending message $i/$MESSAGE_COUNT: $message_body"
    
    # Send message to SQS
    if aws sqs send-message \
        --queue-url "$QUEUE_URL" \
        --message-body "$message_body" \
        --region "$AWS_REGION" \
        --output text \
        --query 'MessageId' > /dev/null; then
        
        print_success "Message $i sent successfully"
        ((successful_sends++))
    else
        print_error "Failed to send message $i"
        ((failed_sends++))
    fi
done

echo ""
echo "==================== Summary ===================="
print_success "Successfully sent: $successful_sends messages"
if [[ $failed_sends -gt 0 ]]; then
    print_error "Failed to send: $failed_sends messages"
fi
print_info "Total messages processed: $MESSAGE_COUNT"
echo "=================================================="

# Check queue attributes after sending
echo ""
print_info "Checking queue status..."
queue_attributes=$(aws sqs get-queue-attributes \
    --queue-url "$QUEUE_URL" \
    --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible \
    --region "$AWS_REGION" \
    --output json 2>/dev/null || echo '{"Attributes":{"ApproximateNumberOfMessages":"N/A","ApproximateNumberOfMessagesNotVisible":"N/A"}}')

visible_messages=$(echo "$queue_attributes" | jq -r '.Attributes.ApproximateNumberOfMessages // "N/A"')
invisible_messages=$(echo "$queue_attributes" | jq -r '.Attributes.ApproximateNumberOfMessagesNotVisible // "N/A"')

print_info "Messages visible in queue: $visible_messages"
print_info "Messages being processed: $invisible_messages"

if [[ $failed_sends -eq 0 ]]; then
    print_success "All messages sent successfully!"
    echo ""
    print_info "💡 Tips for testing KEDA auto-scaling:"
    echo "   • Monitor your deployment: kubectl get pods -w"
    echo "   • Check ScaledObject status: kubectl get scaledobject -A"
    echo "   • View KEDA logs: kubectl logs deployment/keda-operator -n keda -f"
    echo "   • Watch HPA status: kubectl get hpa -w"
    exit 0
else
    print_error "Some messages failed to send. Please check your AWS permissions and queue configuration."
    exit 1
fi