# Deployment Guide

## Step-by-Step Deployment

### 1. Prerequisites Check

```bash
# Verify installations
node --version          # Should be >= 20.x
docker --version        # Should show Docker version
aws --version          # Should show AWS CLI version

# Check AWS credentials
aws sts get-caller-identity

# Expected output:
# {
#     "UserId": "AIDAI...",
#     "Account": "123456789012",
#     "Arn": "arn:aws:iam::123456789012:user/yourname"
# }
```

### 2. Install Serverless Framework

```bash
npm install -g serverless@latest ## avoid using brew as it installs an older version

# Verify installation
serverless --version ## Expected: Framework Core: 4.x or later
```

### 3. Local Testing (Without Deployment)

#### Option A: Serverless Dev Mode

```bash
serverless dev
```

This starts:
- Local ALB emulation at `http://localhost:3000`
- Hot reload on code changes
- Request/response logging

Test endpoints:
```bash
# In another terminal
curl http://localhost:3000/lambda/health
curl http://localhost:3000/fargate/health
curl http://localhost:3000/lambda/api/hello
curl http://localhost:3000/fargate/api/users
```

#### Option B: Native Docker

```bash
docker build -t golang-demo .
docker run -p 8080:8080 -e COMPUTE_TYPE=local golang-demo

# Test
curl http://localhost:8080/health
```

### 4. First Deployment

```bash
# Deploy everything
serverless deploy

# What happens:
# 1. Creates VPC (if needed)              ~2-3 min
# 2. Creates Application Load Balancer   ~3-4 min
# 3. Builds container images              ~1-2 min
# 4. Deploys Lambda function              ~1 min
# 5. Deploys Fargate service             ~2-3 min
# Total: 9-13 minutes
```

Expected output:
```
✓ Building containers
  ✓ api-lambda built successfully
  ✓ api-fargate built successfully

✓ Deploying infrastructure
  ✓ VPC created: vpc-0abc123def456
  ✓ ALB created: golang-demo-alb-xxx.eu-west-2.elb.amazonaws.com

✓ Deploying containers
  ✓ api-lambda deployed to Lambda
  ✓ api-fargate deployed to Fargate

Endpoints:
  https://golang-demo-alb-xxx.eu-west-2.elb.amazonaws.com/lambda/*
  https://golang-demo-alb-xxx.eu-west-2.elb.amazonaws.com/fargate/*

Deployment time: 9m 34s
```

### 5. Test Deployed Application

```bash
# Save your ALB URL
export ALB_URL="https://golang-demo-alb-xxx.eu-west-2.elb.amazonaws.com"

# Test Lambda version
curl $ALB_URL/lambda/health
curl $ALB_URL/lambda/api/hello
curl $ALB_URL/lambda/api/users

# Test Fargate version
curl $ALB_URL/fargate/health
curl $ALB_URL/fargate/api/hello
curl $ALB_URL/fargate/api/users
```

Compare response times:
```bash
# Lambda cold start
time curl -s $ALB_URL/lambda/health

# Lambda warm (run again immediately)
time curl -s $ALB_URL/lambda/health

# Fargate (always warm)
time curl -s $ALB_URL/fargate/health
```

### 6. Subsequent Deployments

After code changes:

```bash
serverless deploy

# Much faster: 2-4 minutes
# Only updates changed containers
```

### 7. Switch Compute Types

Edit `serverless.containers.yml`:

```yaml
containers:
  api-lambda:
    compute:
      type: awsFargateEcs  # Change from awsLambda
      awsFargateEcs:
        memory: 512
        cpu: 256
```

```bash
serverless deploy

# SCF handles:
# - Creates new Fargate task
# - Migrates traffic gradually
# - Removes old Lambda function
# No downtime!
```

## Real-World Deployment Patterns

### Pattern 1: Cost Optimisation Path

Start with Lambda (cheapest for low traffic):
```yaml
api:
  compute:
    type: awsLambda
```

