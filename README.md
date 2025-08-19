# SQS Processor

A Rust application that polls AWS SQS queues and processes messages. It's designed to run in a Kubernetes environment with KEDA for auto-scaling based on queue length.

## Quick Start

To set up the complete system from scratch:

```bash
# 1. Create EKS cluster
eksctl create cluster -f kubernetes/cluster/cluster-config.yaml

# 2. Create SQS queue
./scripts/deploy-sqs-queue.sh us-west-2

# 3. Install KEDA
./kubernetes/scripts/install-keda.sh

# 4. Set up IRSA for KEDA (edit script with your queue ARN first)
./kubernetes/scripts/setup-keda-irsa.sh

# 5. Set up IRSA for application (edit script with your queue ARN first)
./kubernetes/scripts/setup-app-irsa.sh

# 6. Configure manifests with your AWS account ID and settings
./scripts/configure-manifests.sh

# 7. Deploy the application
kubectl apply -f kubernetes/keda-service/

# 8. Verify auto-scaling is working
kubectl get scaledobject sqs-processor-scaler -n default

# 9. Test auto-scaling with sample messages
./scripts/send-test-messages.sh
```

## Features

- Long polling of AWS SQS queues
- Health check endpoints for Kubernetes liveness and readiness probes
- Graceful shutdown on SIGTERM
- Configurable logging
- Kubernetes deployment with KEDA auto-scaling
- IRSA (IAM Roles for Service Accounts) support

## Prerequisites

- Rust 1.80 or later
- Docker
- AWS account
- AWS CLI configured
- eksctl installed (for cluster creation)

## Creating an SQS Queue

This project includes a CloudFormation template for creating an AWS SQS standard queue. The template is located at `aws/sqs-queue.yaml`.

### Using the CloudFormation Template Directly

```bash
aws cloudformation deploy \
  --template-file aws/sqs-queue.yaml \
  --stack-name sqs-processor-stack \
  --region us-east-1 \
  --parameter-overrides QueueName=sqs-processor-queue
```

### Using the Deployment Script

A convenience script is provided to deploy the CloudFormation stack and display the ARN of the created queue:

```bash
# Make the script executable
chmod +x scripts/deploy-sqs-queue.sh

# Run the script with default region (us-east-1)
./scripts/deploy-sqs-queue.sh

# Or specify a different region
./scripts/deploy-sqs-queue.sh us-west-2
```

The script will:
1. Deploy the CloudFormation stack with the SQS queue
2. Wait for the stack creation to complete
3. Display the ARN of the created SQS queue

You can use this ARN in your application configuration and KEDA ScaledObject.

## Creating an EKS Cluster

This project includes a configuration file for creating an Amazon EKS cluster using eksctl. The configuration file is located at `kubernetes/cluster/cluster-config.yaml`.

```bash
# Create the EKS cluster using the provided configuration
eksctl create cluster -f kubernetes/cluster/cluster-config.yaml
```

This will create an EKS cluster with the following specifications:
- Cluster name: sandbox
- Region: us-west-2
- Node type: m6g.large (ARM-based instances)
- Node count: 2

You can modify the configuration file to customize the cluster according to your requirements.

### Verifying the Cluster

After the cluster is created, you can verify it with:

```bash
# Configure kubectl to use the new cluster
aws eks update-kubeconfig --name sandbox --region us-west-2

# Verify the nodes are running
kubectl get nodes
```

## Installing KEDA

This project uses KEDA (Kubernetes Event-driven Autoscaling) to automatically scale the application based on the SQS queue length. If KEDA is not installed in your Kubernetes cluster, you can use the provided scripts to install it.

### Using Helm

The simplest way to install KEDA is using Helm:

```bash
# Make the script executable
chmod +x kubernetes/scripts/install-keda.sh

# Run the installation script
./kubernetes/scripts/install-keda.sh
```

