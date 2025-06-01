#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Setting up complete Lughati Cloud Infrastructure...${NC}"

# Create all directories
mkdir -p bin lib lambda/{auth,courses,progress} test config

# Create config/environments.ts
cat > config/environments.ts << 'EOL'
export const environments = {
  dev: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'eu-west-1'
  },
  prod: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'eu-west-1'
  }
};
EOL

# Create bin/lughati-cloud.ts
cat > bin/lughati-cloud.ts << 'EOL'
#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { LughatiStack } from '../lib/lughati-stack';
import { environments } from '../config/environments';

const app = new cdk.App();
const env = app.node.tryGetContext('env') || 'dev';

new LughatiStack(app, `LughatiStack-${env}`, {
  env: environments[env],
  description: 'Lughati Arabic Learning Platform Infrastructure',
});
EOL

# Create lib/lughati-stack.ts
cat > lib/lughati-stack.ts << 'EOL'
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as cognito from 'aws-cdk-lib/aws-cognito';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as iam from 'aws-cdk-lib/aws-iam';

export class LughatiStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // S3 bucket for course content
    const coursesBucket = new s3.Bucket(this, 'CoursesBucket', {
      versioned: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      cors: [{
        allowedMethods: [s3.HttpMethods.GET, s3.HttpMethods.PUT],
        allowedOrigins: ['*'],
        allowedHeaders: ['*'],
      }],
    });

    // Cognito User Pool
    const userPool = new cognito.UserPool(this, 'LughatiUserPool', {
      userPoolName: `${id}-users`,
      selfSignUpEnabled: true,
      signInAliases: {
        email: true,
        username: true,
      },
      standardAttributes: {
        givenName: { required: true, mutable: true },
        familyName: { required: true, mutable: true },
      },
      customAttributes: {
        'userType': new cognito.StringAttribute({ mutable: true }),
      },
      passwordPolicy: {
        minLength: 8,
        requireLowercase: true,
        requireUppercase: true,
        requireDigits: true,
        requireSymbols: true,
      },
    });

    // User Pool Client
    const userPoolClient = new cognito.UserPoolClient(this, 'LughatiUserPoolClient', {
      userPool,
      generateSecret: false,
      authFlows: {
        adminUserPassword: true,
        userPassword: true,
        userSrp: true,
      },
    });

    // DynamoDB Tables
    const progressTable = new dynamodb.Table(this, 'ProgressTable', {
      partitionKey: { name: 'userId', type: dynamodb.AttributeType.STRING },
      sortKey: { name: 'courseId', type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    const coursesTable = new dynamodb.Table(this, 'CoursesTable', {
      partitionKey: { name: 'courseId', type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Lambda Functions
    const authFunction = new lambda.Function(this, 'AuthFunction', {
      runtime: lambda.Runtime.NODEJS_18_X,
      handler: 'index.handler',
      code: lambda.Code.fromAsset('lambda/auth'),
      environment: {
        USER_POOL_ID: userPool.userPoolId,
        CLIENT_ID: userPoolClient.userPoolClientId,
      },
    });

    const listCoursesFunction = new lambda.Function(this, 'ListCoursesFunction', {
      runtime: lambda.Runtime.NODEJS_18_X,
      handler: 'list-courses.handler',
      code: lambda.Code.fromAsset('lambda/courses'),
      environment: {
        COURSES_BUCKET: coursesBucket.bucketName,
        COURSES_TABLE: coursesTable.tableName,
      },
    });

    const saveProgressFunction = new lambda.Function(this, 'SaveProgressFunction', {
      runtime: lambda.Runtime.NODEJS_18_X,
      handler: 'save-progress.handler',
      code: lambda.Code.fromAsset('lambda/progress'),
      environment: {
        PROGRESS_TABLE: progressTable.tableName,
      },
    });

    // Permissions
    coursesBucket.grantRead(listCoursesFunction);
    coursesTable.grantReadWriteData(listCoursesFunction);
    progressTable.grantReadWriteData(saveProgressFunction);

    // API Gateway
    const api = new apigateway.RestApi(this, 'LughatiApi', {
      restApiName: 'Lughati API',
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: apigateway.Cors.DEFAULT_HEADERS,
      },
    });

    // API Resources and Methods
    const auth = api.root.addResource('auth');
    auth.addMethod('POST', new apigateway.LambdaIntegration(authFunction));

    const courses = api.root.addResource('courses');
    courses.addMethod('GET', new apigateway.LambdaIntegration(listCoursesFunction));

    const progress = api.root.addResource('progress');
    progress.addMethod('POST', new apigateway.LambdaIntegration(saveProgressFunction));

    // Stack Outputs
    new cdk.CfnOutput(this, 'UserPoolId', { value: userPool.userPoolId });
    new cdk.CfnOutput(this, 'UserPoolClientId', { value: userPoolClient.userPoolClientId });
    new cdk.CfnOutput(this, 'ApiUrl', { value: api.url });
    new cdk.CfnOutput(this, 'BucketName', { value: coursesBucket.bucketName });
  }
}
EOL

# Create Lambda functions
# Auth Lambda
cat > lambda/auth/index.js << 'EOL'
const AWS = require('aws-sdk');
const cognito = new AWS.CognitoIdentityServiceProvider();

exports.handler = async (event) => {
  try {
    const body = JSON.parse(event.body);
    const { action, username, password, email } = body;

    switch (action) {
      case 'signup':
        const signupParams = {
          ClientId: process.env.CLIENT_ID,
          Username: username,
          Password: password,
          UserAttributes: [
            { Name: 'email', Value: email }
          ]
        };
        await cognito.signUp(signupParams).promise();
        return {
          statusCode: 200,
          body: JSON.stringify({ message: 'User registered successfully' })
        };

      case 'login':
        const loginParams = {
          AuthFlow: 'USER_PASSWORD_AUTH',
          ClientId: process.env.CLIENT_ID,
          AuthParameters: {
            USERNAME: username,
            PASSWORD: password
          }
        };
        const authResult = await cognito.initiateAuth(loginParams).promise();
        return {
          statusCode: 200,
          body: JSON.stringify({ token: authResult.AuthenticationResult.IdToken })
        };

      default:
        return {
          statusCode: 400,
          body: JSON.stringify({ error: 'Invalid action' })
        };
    }
  } catch (error) {
    console.error('Error:', error);
    return {
      statusCode: 500,
      body: JSON.stringify({ error: error.message })
    };
  }
};
EOL

# Courses Lambda
cat > lambda/courses/list-courses.js << 'EOL'
const AWS = require('aws-sdk');
const s3 = new AWS.S3();
const dynamodb = new AWS.DynamoDB.DocumentClient();

exports.handler = async (event) => {
  try {
    const params = {
      TableName: process.env.COURSES_TABLE,
    };
    
    const result = await dynamodb.scan(params).promise();
    
    return {
      statusCode: 200,
      body: JSON.stringify(result.Items),
    };
  } catch (error) {
    console.error('Error:', error);
    return {
      statusCode: 500,
      body: JSON.stringify({ error: 'Failed to list courses' }),
    };
  }
};
EOL

# Progress Lambda
cat > lambda/progress/save-progress.js << 'EOL'
const AWS = require('aws-sdk');
const dynamodb = new AWS.DynamoDB.DocumentClient();

exports.handler = async (event) => {
  try {
    const { userId, courseId, progress } = JSON.parse(event.body);
    
    const params = {
      TableName: process.env.PROGRESS_TABLE,
      Item: {
        userId,
        courseId,
        progress,
        timestamp: new Date().toISOString()
      }
    };
    
    await dynamodb.put(params).promise();
    
    return {
      statusCode: 200,
      body: JSON.stringify({ message: 'Progress saved successfully' }),
    };
  } catch (error) {
    console.error('Error:', error);
    return {
      statusCode: 500,
      body: JSON.stringify({ error: 'Failed to save progress' }),
    };
  }
};
EOL

# Create package.json if it doesn't exist
if [ ! -f package.json ]; then
  echo -e "${GREEN}Creating package.json...${NC}"
  cat > package.json << 'EOL'
{
  "name": "lughati-cloud-infra",
  "version": "0.1.0",
  "bin": {
    "lughati-cloud-infra": "bin/lughati-cloud.js"
  },
  "scripts": {
    "build": "tsc",
    "watch": "tsc -w",
    "test": "jest",
    "cdk": "cdk",
    "deploy": "cdk deploy",
    "deploy:dev": "cdk deploy --context env=dev",
    "deploy:prod": "cdk deploy --context env=prod"
  },
  "devDependencies": {
    "@types/jest": "^29.5.1",
    "@types/node": "20.1.0",
    "jest": "^29.5.0",
    "ts-jest": "^29.1.0",
    "aws-cdk": "2.77.0",
    "ts-node": "^10.9.1",
    "typescript": "~5.0.4"
  },
  "dependencies": {
    "aws-cdk-lib": "2.77.0",
    "constructs": "^10.0.0",
    "source-map-support": "^0.5.21"
  }
}
EOL
fi

# Create tsconfig.json
cat > tsconfig.json << 'EOL'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": [
      "es2020"
    ],
    "declaration": true,
    "strict": true,
    "noImplicitAny": true,
    "strictNullChecks": true,
    "noImplicitThis": true,
    "alwaysStrict": true,
    "noUnusedLocals": false,
    "noUnusedParameters": false,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": false,
    "inlineSourceMap": true,
    "inlineSources": true,
    "experimentalDecorators": true,
    "strictPropertyInitialization": false,
    "typeRoots": [
      "./node_modules/@types"
    ],
    "outDir": "dist"
  },
  "exclude": [
    "node_modules",
    "cdk.out"
  ]
}
EOL

