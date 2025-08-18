# SQS Processor

A Rust application that polls AWS SQS queues and processes messages. It's designed to run in a Kubernetes environment with KEDA for auto-scaling based on queue length.

## Features

- Long polling of AWS SQS queues
- Health check endpoints for Kubernetes liveness and readiness probes
- Graceful shutdown on SIGTERM
- Configurable logging
- Kubernetes deployment with KEDA auto-scaling

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
chmod +x scripts/install-keda.sh

# Run the installation script
./scripts/install-keda.sh
```

This script will:
1. Add the KEDA Helm repository
2. Create the keda namespace
3. Install KEDA using Helm

### Setting up IAM Roles for Service Accounts (IRSA)

To allow KEDA to access AWS SQS using IAM roles, you can set up IAM Roles for Service Accounts (IRSA):

```bash
# Make the script executable
chmod +x kubernetes/scripts/setup-keda-irsa.sh

# Edit the script to set your cluster name, region, and SQS queue ARN
vi kubernetes/scripts/setup-keda-irsa.sh

# Run the setup script
./kubernetes/scripts/setup-keda-irsa.sh
```

> **Important**: The IAM policy created by this script grants permissions for a specific SQS queue ARN. Make sure to update the ARN in the script to match your SQS queue.

This script will:
1. Create an IAM policy for KEDA to access SQS
2. Create an IAM role and service account for KEDA

After running the script, you need to update your KEDA installation to use the service account. You can do this in three ways:

#### Option 1: Using the update-keda-irsa.sh script (Recommended)

A script has been provided to automatically update KEDA to use the service account:

```bash
# Make the script executable
chmod +x kubernetes/scripts/update-keda-irsa.sh

# Run the update script
./kubernetes/scripts/update-keda-irsa.sh
```

This script will:
1. Check if the necessary components exist
2. Update KEDA to use the keda-operator service account
3. Provide confirmation of the update

#### Option 2: Using a values.yaml file

A values.yaml file has been created at `kubernetes/keda-values.yaml` with the following content:

```yaml
serviceAccount:
  create: false
  name: keda-operator
```

Update KEDA with:

```bash
helm upgrade keda kedacore/keda --namespace keda -f kubernetes/keda-values.yaml
```

#### Option 3: Using command line parameters

Alternatively, you can update KEDA directly from the command line without using a values file:

```bash
helm upgrade keda kedacore/keda --namespace keda --set serviceAccount.create=false --set serviceAccount.name=keda-operator
```

#### Note for New Installations

If you're installing KEDA for the first time after setting up IRSA, the `install-keda.sh` script will automatically use the `keda-values.yaml` file if it exists, configuring KEDA to use the service account with the proper IAM permissions.

### Setting up IRSA for the Application

Similarly, you can set up IRSA for the application itself:

```bash
# Make the script executable
chmod +x scripts/setup-app-irsa.sh

# Edit the script to set your cluster name, region, SQS queue ARN, and other parameters
vi scripts/setup-app-irsa.sh

# Run the setup script
./scripts/setup-app-irsa.sh
```

> **Important**: The IAM policy created by this script grants permissions for a specific SQS queue ARN. Make sure to update the ARN in the script to match your SQS queue.

This script will:
1. Check if an IAM OIDC provider is associated with the cluster and create one if needed
2. Create an IAM policy for the application to access SQS
3. Create an IAM role and service account for the application
4. Provide instructions for updating your deployment to use the service account

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

1. Create an EKS cluster if you don't have one already (see [Creating an EKS Cluster](#creating-an-eks-cluster))
2. Ensure KEDA is installed in your cluster (see [Installing KEDA](#installing-keda))
3. Push the Docker image to a registry accessible by your Kubernetes cluster
4. Update the image reference in `kubernetes/keda-service/deployment.yaml`
5. Update the SQS queue URL and AWS region in both:
   - `kubernetes/keda-service/configmap.yaml` (for the application)
   - `kubernetes/keda-service/scaled-object.yaml` (for KEDA scaling)
6. If using IAM Roles for Service Accounts (IRSA), update the deployment to use the service account (see [Setting up IRSA for the Application](#setting-up-irsa-for-the-application))
7. Apply the Kubernetes manifests:

   Option 1: Apply each manifest individually:
   ```bash
   kubectl apply -f kubernetes/keda-service/configmap.yaml
   kubectl apply -f kubernetes/keda-service/deployment.yaml
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

### IAM Permission Issues

If you encounter IAM permission errors like the following:

```
operation error SQS: GetQueueAttributes, https response error StatusCode: 403, RequestID: bfce4720-8251-59e8-bfba-263c10bfdcf9, api error AccessDenied: User: arn:aws:sts::252703795646:assumed-role/eksctl-sandbox-nodegroup-mng-arm-NodeInstanceRole-XG3mWuZ62X6U/i-0cc905a274f44b524 is not authorized to perform: sqs:getqueueattributes on resource: arn:aws:sqs:us-west-2:252703795646:sqs-processor-queue
```

This indicates that the IAM policy doesn't have the necessary permissions to access the SQS queue. To resolve this:

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

## License

This project is licensed under the MIT License - see the LICENSE file for details.
