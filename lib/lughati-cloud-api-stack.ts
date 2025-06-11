import { Stack, StackProps, CfnOutput, RemovalPolicy } from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as cognito from 'aws-cdk-lib/aws-cognito';

export interface LughatiApiStackProps extends StackProps {
  userPool: cognito.UserPool;
}

export class LughatiApiStack extends Stack {
  constructor(scope: Construct, id: string, props: LughatiApiStackProps) {
    super(scope, id, props);

    const table = new dynamodb.Table(this, 'CoursesTable', {
      partitionKey: { name: 'id', type: dynamodb.AttributeType.STRING },
      removalPolicy: RemovalPolicy.DESTROY
    });

    const createCourseFn = new lambda.Function(this, 'CreateCourseFunction', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'handler.handler',
      code: lambda.Code.fromAsset('lambda'),
      environment: {
        TABLE_NAME: table.tableName
      }
    });

    table.grantWriteData(createCourseFn);

    const api = new apigateway.RestApi(this, 'LughatiApi', {
      restApiName: 'Lughati Service',
      description: 'Lughati API Gateway'
    });

    const authorizer = new apigateway.CognitoUserPoolsAuthorizer(this, 'LughatiAuthorizer', {
      cognitoUserPools: [props.userPool],
      identitySource: 'method.request.header.Authorization'
    });

    const courses = api.root.addResource('courses');
    courses.addMethod('POST', new apigateway.LambdaIntegration(createCourseFn), {
      authorizationType: apigateway.AuthorizationType.COGNITO,
      authorizer
    });

    new CfnOutput(this, 'LughatiApiEndpoint', {
      value: api.url
    });
  }
}
