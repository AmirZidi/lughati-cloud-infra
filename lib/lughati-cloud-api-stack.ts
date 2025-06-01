import { Stack, StackProps, RemovalPolicy } from 'aws-cdk-lib'; // 👈 ajoute RemovalPolicy ici
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as iam from 'aws-cdk-lib/aws-iam';


export class LughatiApiStack extends Stack {
  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);

    const table = new dynamodb.Table(this, 'CoursesTable', {
      partitionKey: { name: 'id', type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: RemovalPolicy.DESTROY // ✅ au lieu de dynamodb.RemovalPolicy

    });

    const createCourseFn = new lambda.Function(this, 'CreateCourseFunction', {
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'handler.handler',
      code: lambda.Code.fromAsset('lambda'),
      environment: {
        TABLE_NAME: table.tableName
      }
    });

    table.grantWriteData(createCourseFn);

    const api = new apigateway.RestApi(this, 'LughatiApi', {
      restApiName: 'Lughati Service',
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS
      }
    });

    const courses = api.root.addResource('courses');
    courses.addMethod('POST', new apigateway.LambdaIntegration(createCourseFn), {
      authorizationType: apigateway.AuthorizationType.NONE // À remplacer plus tard par Cognito
    });
  }
}
