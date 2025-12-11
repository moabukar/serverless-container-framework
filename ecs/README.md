# SCF 

```bash

export AWS_ACCESS_KEY_ID=******
export AWS_SECRET_ACCESS_KEY=******
export AWS_REGION=eu-west-2

npm install -g serverless
serverless --version

serverless deploy

AWS_REGION=eu-west-2 serverless deploy ## try this one...


serverless logs --container api-fargate --tail

serverless remove
```