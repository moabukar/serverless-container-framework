# Architecture Overview

## High-Level Architecture

```
                                    Internet
                                        |
                                        v
                            ┌───────────────────────┐
                            │  Application Load     │
                            │  Balancer (ALB)       │
                            │  - HTTPS/HTTP         │
                            │  - Path-based routing │
                            └───────────┬───────────┘
                                        |
                    ┌───────────────────┴───────────────────┐
                    |                                       |
            /lambda/* path                          /fargate/* path
                    |                                       |
                    v                                       v
        ┌──────────────────────┐              ┌──────────────────────┐
        │   AWS Lambda         │              │   ECS Fargate        │
        │   ┌──────────────┐   │              │   ┌──────────────┐   │
        │   │  Container   │   │              │   │  Container   │   │
        │   │  - Go App    │   │              │   │  - Go App    │   │
        │   │  - Port 8080 │   │              │   │  - Port 8080 │   │
        │   └──────────────┘   │              │   └──────────────┘   │
        │                      │              │                      │
        │  Auto-scaling:       │              │  Auto-scaling:       │
        │  0 → 1000            │              │  1 → 10 tasks        │
        │  instances           │              │                      │
        └──────────────────────┘              └──────────────────────┘
                    |                                       |
                    └───────────────────┬───────────────────┘
                                        |
                                        v
                            ┌───────────────────────┐
                            │   CloudWatch Logs     │
                            │   - Application logs  │
                            │   - Request logs      │
                            │   - Metrics           │
                            └───────────────────────┘
```

## Request Flow

### Lambda Path (`/lambda/*`)

1. **Client Request**
   - `GET /lambda/health` → ALB
   
2. **ALB Processing**
   - Matches path pattern `/lambda/*`
   - Routes to Lambda target group
   - Waits for response (max 30s)
   
3. **Lambda Execution**
   - Cold start: Function init (~200-500ms)
     - Download container image (first time)
     - Start execution environment
     - Load Go runtime
     - Execute handler
   - Warm start: Direct execution (~5-10ms)
   
4. **Response**
   - JSON response with `compute: "lambda"`
   - ALB forwards to client

### Fargate Path (`/fargate/*`)

1. **Client Request**
   - `GET /fargate/health` → ALB
   
2. **ALB Processing**
   - Matches path pattern `/fargate/*`
   - Routes to Fargate target group
   - Health check: Every 30s
   
3. **Fargate Processing**
   - Always warm (no cold starts)
   - Container runs continuously
   - Direct HTTP request to :8080
   
4. **Response**
   - JSON response with `compute: "fargate"`
   - ALB forwards to client

## Networking

### VPC Configuration

```
VPC: 10.0.0.0/16
  |
  ├── Public Subnet A (10.0.1.0/24) - AZ A
  |   └── NAT Gateway A
  |
  ├── Public Subnet B (10.0.2.0/24) - AZ B
  |   └── NAT Gateway B
  |
  ├── Private Subnet A (10.0.10.0/24) - AZ A
  |   ├── Lambda ENIs
  |   └── Fargate Tasks
  |
  └── Private Subnet B (10.0.11.0/24) - AZ B
      ├── Lambda ENIs
      └── Fargate Tasks
```

**Components:**
- **ALB**: Public-facing, in public subnets
- **Lambda**: ENIs in private subnets (VPC mode)
- **Fargate**: Tasks in private subnets
- **NAT Gateways**: Outbound internet for private subnets

### Security Groups

```
ALB Security Group:
  Ingress: 0.0.0.0/0:443 (HTTPS)
  Ingress: 0.0.0.0/0:80 (HTTP)
  Egress: Lambda/Fargate SG:8080

Lambda Security Group:
  Ingress: ALB SG:8080
  Egress: 0.0.0.0/0:443 (AWS APIs)

Fargate Security Group:
  Ingress: ALB SG:8080
  Egress: 0.0.0.0/0:443 (AWS APIs)
```

## Scaling Behaviour

### Lambda Auto-scaling

