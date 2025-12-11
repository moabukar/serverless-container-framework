#!/bin/bash

# Compare Lambda vs Fargate response characteristics

set -e

ALB_URL="${ALB_URL:-https://your-alb-url.amazonaws.com}"

# Colours
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}=== Lambda vs Fargate Comparison ===${NC}\n"

if [[ "$ALB_URL" == "https://your-alb-url.amazonaws.com" ]]; then
    echo "ERROR: Set ALB_URL first"
    echo "Example: export ALB_URL=https://golang-demo-alb-xxx.eu-west-2.elb.amazonaws.com"
    exit 1
fi

# Function to measure response time
measure() {
    local url=$1
    local result=$(curl -s -w "\n%{time_total}" -o /tmp/response.json "$url")
    local time=$(echo "$result" | tail -n1)
    local body=$(cat /tmp/response.json)
    echo "$time|$body"
}

# Test cold start (Lambda)
echo -e "${YELLOW}Testing Lambda cold start (wait 5 minutes for function to go cold)...${NC}"
sleep 5
result=$(measure "$ALB_URL/lambda/health")
time=$(echo "$result" | cut -d'|' -f1)
body=$(echo "$result" | cut -d'|' -f2)
echo "  Cold start: ${time}s"
echo "  Response: $(echo $body | jq -r .compute)"

# Test warm Lambda
echo -e "\n${YELLOW}Testing Lambda warm (immediate re-request)...${NC}"
result=$(measure "$ALB_URL/lambda/health")
time=$(echo "$result" | cut -d'|' -f1)
echo "  Warm: ${time}s"

# Test Fargate (always warm)
echo -e "\n${YELLOW}Testing Fargate (always warm)...${NC}"
result=$(measure "$ALB_URL/fargate/health")
time=$(echo "$result" | cut -d'|' -f1)
body=$(echo "$result" | cut -d'|' -f2)
echo "  Response: ${time}s"
echo "  Compute: $(echo $body | jq -r .compute)"

# Burst test
echo -e "\n${YELLOW}Testing burst handling (10 concurrent requests)...${NC}"
echo "Lambda:"
for i in {1..10}; do
    curl -s "$ALB_URL/lambda/api/hello" > /dev/null &
done
wait
echo "  ✓ Completed"

echo "Fargate:"
for i in {1..10}; do
    curl -s "$ALB_URL/fargate/api/hello" > /dev/null &
done
wait
echo "  ✓ Completed"

# Feature comparison
echo -e "\n${BLUE}=== Feature Comparison ===${NC}\n"

cat << 'EOF'
┌─────────────────────┬────────────────────┬────────────────────┐
│ Feature             │ Lambda             │ Fargate            │
├─────────────────────┼────────────────────┼────────────────────┤
│ Cold Start          │ 100-500ms          │ None               │
│ Warm Response       │ <10ms              │ <10ms              │
│ Scaling Speed       │ Instant            │ 1-2 minutes        │
│ Max Concurrent      │ 1000 (default)     │ Limited by config  │
│ Pricing Model       │ Per request        │ Per hour running   │
│ Best For            │ Bursty traffic     │ Steady traffic     │
│ WebSocket Support   │ No                 │ Yes                │
│ Long-running Tasks  │ <15 min            │ Unlimited          │
│ Memory Options      │ 128MB-10GB         │ 512MB-30GB         │
└─────────────────────┴────────────────────┴────────────────────┘

Cost Analysis (1M requests/month, 200ms avg):

Lambda (512MB):
  Compute:  1M × 0.2s × $0.0000000083 × 512 = $0.83
  Requests: 1M × $0.0000002 = $0.20
  Total: ~$1.03/month

Fargate (512MB, 0.25 vCPU, 1 task):
  Compute: 730 hours × $0.01896 = $13.84
  Total: ~$13.84/month

Break-even: ~150,000 requests/day

Recommendation:
  < 100K req/day  → Use Lambda
  > 100K req/day  → Use Fargate
  > 1M req/day    → Use Fargate with auto-scaling

EOF

echo -e "\nRun load test with: ./load-test.sh"