# Serverless Container Framework - Basic Example

This is a basic example of how to use the Serverless Container Framework to deploy a simple web application.


```bash
npm install -g serverless

# Option 1: AWS CLI (recommended)
aws configure

# Option 2: Environment variables
export AWS_ACCESS_KEY_ID=your-key-id
export AWS_SECRET_ACCESS_KEY=your-access-key
export AWS_SESSION_TOKEN=your-session-token

cd service
npm install 
serverless dev # local

serverless deploy # deploy to aws
```

## Cleanup

```bash
serverless remove
serverless remove --force
```

## Troubleshooting

- Ensure Docker daemon is running for local development
- Check AWS credentials are properly configured using aws sts get-caller-identity
- View detailed logs with serverless dev --debug or serverless deploy --debug
