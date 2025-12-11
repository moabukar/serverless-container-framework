#!/bin/bash

set -e

# Colours
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== LocalStack Quick Start ===${NC}\n"

# Check dependencies
echo -e "${YELLOW}Checking dependencies...${NC}"

if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker not found. Please install Docker first.${NC}"
    exit 1
fi
echo "✓ Docker found"

if ! command -v aws &> /dev/null; then
    echo -e "${RED}✗ AWS CLI not found. Installing...${NC}"
    # On macOS: brew install awscli
    # On Linux: pip install awscli
    echo "Please install AWS CLI: https://aws.amazon.com/cli/"
    exit 1
fi
echo "✓ AWS CLI found"

if ! command -v serverless &> /dev/null; then
    echo -e "${RED}✗ Serverless Framework not found.${NC}"
    echo "Install with: npm install -g serverless"
    exit 1
fi
echo "✓ Serverless Framework found"

# Install serverless-localstack plugin
echo -e "\n${YELLOW}Installing serverless-localstack plugin...${NC}"
if [ ! -d "node_modules" ]; then
    npm install
fi
echo "✓ Plugin installed"

# Start LocalStack
echo -e "\n${YELLOW}Starting LocalStack...${NC}"
docker compose -f docker-compose.localstack.yml up -d

# Wait for LocalStack to be ready
echo "Waiting for LocalStack to be ready..."
sleep 5

# Check health
if curl -s http://localhost:4566/_localstack/health > /dev/null; then
    echo -e "${GREEN}✓ LocalStack is ready${NC}"
else
    echo -e "${RED}✗ LocalStack failed to start${NC}"
    docker compose -f docker-compose.localstack.yml logs
    exit 1
fi

# Set environment variables
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=eu-west-2

echo -e "\n${YELLOW}Deploying to LocalStack...${NC}"
serverless deploy --stage local --config serverless.containers.local.yml

echo -e "\n${GREEN}=== Setup Complete! ===${NC}\n"
echo "LocalStack is running at: http://localhost:4566"
echo ""
echo "Available commands:"
echo "  make localstack-status      # Check LocalStack health"
echo "  make aws-ls-functions       # List Lambda functions"
echo "  make aws-ls-stacks          # List CloudFormation stacks"
echo "  make localstack-logs        # View LocalStack logs"
echo "  make localstack-down        # Stop LocalStack"
echo ""
echo "Test your API:"
echo "  curl http://localhost:4566/lambda/health"
echo ""
echo "View logs:"
echo "  make localstack-logs-lambda"