Monitor CloudWatch metrics. When >150K req/day, switch to Fargate:
```yaml
api:
  compute:
    type: awsFargateEcs
    awsFargateEcs:
      minInstances: 2
      maxInstances: 5
```

### Pattern 2: Hybrid Deployment

Use both simultaneously:
```yaml
containers:
  web-frontend:
    src: ./frontend
    routing:
      pathPattern: /*
    compute:
      type: awsLambda  # Frontend – infrequent, cacheable
      
  api-backend:
    src: ./backend
    routing:
      pathPattern: /api/*
    compute:
      type: awsFargateEcs  # Backend – frequent, stateful
```

### Pattern 3: Canary Deployment

Deploy new version to separate path first:
```yaml
containers:
  api-stable:
    routing:
      pathPattern: /api/*
    compute:
      type: awsLambda
      
  api-canary:
    routing:
      pathPattern: /canary/*
    compute:
      type: awsLambda  # Test new version
```

Route 5% traffic to canary, monitor, then promote.

## Monitoring Post-Deployment

### CloudWatch Logs

```bash
# Lambda logs
aws logs tail /aws/lambda/golang-demo-api-lambda --follow --format short

# Fargate logs
aws logs tail /aws/ecs/golang-demo-api-fargate --follow --format short
```

### CloudWatch Metrics

```bash
# Lambda invocations
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=golang-demo-api-lambda \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum

# Fargate CPU
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ServiceName,Value=golang-demo-api-fargate \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

### Cost Monitoring

```bash
# Check current month spend
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --filter file://filter.json

# filter.json:
{
  "Tags": {
    "Key": "serverless-framework",
    "Values": ["golang-demo"]
  }
}
```

## Troubleshooting Deployments

### Issue: Deployment Hangs

```bash
# Check CloudFormation status
aws cloudformation describe-stacks \
  --stack-name golang-demo \
  --query 'Stacks[0].StackStatus'

# Check events for errors
aws cloudformation describe-stack-events \
  --stack-name golang-demo \
  --max-items 10
```

### Issue: Container Build Fails

```bash
# Test locally first
docker build -t test .
docker run -p 8080:8080 test

# Check logs
docker logs $(docker ps -lq)
```

### Issue: Health Check Fails

```bash
# Verify endpoint
curl -v http://localhost:8080/health

# Should return 200 with JSON
# Check Dockerfile EXPOSE and CMD
```

### Issue: Permission Denied

```bash
# Verify IAM permissions
aws iam get-user
aws iam list-attached-user-policies --user-name YOUR_USERNAME

# Required policies:
# - AWSLambda_FullAccess
# - AmazonECS_FullAccess
# - AmazonEC2FullAccess
# - IAMFullAccess (for role creation)
```

## Cost Breakdown Example

### Scenario: 1M requests/month, 200ms avg duration

**Lambda (512MB):**
```
Compute: 1M * 0.2s * 0.0000000083 * 512 = $0.83
Requests: 1M * 0.0000002 = $0.20
Total: ~$1.03/month
```

**Fargate (512MB, 0.25 vCPU, 1 task):**
```
Compute: 730 hours * $0.01896 = $13.84
Total: ~$13.84/month
```

**Break-even:** ~150K requests/day

## Cleanup

### Temporary Removal (Keep VPC)

```bash
serverless remove

# Removes:
# - Lambda functions
# - Fargate services
# - ALB rules
# Keeps:
# - VPC
# - Subnets
# - NAT gateways (if created)
```

### Complete Removal

```bash
serverless remove --force

# Removes everything
# Can take 5-10 minutes
```

### Verify Cleanup

```bash
# Check CloudFormation
aws cloudformation list-stacks \
  --query 'StackSummaries[?contains(StackName, `golang-demo`)].{Name:StackName,Status:StackStatus}'

# Check ECR repositories
aws ecr describe-repositories \
  --query 'repositories[?contains(repositoryName, `golang-demo`)].repositoryName'

# Check VPCs
aws ec2 describe-vpcs \
  --filters "Name=tag:serverless-framework,Values=golang-demo" \
  --query 'Vpcs[].VpcId'
```