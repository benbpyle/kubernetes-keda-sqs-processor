# Architecture Diagram: Rust SQS Processor with KEDA on EKS

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                                    AWS Cloud                                     │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                              Amazon EKS Cluster                         │   │
│  │                                                                         │   │
│  │  ┌──────────────────────────────────────────────────────────────────┐  │   │
│  │  │                        Kubernetes Control Plane                  │  │   │
│  │  │                         (Managed by AWS)                         │  │   │
│  │  └──────────────────────────────────────────────────────────────────┘  │   │
│  │                                    │                                    │   │
│  │  ┌──────────────────────────────────────────────────────────────────┐  │   │
│  │  │                           Worker Nodes                           │  │   │
│  │  │                                                                  │  │   │
│  │  │  ┌─────────────────┐    ┌─────────────────┐    ┌──────────────┐ │  │   │
│  │  │  │   keda namespace │    │ default namespace│    │System Pods   │ │  │   │
│  │  │  │                 │    │                 │    │              │ │  │   │
│  │  │  │ ┌─────────────┐ │    │ ┌─────────────┐ │    │ • CoreDNS    │ │  │   │
│  │  │  │ │ KEDA        │ │    │ │   Rust SQS  │ │    │ • kube-proxy │ │  │   │
│  │  │  │ │ Operator    │ │◄───┤ │ Processor   │ │    │ • AWS Node   │ │  │   │
│  │  │  │ │             │ │    │ │ Deployment  │ │    │   Daemonset  │ │  │   │
│  │  │  │ └─────────────┘ │    │ │             │ │    └──────────────┘ │  │   │
│  │  │  │                 │    │ │ ┌─────────┐ │ │                      │  │   │
│  │  │  │ ┌─────────────┐ │    │ │ │ Pod 1   │ │ │                      │  │   │
│  │  │  │ │ Metrics     │ │    │ │ └─────────┘ │ │                      │  │   │
│  │  │  │ │ Server      │ │    │ │ ┌─────────┐ │ │                      │  │   │
│  │  │  │ └─────────────┘ │    │ │ │ Pod 2   │ │ │                      │  │   │
│  │  │  │                 │    │ │ └─────────┘ │ │                      │  │   │
│  │  │  │ ┌─────────────┐ │    │ │     ...     │ │                      │  │   │
│  │  │  │ │ Admission   │ │    │ │ ┌─────────┐ │ │                      │  │   │
│  │  │  │ │ Webhooks    │ │    │ │ │ Pod N   │ │ │                      │  │   │
│  │  │  │ └─────────────┘ │    │ │ └─────────┘ │ │                      │  │   │
│  │  │  └─────────────────┘    │ │             │ │                      │  │   │
│  │  │                         │ │ ┌─────────┐ │ │                      │  │   │
│  │  │                         │ │ │   HPA   │ │ │                      │  │   │
│  │  │                         │ │ └─────────┘ │ │                      │  │   │
│  │  │                         │ │             │ │                      │  │   │
│  │  │                         │ │ ┌─────────┐ │ │                      │  │   │
│  │  │                         │ │ │Scaled   │ │ │                      │  │   │
│  │  │                         │ │ │Object   │ │ │                      │  │   │
│  │  │                         │ │ └─────────┘ │ │                      │  │   │
│  │  │                         │ └─────────────┘ │                      │  │   │
│  │  │                         └─────────────────┘                      │  │   │
│  │  └──────────────────────────────────────────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                                AWS Services                             │   │
│  │                                                                         │   │
│  │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                 │   │
│  │  │    SQS      │    │     IAM     │    │    OIDC     │                 │   │
│  │  │   Queue     │    │   Roles     │    │  Provider   │                 │   │
│  │  │             │    │             │    │             │                 │   │
│  │  │ ┌─────────┐ │    │ ┌─────────┐ │    │             │                 │   │
│  │  │ │Messages │ │    │ │KEDA Role│ │    │             │                 │   │
│  │  │ │         │ │    │ └─────────┘ │    │             │                 │   │
│  │  │ │Queue: 5 │ │    │ ┌─────────┐ │    │             │                 │   │
│  │  │ │         │ │    │ │App Role │ │    │             │                 │   │
│  │  │ └─────────┘ │    │ └─────────┘ │    │             │                 │   │
│  │  └─────────────┘    │             │    │             │                 │   │
│  │                     │ ┌─────────┐ │    │             │                 │   │
│  │                     │ │Node Role│ │    │             │                 │   │
│  │                     │ └─────────┘ │    │             │                 │   │
│  │                     └─────────────┘    └─────────────┘                 │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Component Flow and Interactions

