#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';

import { LughatiStack } from '../lib/lughati-stack';
import { LughatiApiStack } from '../lib/lughati-cloud-api-stack';
import { LughatiAuthStack } from '../lib/lughati-auth-stack';

const app = new cdk.App();
const envName = app.node.tryGetContext('env') || 'dev';

const envs = {
  dev: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'eu-west-1'
  },
  prod: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'eu-west-1'
  }
} as const;

type EnvName = keyof typeof envs;

if (!(envName in envs)) {
  throw new Error(`Invalid environment: ${envName}`);
}

// 💠 Stack principale
new LughatiStack(app, `LughatiStack-${envName}`, {
  env: envs[envName],
  description: 'Lughati Arabic Learning Platform Infrastructure',
});

// 🔐 Stack Cognito
const authStack = new LughatiAuthStack(app, `LughatiAuthStack-${envName}`, {
  env: envs[envName]
});

// 🌐 Stack API avec userPool (et authorizer interne)
new LughatiApiStack(app, `LughatiApiStack-${envName}`, {
  env: envs[envName],
  userPool: authStack.userPool // ✅ c'est ce qu'on passe maintenant
});
