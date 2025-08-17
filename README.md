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
- Kubernetes cluster
- AWS account with SQS queue

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
chmod +x scripts/setup-keda-irsa.sh

# Edit the script to set your cluster name and region
vi scripts/setup-keda-irsa.sh

# Run the setup script
./scripts/setup-keda-irsa.sh
```

This script will:
1. Create an IAM policy for KEDA to access SQS
2. Create an IAM role and service account for KEDA
3. Configure KEDA to use the service account

### Setting up IRSA for the Application

Similarly, you can set up IRSA for the application itself:

```bash
# Make the script executable
chmod +x scripts/setup-app-irsa.sh

# Edit the script to set your cluster name, region, and other parameters
vi scripts/setup-app-irsa.sh

# Run the setup script
./scripts/setup-app-irsa.sh
```

This script will:
1. Create an IAM policy for the application to access SQS
2. Create an IAM role and service account for the application
3. Provide instructions for updating your deployment to use the service account

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

1. Ensure KEDA is installed in your cluster (see [Installing KEDA](#installing-keda))
2. Push the Docker image to a registry accessible by your Kubernetes cluster
3. Update the image reference in `kubernetes/keda-service/deployment.yaml`
4. Update the SQS queue URL and AWS region in `kubernetes/keda-service/scaled-object.yaml`
5. If using IAM Roles for Service Accounts (IRSA), update the deployment to use the service account (see [Setting up IRSA for the Application](#setting-up-irsa-for-the-application))
6. Apply the Kubernetes manifests:

```bash
kubectl apply -f kubernetes/keda-service/deployment.yaml
kubectl apply -f kubernetes/keda-service/scaled-object.yaml
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

## License

This project is licensed under the MIT License - see the LICENSE file for details.