This script will:
1. Add the KEDA Helm repository
2. Create the keda namespace
3. Install KEDA using Helm

### Setting up IAM Roles for Service Accounts (IRSA)

For KEDA to properly auto-scale based on SQS queue metrics, you need to set up IRSA for both KEDA and your application. **Run these scripts in order:**

#### Step 1: Set up KEDA IRSA

```bash
# Make the script executable
chmod +x kubernetes/scripts/setup-keda-irsa.sh

# Edit the script to set your cluster name, region, and SQS queue ARN
vi kubernetes/scripts/setup-keda-irsa.sh

# Run the setup script
./kubernetes/scripts/setup-keda-irsa.sh
```

This script will:
1. Create an IAM policy for KEDA to access SQS
2. Create an IAM role and service account for KEDA with IRSA
3. Automatically update KEDA to use the service account
4. Set up cross-role trust if the application service account exists

#### Step 2: Set up Application IRSA

```bash
# Make the script executable
chmod +x kubernetes/scripts/setup-app-irsa.sh

# Edit the script to set your cluster name, region, SQS queue ARN, and other parameters
vi kubernetes/scripts/setup-app-irsa.sh

# Run the setup script
./kubernetes/scripts/setup-app-irsa.sh
```

This script will:
1. Create an IAM policy for the application to access SQS
2. Create an IAM role and service account for the application
3. Set up cross-role trust relationship with KEDA (if KEDA IRSA exists)
4. Provide next steps for deployment

> **Important**: Both scripts grant permissions for a specific SQS queue ARN. Make sure to update the queue ARN in both scripts to match your SQS queue.

> **Note**: The scripts automatically handle the cross-role trust relationship that allows KEDA to assume the application's role when using `identityOwner: "pod"` in the ScaledObject configuration.

## Configuration Management

### Automatic Configuration

The project includes a script to automatically configure your Kubernetes manifests with the correct AWS Account ID and other settings:

```bash
# Configure with defaults (sandbox cluster, us-west-2 region)
./scripts/configure-manifests.sh

# Configure with custom settings
./scripts/configure-manifests.sh my-cluster us-east-1 my-queue-name

# Using environment variables
export CLUSTER_NAME=my-cluster
export AWS_REGION=us-east-1
export QUEUE_NAME=my-queue
./scripts/configure-manifests.sh
```

### What Gets Configured

The script updates the following files:
- `kubernetes/keda-service/configmap.yaml` - Application configuration
- `kubernetes/keda-service/scaled-object.yaml` - KEDA scaling configuration  
- `kubernetes/keda-values.yaml` - KEDA Helm values (commented examples)

### Manual Configuration

If you prefer to configure manually, update these placeholders in the YAML files:
- `{AWS_ACCOUNT_ID}` - Your AWS account ID
- `{CLUSTER_NAME}` - Your EKS cluster name
- `{AWS_REGION}` - Your AWS region
- `{QUEUE_NAME}` - Your SQS queue name

## Building

### Local Build

```bash
cargo build --release
```

### Docker Build

```bash
docker build -t sqs-processor:latest .
```

## Configuration

The application uses default configuration values, but in a real-world scenario, you would configure it using environment variables or a configuration file.

Key configuration options:

- `SQS_QUEUE_URL`: The URL of the SQS queue to poll
- `SQS_MAX_MESSAGES`: Maximum number of messages to receive in one batch (default: 10)
- `SQS_WAIT_TIME_SECONDS`: Wait time in seconds for long polling (default: 20)
- `SQS_VISIBILITY_TIMEOUT`: Visibility timeout in seconds (default: 30)
- `HEALTH_HOST`: Host to bind the health check server to (default: 0.0.0.0)
- `HEALTH_PORT`: Port to bind the health check server to (default: 8080)
- `RUST_LOG`: Log level (default: info)

## Running

### Local Run

```bash
cargo run --release
```

### Docker Run