# Create or update .gitignore
cat > .gitignore << 'EOL'
*.js
!jest.config.js
*.d.ts
node_modules
.cdk.staging
cdk.out
.env
*.log
.DS_Store
dist/
.idea/
.vscode/
EOL

# Create cdk.json
cat > cdk.json << 'EOL'
{
  "app": "npx ts-node --prefer-ts-exts bin/lughati-cloud.ts",
  "watch": {
    "include": [
      "**"
    ],
    "exclude": [
      "README.md",
      "cdk*.json",
      "**/*.d.ts",
      "**/*.js",
      "tsconfig.json",
      "package*.json",
      "yarn.lock",
      "node_modules",
      "test"
    ]
  },
  "context": {
    "@aws-cdk/aws-lambda:recognizeLayerVersion": true,
    "@aws-cdk/core:checkSecretUsage": true,
    "@aws-cdk/core:target-partitions": [
      "aws",
      "aws-cn"
    ],
    "@aws-cdk-containers/ecs-service-extensions:enableDefaultLogDriver": true,
    "@aws-cdk/aws-ec2:uniqueImdsv2TemplateName": true,
    "@aws-cdk/aws-ecs:arnFormatIncludesClusterName": true,
    "@aws-cdk/aws-iam:minimizePolicies": true,
    "@aws-cdk/core:validateSnapshotRemovalPolicy": true,
    "@aws-cdk/aws-codepipeline:crossAccountKeyAliasStackSafeResourceName": true,
    "@aws-cdk/aws-s3:createDefaultLoggingPolicy": true,
    "@aws-cdk/aws-sns-subscriptions:restrictSqsDescryption": true,
    "@aws-cdk/aws-apigateway:disableCloudWatchRole": true,
    "@aws-cdk/core:enablePartitionLiterals": true,
    "@aws-cdk/aws-events:eventsTargetQueue

SseAlias": true,
    "@aws-cdk/aws-iam:standardizedServicePrincipals": true,
    "@aws-cdk/aws-ecs:disableExplicitDeploymentControllerForCircuitBreaker": true,
    "@aws-cdk/aws-iam:importedRoleStackSafeDefaultPolicyName": true,
    "@aws-cdk/aws-s3:serverAccessLogsUseBucketPolicy": true,
    "@aws-cdk/aws-route53-patters:useCertificate": true,
    "@aws-cdk/customresources:installLatestAwsSdkDefault": false
  }
}
EOL

# Update README.md
cat > README.md << 'EOL'