```
Request Load → Lambda Invocations

0 requests     → 0 instances (cold)
1 request      → 1 instance (cold start ~200-500ms)
10 requests    → 10 instances (parallel execution)
1000 requests  → 1000 instances (default concurrency limit)
10000 requests → 1000 instances (throttling above limit)
```

**Characteristics:**
- Scales instantly (within milliseconds)
- Each invocation = separate container
- Cold start on first request after idle period
- Warm instances reused for ~15 minutes

### Fargate Auto-scaling

```
Metric-based Scaling

CPU > 60% for 1 min    → Scale out (+1 task)
CPU < 60% for 5 min    → Scale in (-1 task)
Memory > 70% for 1 min → Scale out (+1 task)

Min: 1 task (always running)
Max: 10 tasks (based on config)
```

**Characteristics:**
- Gradual scaling (1-2 minutes per task)
- Always warm (no cold starts)
- Predictable performance
- Longer scale-down cooldown (cost consideration)

## Cost Model Comparison

### Lambda Pricing (London - eu-west-2)

```
Memory: 512MB
Duration: 200ms average

Cost per request:
  Compute: 512MB × 0.2s × $0.0000000083 = $0.000000836
  Request: $0.0000002
  Total: $0.000001036 per request

Monthly costs:
  1K requests:   $0.001
  10K requests:  $0.01
  100K requests: $0.10
  1M requests:   $1.03
  10M requests:  $10.36
```

### Fargate Pricing (London - eu-west-2)

```
Configuration: 512MB RAM, 0.25 vCPU

Cost per task-hour:
  vCPU: 0.25 × $0.04656 = $0.01164
  Memory: 0.5GB × $0.00511 = $0.00256
  Total: $0.0142 per hour

Monthly costs (1 task):
  730 hours × $0.0142 = $10.37/month

Monthly costs with scaling:
  2 tasks (baseline): $20.74
  Peak 5 tasks for 4 hours/day: +$17.04
  Total: ~$37.78/month
```

### Break-even Analysis

```
Daily requests for Lambda = Fargate cost:

1 task Fargate: $10.37/month
Break-even requests: ~10,000/day (300K/month)

2 tasks Fargate: $20.74/month
Break-even requests: ~20,000/day (600K/month)

Rule of thumb:
  < 10K req/day  → Lambda cheaper
  > 10K req/day  → Fargate cheaper
  > 100K req/day → Fargate much cheaper
```

## Performance Characteristics

### Latency Breakdown

**Lambda (Cold Start):**
```
Total: ~300-600ms
├── ALB routing: 5-10ms
├── Lambda init: 200-500ms
│   ├── Container download: 100-200ms
│   ├── Runtime init: 50-150ms
│   └── Handler init: 50-150ms
└── Handler execution: 5-10ms
```

**Lambda (Warm):**
```
Total: ~10-20ms
├── ALB routing: 5-10ms
└── Handler execution: 5-10ms
```

**Fargate:**
```
Total: ~10-20ms
├── ALB routing: 5-10ms
└── Container processing: 5-10ms
```

### Throughput

**Lambda:**
- Theoretical: 1000 concurrent = 5000 req/s (200ms each)
- Practical: 500-1000 req/s (accounting for cold starts)
- Burst: Excellent (instant scale)

**Fargate:**
- Per task: 50-100 req/s (depends on Go app efficiency)
- 10 tasks: 500-1000 req/s
- Burst: Limited by scale-out time (1-2 min)

## Observability

### CloudWatch Logs Structure

```
Lambda Logs:
  /aws/lambda/golang-demo-api-lambda
  ├── 2025/12/11/[$LATEST]abc123...
  │   ├── START RequestId: xxx
  │   ├── 2025/12/11 10:30:45 Started GET /health
  │   ├── 2025/12/11 10:30:45 Completed GET /health in 2ms
  │   └── END RequestId: xxx
  └── ...

Fargate Logs:
  /ecs/golang-demo-api-fargate
  ├── ecs/service/task-id
  │   ├── 2025/12/11 10:30:45 Starting server on port 8080
  │   ├── 2025/12/11 10:30:50 Started GET /health
  │   ├── 2025/12/11 10:30:50 Completed GET /health in 2ms
  │   └── ...
  └── ...
```