### 1. KEDA Monitoring and Scaling Flow

```
SQS Queue ──► KEDA Operator ──► ScaledObject ──► HPA ──► Deployment ──► Pods
    │              │                │            │           │          │
    │              │                │            │           │          │
    └──────────────┼────────────────┼────────────┼───────────┼──────────┘
                   │                │            │           │
                   ▼                ▼            ▼           ▼
             Metrics Query    Scale Decision   Pod Count   Message 
            (Every 15s)      (Queue ÷ 5)     Adjustment  Processing

Timeline:
1. KEDA queries SQS queue depth every 15 seconds
2. If queue has messages: KEDA calculates desired pods = ceiling(messages ÷ 5)
3. KEDA updates HPA with external metrics
4. HPA scales deployment up/down
5. New pods start and begin processing messages
6. When queue is empty, pods scale down after 300s cooldown
```

### 2. IAM and IRSA Authentication Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            IRSA Authentication Flow                         │
└─────────────────────────────────────────────────────────────────────────────┘

EKS OIDC Provider ──► IAM Trust Relationship ──► IAM Roles ──► AWS Services
        │                        │                   │              │
        │                        │                   │              │
        ▼                        ▼                   ▼              ▼
Service Account ──► Web Identity ──► AssumeRole ──► STS Token ──► SQS API
    Token              Token          Request         

KEDA Flow:
┌─────────────┐    ┌──────────────┐    ┌─────────────┐    ┌─────────────┐
│ keda-operator│───►│KEDA IRSA Role│───►│App IRSA Role│───►│  SQS Queue  │
│Service Acct │    │              │    │             │    │             │
└─────────────┘    └──────────────┘    └─────────────┘    └─────────────┘
                          │                    │
                          │                    │
                   Cross-Role Trust     Direct Access
                   (AssumeRole)         (GetQueueAttributes)

App Flow:
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│sqs-processor│───►│App IRSA Role│───►│  SQS Queue  │
│Service Acct │    │             │    │             │
└─────────────┘    └─────────────┘    └─────────────┘
                          │
                          │
                   Direct Access
                   (All SQS Operations)
```

### 3. Message Processing Lifecycle

```
┌────────────┐    ┌──────────────┐    ┌─────────────┐    ┌──────────────┐
│  Producer  │───►│  SQS Queue   │───►│   KEDA      │───►│ HPA Decision │
│            │    │              │    │ Monitoring  │    │              │
└────────────┘    └──────────────┘    └─────────────┘    └──────────────┘
                          │                                       │
                          │                                       ▼
                          │                              ┌──────────────┐
                          │                              │ Deployment   │
                          │                              │ Scaling      │
                          │                              └──────────────┘
                          │                                       │
                          │                                       ▼
                          │                              ┌──────────────┐
                          │                              │   Pod        │
                          │                              │ Creation     │
                          │                              └──────────────┘
                          │                                       │
                          │                                       ▼
                          │                              ┌──────────────┐
                          └──────────────────────────────► Rust SQS     │
                                                         │ Processor    │
                                                         │              │
                                                         │ • Long Poll  │
                                                         │ • Process    │
                                                         │ • Delete     │
                                                         └──────────────┘