```bash
docker run -p 8080:8080 \
  -e AWS_REGION=us-east-1 \
  -e SQS_QUEUE_URL=https://sqs.us-east-1.amazonaws.com/123456789012/my-queue \
  -e RUST_LOG=info \
  sqs-processor:latest
```

## Kubernetes Deployment

Follow these steps in order to deploy the SQS processor with KEDA auto-scaling:

### Prerequisites
1. Create an EKS cluster (see [Creating an EKS Cluster](#creating-an-eks-cluster))
2. Create an SQS queue (see [Creating an SQS Queue](#creating-an-sqs-queue))
3. Install KEDA (see [Installing KEDA](#installing-keda))

### Setup IRSA (Required for auto-scaling)
4. Set up KEDA IRSA: `./kubernetes/scripts/setup-keda-irsa.sh`
5. Set up Application IRSA: `./kubernetes/scripts/setup-app-irsa.sh`

### Configure and Deploy
6. Configure manifests with your AWS Account ID and settings:
   ```bash
   ./scripts/configure-manifests.sh
   ```
   This script automatically:
   - Detects your AWS Account ID
   - Updates queue URLs in configuration files
   - Creates backups of original files

7. If using a custom image, update the image reference in `kubernetes/keda-service/deployment.yaml`
8. Apply the Kubernetes manifests:

   Option 1: Apply each manifest individually:
   ```bash
   kubectl apply -f kubernetes/keda-service/configmap.yaml
   kubectl apply -f kubernetes/keda-service/deployment.yaml
   kubectl apply -f kubernetes/keda-service/trigger-authentication.yaml
   kubectl apply -f kubernetes/keda-service/scaled-object.yaml
   ```

   Option 2: Use the provided script:
   ```bash
   # Make the script executable
   chmod +x scripts/apply-kubernetes-manifests.sh

   # Run the script
   ./scripts/apply-kubernetes-manifests.sh
   ```

### Environment Variables Configuration

The application's environment variables are managed through a ConfigMap (`kubernetes/keda-service/configmap.yaml`). This approach separates configuration from deployment, making it easier to manage and update configuration values.

Key environment variables that can be configured in the ConfigMap:

- `SQS_QUEUE_URL`: The URL of the SQS queue to poll
- `SQS_MAX_MESSAGES`: Maximum number of messages to receive in one batch
- `SQS_WAIT_TIME_SECONDS`: Wait time in seconds for long polling
- `SQS_VISIBILITY_TIMEOUT`: Visibility timeout in seconds
- `HEALTH_HOST`: Host to bind the health check server to
- `HEALTH_PORT`: Port to bind the health check server to
- `AWS_REGION`: AWS region
- `RUST_LOG`: Log level

If you need to update these values after deployment, simply edit the ConfigMap and restart the deployment:

```bash
kubectl edit configmap sqs-processor-config
kubectl rollout restart deployment sqs-processor
```

## Testing Auto-Scaling

Once your deployment is running, you can test the KEDA auto-scaling functionality by sending messages to your SQS queue.

### Using the Test Script

A convenient script is provided to send test messages:

```bash
# Send 10 test messages to the default queue
./scripts/send-test-messages.sh

# Send messages to a specific queue
./scripts/send-test-messages.sh https://sqs.us-west-2.amazonaws.com/{YOUR_ACCOUNT_ID}/your-queue

# Send a custom number of messages
./scripts/send-test-messages.sh https://sqs.us-west-2.amazonaws.com/{YOUR_ACCOUNT_ID}/your-queue us-west-2 20

# View help
./scripts/send-test-messages.sh --help
```

### Message Format

The script sends JSON messages with the following structure:
```json
{"messageNumber": "1"}
{"messageNumber": "2"}
...
```

### Monitoring Auto-Scaling

After sending messages, monitor the auto-scaling behavior:

```bash
# Watch pods scale up/down
kubectl get pods -w

# Check ScaledObject status
kubectl get scaledobject sqs-processor-scaler -n default

# View HPA status
kubectl get hpa -w

# Check KEDA operator logs
kubectl logs deployment/keda-operator -n keda -f
```

### Expected Behavior

1. **Scale Up**: When messages arrive in the queue, KEDA should scale your deployment from 0 to N pods (based on queue length and your `queueLength` setting)
2. **Processing**: Pods will process messages from the queue
3. **Scale Down**: When the queue is empty, KEDA will scale back down to 0 pods after the `cooldownPeriod`

## Cleaning Up Resources

This project includes a script to delete/unroll all resources created by the SQS Processor project, including:
- EKS cluster
- SQS queue
- IAM policies and roles

### Using the Cleanup Script

```bash
# Make the script executable
chmod +x scripts/cleanup-resources.sh

# Run the script with default values
./scripts/cleanup-resources.sh

# Or specify custom values
./scripts/cleanup-resources.sh --cluster-name my-cluster --region us-east-1 --stack-name my-stack
```

The script will:
1. Uninstall KEDA from the cluster
2. Delete IAM service accounts and policies for both KEDA and the application
3. Delete the EKS cluster
4. Delete the CloudFormation stack containing the SQS queue

The script includes confirmation prompts before deleting major resources to prevent accidental deletion.

### Command Line Options

- `--cluster-name NAME`: Specify the EKS cluster name (default: sandbox)
- `--region REGION`: Specify the AWS region (default: us-west-2)
- `--stack-name NAME`: Specify the CloudFormation stack name for the SQS queue (default: sqs-processor-stack)
- `--help`: Display help information

## Health Check Endpoints

- `/health/live`: Liveness probe endpoint
- `/health/ready`: Readiness probe endpoint

## Development

### Running Tests

```bash
cargo test
```

### Code Formatting

```bash
cargo fmt
```

## Troubleshooting

### KEDA Authentication and Scaling

#### TriggerAuthentication

KEDA uses a TriggerAuthentication resource to authenticate with AWS services. This project includes a TriggerAuthentication resource that uses the AWS EKS pod identity provider to authenticate with AWS SQS.

The TriggerAuthentication resource is defined in `kubernetes/keda-service/trigger-authentication.yaml`:

```yaml
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: aws-pod-identity
  namespace: default
spec:
  podIdentity:
    provider: aws-eks
```

This TriggerAuthentication resource is referenced in the ScaledObject resource in `kubernetes/keda-service/scaled-object.yaml`:

```yaml
authenticationRef:
  name: aws-pod-identity  # Reference to the TriggerAuthentication resource
```

When deploying the application, make sure to apply the TriggerAuthentication resource before the ScaledObject resource:

```bash
kubectl apply -f kubernetes/keda-service/trigger-authentication.yaml
kubectl apply -f kubernetes/keda-service/scaled-object.yaml
```

#### IAM Permission Errors

If you encounter IAM permission errors like the following:

```
operation error SQS: GetQueueAttributes, https response error StatusCode: 403, RequestID: bfce4720-8251-59e8-bfba-263c10bfdcf9, api error AccessDenied: User: arn:aws:sts::252703795646:assumed-role/eksctl-sandbox-nodegroup-mng-arm-NodeInstanceRole-XG3mWuZ62X6U/i-0cc905a274f44b524 is not authorized to perform: sqs:getqueueattributes on resource: arn:aws:sqs:us-west-2:252703795646:sqs-processor-queue
```

This indicates that the IAM policy doesn't have the necessary permissions to access the SQS queue. There are two ways to resolve this:

#### Option 1: Update the ScaledObject to use the pod's service account

In the `kubernetes/keda-service/scaled-object.yaml` file, change the `identityOwner` setting from `operator` to `pod`:

```yaml
triggers:
- type: aws-sqs-queue
  metadata:
    queueURL: https://sqs.us-west-2.amazonaws.com/252703795646/sqs-processor-queue
    queueLength: "5"
    awsRegion: "us-west-2"
    identityOwner: "pod"  # Change from "operator" to "pod"
```

This setting determines which IAM role KEDA will use to access the SQS queue:
- `operator`: Uses the IAM role attached to the KEDA operator's service account
- `pod`: Uses the IAM role attached to the application pod's service account (sqs-processor-sa)

If you're getting permission errors with `identityOwner: "operator"`, changing to `identityOwner: "pod"` will make KEDA use the application's service account, which already has the necessary SQS permissions.

#### Option 2: Update the IAM policies

1. Update the IAM policies in both `kubernetes/scripts/setup-keda-irsa.sh` and `kubernetes/scripts/setup-app-irsa.sh` to specify the exact SQS queue ARN instead of using a wildcard (`*`).
2. Re-run the scripts to update the IAM policies:

```bash
./kubernetes/scripts/setup-keda-irsa.sh
./kubernetes/scripts/setup-app-irsa.sh
```

3. Update your KEDA installation to use the updated service account:

```bash
helm upgrade keda kedacore/keda --namespace keda --set serviceAccount.create=false --set serviceAccount.name=keda-operator
```

#### KEDA Authentication and STS AssumeRole Errors

If you encounter errors like:
```
operation error SQS: GetQueueAttributes, get identity: get credentials: failed to refresh cached credentials, operation error STS: AssumeRole, https response error StatusCode: 403, RequestID: ..., api error AccessDenied: User: arn:aws:sts::...:assumed-role/... is not authorized to perform: sts:AssumeRole on resource: arn:aws:iam::...:role/...
```

Or:
```
error parsing SQS queue metadata: awsAccessKeyID not found
```

**Root Cause**: IRSA trust relationships are not properly configured between KEDA and the application service account.

**Solution**: Follow the updated setup scripts in the correct order:

1. **First, set up KEDA IRSA:**
   ```bash
   ./kubernetes/scripts/setup-keda-irsa.sh
   ```

2. **Then, set up Application IRSA:**
   ```bash
   ./kubernetes/scripts/setup-app-irsa.sh
   ```

3. **Verify the ScaledObject is working:**
   ```bash
   kubectl get scaledobject sqs-processor-scaler -n default
   ```

The ScaledObject should show `READY: True`. If you still see issues:

4. **Check the events for detailed errors:**
   ```bash
   kubectl describe scaledobject sqs-processor-scaler -n default
   ```

5. **Verify KEDA operator is using IRSA:**
   ```bash
   kubectl get serviceaccount keda-operator -n keda -o yaml
   ```

The updated scripts automatically handle the complex trust relationships required for KEDA to assume the application's role when using `identityOwner: "pod"`.

## Scripts Reference

This project includes several scripts to automate setup, configuration, and testing:

### Setup Scripts
- **`kubernetes/scripts/install-keda.sh`** - Install KEDA using Helm
- **`kubernetes/scripts/setup-keda-irsa.sh`** - Set up IRSA for KEDA operator with SQS permissions
- **`kubernetes/scripts/setup-app-irsa.sh`** - Set up IRSA for application with cross-role trust

### Configuration Scripts
- **`scripts/configure-manifests.sh`** - Configure Kubernetes manifests with AWS Account ID and settings
- **`scripts/deploy-sqs-queue.sh`** - Deploy SQS queue using CloudFormation

### Deployment Scripts
- **`scripts/apply-kubernetes-manifests.sh`** - Apply all Kubernetes manifests

### Testing Scripts
- **`scripts/send-test-messages.sh`** - Send test messages to SQS queue for testing auto-scaling

### Cleanup Scripts
- **`scripts/cleanup-resources.sh`** - Clean up all created AWS and Kubernetes resources

All scripts include help documentation accessible with the `--help` flag.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