### Key Metrics

**Lambda Metrics:**
- `Invocations` - Total function calls
- `Duration` - Execution time
- `Errors` - Failed invocations
- `Throttles` - Rate-limited requests
- `ConcurrentExecutions` - Active instances

**Fargate Metrics:**
- `CPUUtilization` - CPU usage %
- `MemoryUtilization` - Memory usage %
- `TargetResponseTime` - ALB → task latency
- `HealthyHostCount` - Available tasks
- `RequestCount` - Total requests

## Failure Modes & Recovery

### Lambda Failures

**Scenario: Function timeout**
```
Request → Lambda (30s timeout) → Timeout
ALB returns 504 Gateway Timeout
Recovery: Automatic (new invocation)
```

**Scenario: Out of memory**
```
Request → Lambda → OOM error
ALB returns 502 Bad Gateway
Recovery: Automatic (new container)
```

**Scenario: Throttling**
```
Too many concurrent → Throttle error
ALB returns 502 Bad Gateway
Recovery: Retry with backoff
```

### Fargate Failures

**Scenario: Task crash**
```
Container dies → ECS detects → Starts new task
ALB health check fails → Remove from pool
New task healthy → Add to pool
Recovery time: 1-2 minutes
```

**Scenario: Deployment failure**
```
New task fails health check → ECS rollback
Old tasks continue serving traffic
Recovery: Automatic rollback
```

**Scenario: CPU throttling**
```
High CPU → Auto-scaling triggered → New task
Scale-out time: 1-2 minutes
Old tasks continue under load
```

## Security Considerations

### IAM Permissions

**Lambda Execution Role:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateNetworkInterface",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DeleteNetworkInterface"
      ],
      "Resource": "*"
    }
  ]
}
```

**Fargate Task Role:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    }
  ]
}
```

### Network Security

- **Private subnets**: No direct internet access
- **NAT Gateway**: Controlled egress
- **Security groups**: Least privilege (only :8080 from ALB)
- **ALB**: HTTPS termination, WAF integration possible

## Deployment Pipeline

```
┌──────────────────┐
│  Code Change     │
└────────┬─────────┘
         │
         v
┌──────────────────┐
│  serverless      │
│  deploy          │
└────────┬─────────┘
         │
    ┌────┴────┐
    │         │
    v         v
Lambda    Fargate
    │         │
    └────┬────┘
         │
         v
┌──────────────────┐
│  Docker Build    │
│  - Build image   │
│  - Push to ECR   │
└────────┬─────────┘
         │
         v
┌──────────────────┐
│  Infrastructure  │
│  - Update stack  │
│  - Blue/green    │
└────────┬─────────┘
         │
         v
┌──────────────────┐
│  Health Checks   │
│  - Wait for OK   │
└────────┬─────────┘
         │
         v
┌──────────────────┐
│  Traffic Shift   │
│  - Gradual       │
│  - Rollback auto │
└──────────────────┘
```

## Recommended Setup

### Development
```yaml
compute:
  type: awsLambda
  awsLambda:
    memory: 512
    timeout: 30
```
**Why:** Cheap, fast iteration, serverless dev mode

### Staging
```yaml
compute:
  type: awsLambda
  awsLambda:
    memory: 1024
    provisionedConcurrency: 1  # No cold starts
```
**Why:** Production-like, cost-effective, always warm

### Production (Low Traffic)
```yaml
compute:
  type: awsLambda
  awsLambda:
    memory: 1024
    reservedConcurrency: 100
    provisionedConcurrency: 5
```
**Why:** < 100K req/day, cost-effective, good performance

### Production (High Traffic)
```yaml
compute:
  type: awsFargateEcs
  awsFargateEcs:
    memory: 2048
    cpu: 1024
    minInstances: 3  # Multi-AZ
    maxInstances: 20
    autoScaling:
      targetCpuUtilization: 60
```
**Why:** > 100K req/day, consistent performance, cost-effective at scale