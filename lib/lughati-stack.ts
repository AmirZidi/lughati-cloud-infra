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