Message States:
1. Available (Visible in queue, KEDA counts these)
2. In-Flight (Being processed, invisible for 30s)
3. Processed (Deleted from queue)
4. Failed (Returns to Available after visibility timeout)
```

### 4. Scaling Behavior

```
Queue Depth vs Pod Count:

Messages │ Target Pods │ Scaling Action
---------|-------------|---------------
0        │ 0          │ Scale to Zero (after 300s cooldown)
1-5      │ 1          │ Scale Up to 1
6-10     │ 2          │ Scale Up to 2
11-15    │ 3          │ Scale Up to 3
...      │ ...        │ ...
46-50    │ 10         │ Scale Up to 10 (max)

Scaling Timeline:
┌─────────────────────────────────────────────────────────────────┐
│                        Scaling Events                           │
└─────────────────────────────────────────────────────────────────┘

T+0s:    Messages arrive in queue (0 → 12 messages)
T+15s:   KEDA detects messages, calculates 12÷5 = 3 pods needed
T+16s:   HPA receives scaling request
T+17s:   Deployment scales from 0 → 3 pods
T+20s:   Pods start and begin processing
T+45s:   Queue empty, but pods continue running
T+345s:  Cooldown expires, scale down to 0 pods

Configuration Values:
- pollingInterval: 15s (how often KEDA checks)
- queueLength: 5 (target messages per pod)
- cooldownPeriod: 300s (wait before scaling down)
- minReplicaCount: 0 (scale to zero enabled)
- maxReplicaCount: 10 (maximum pods)
```

### 5. Network and Security

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Network Flow                                   │
└─────────────────────────────────────────────────────────────────────────────┘

Internet ──► Load Balancer ──► EKS Cluster ──► Pods ──► AWS Services
    │              │               │            │            │
    │              │               │            │            │
    ▼              ▼               ▼            ▼            ▼
External      AWS ALB/NLB    VPC Network   Pod Network   Service
Traffic      (if exposed)      Subnets      (CNI)       Endpoints

Security Boundaries:
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   VPC       │    │  Security   │    │   RBAC      │
│  Network    │────│   Groups    │────│Kubernetes   │
│   ACLs      │    │             │    │Permissions  │
└─────────────┘    └─────────────┘    └─────────────┘
       │                   │                   │
       │                   │                   │
       ▼                   ▼                   ▼
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Subnet    │    │    Pod      │    │   Service   │
│  Isolation  │    │  Security   │    │  Account    │
│             │    │  Context    │    │   Token     │
└─────────────┘    └─────────────┘    └─────────────┘

IAM Permission Flow:
Pod → Service Account → IRSA Role → SQS Permissions → AWS API
```

## Key Components Explained

### KEDA Components
- **Operator**: Main controller that watches ScaledObjects and creates/manages HPAs
- **Metrics Server**: Exposes external metrics to Kubernetes metrics API
- **Admission Webhooks**: Validates ScaledObject configurations

### Kubernetes Resources
- **ScaledObject**: KEDA CRD that defines scaling behavior and triggers
- **HPA**: Standard Kubernetes Horizontal Pod Autoscaler (managed by KEDA)
- **Deployment**: Manages the Rust SQS processor pods
- **ServiceAccount**: Kubernetes identity for IRSA authentication

### AWS Resources
- **SQS Queue**: Message queue that triggers scaling
- **IAM Roles**: IRSA roles for KEDA and application with SQS permissions
- **OIDC Provider**: EKS-managed identity provider for service account tokens

### Scaling Logic
```
Desired Pods = ceiling(Queue Depth ÷ queueLength)
If Queue Depth = 0: Scale to minReplicaCount after cooldownPeriod
If Queue Depth > 0: Scale up immediately
Max Pods = maxReplicaCount
```

This architecture provides:
- ✅ **Auto-scaling** based on queue depth
- ✅ **Scale-to-zero** for cost efficiency  
- ✅ **Secure** IAM-based authentication
- ✅ **Resilient** message processing
- ✅ **Observable** through Kubernetes metrics