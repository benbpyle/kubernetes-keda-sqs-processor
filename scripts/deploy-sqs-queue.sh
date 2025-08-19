#!/bin/bash

# Script to deploy SQS queue using CloudFormation and display the queue ARN
# Usage: ./deploy-sqs-queue.sh [region]

# Set default region if not provided
REGION=${1:-us-west-2}
STACK_NAME="sqs-processor-stack"
TEMPLATE_FILE="./aws/sqs-queue.yaml"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI is not installed. Please install it first."
    exit 1
fi

echo "Deploying SQS queue in region: $REGION"

# Deploy CloudFormation stack
aws cloudformation deploy \
    --template-file $TEMPLATE_FILE \
    --stack-name $STACK_NAME \
    --region $REGION \
    --parameter-overrides QueueName=sqs-processor-queue \
    --capabilities CAPABILITY_IAM

# Check if deployment was successful
if [ $? -ne 0 ]; then
    echo "Error: Failed to deploy CloudFormation stack."
    exit 1
fi

echo "Stack deployment completed successfully."

# Get the SQS queue ARN from the stack outputs
QUEUE_ARN=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    --query "Stacks[0].Outputs[?OutputKey=='QueueARN'].OutputValue" \
    --output text)

if [ -z "$QUEUE_ARN" ]; then
    echo "Error: Failed to retrieve SQS queue ARN."
    exit 1
fi

echo "SQS Queue ARN: $QUEUE_ARN"