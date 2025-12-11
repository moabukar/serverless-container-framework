#!/bin/bash

# Load testing script for comparing Lambda vs Fargate performance

set -e

# Configuration
ALB_URL="${ALB_URL:-https://your-alb-url.amazonaws.com}"
REQUESTS="${REQUESTS:-1000}"
CONCURRENCY="${CONCURRENCY:-10}"

# Colours
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Colour

echo -e "${GREEN}=== Serverless Container Load Test ===${NC}"
echo ""
echo "Configuration:"
echo "  ALB URL: $ALB_URL"
echo "  Requests: $REQUESTS"
echo "  Concurrency: $CONCURRENCY"
echo ""

# Check if ALB_URL is set properly
if [[ "$ALB_URL" == "https://your-alb-url.amazonaws.com" ]]; then
    echo -e "${RED}ERROR: Please set ALB_URL environment variable${NC}"
    echo "Example: export ALB_URL=https://golang-demo-alb-xxx.eu-west-2.elb.amazonaws.com"
    exit 1
fi

# Check dependencies
command -v ab >/dev/null 2>&1 || { 
    echo -e "${RED}ERROR: Apache Bench (ab) is required but not installed${NC}"
    echo "Install: sudo apt-get install apache2-utils"
    exit 1
}

# Function to run load test
run_load_test() {
    local endpoint=$1
    local name=$2
    
    echo -e "${YELLOW}Testing $name: $endpoint${NC}"
    
    ab -n $REQUESTS -c $CONCURRENCY -q "$ALB_URL$endpoint" 2>&1 | \
        grep -E "(Requests per second|Time per request|Transfer rate|50%|95%|99%)" | \
        sed 's/^/  /'
    
    echo ""
}

# Warm up
echo -e "${YELLOW}Warming up endpoints...${NC}"
curl -s "$ALB_URL/lambda/health" > /dev/null
curl -s "$ALB_URL/fargate/health" > /dev/null
sleep 2

# Run tests
echo -e "${GREEN}=== Lambda Function ===${NC}"
run_load_test "/lambda/health" "Lambda Health Check"
run_load_test "/lambda/api/hello" "Lambda API"

echo -e "${GREEN}=== Fargate Container ===${NC}"
run_load_test "/fargate/health" "Fargate Health Check"
run_load_test "/fargate/api/hello" "Fargate API"

# Summary
echo -e "${GREEN}=== Load Test Complete ===${NC}"
echo ""
echo "Analysis tips:"
echo "  - Compare 'Requests per second' for throughput"
echo "  - Compare '95%' and '99%' for tail latency"
echo "  - Lambda may show higher latency on first requests (cold starts)"
echo "  - Fargate should show consistent performance"
echo ""
echo "Run with custom settings:"
echo "  REQUESTS=10000 CONCURRENCY=50 ALB_URL=https://your-url ./load-test.sh"