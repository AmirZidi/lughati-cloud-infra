#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';

import { LughatiStack } from '../lib/lughati-stack';
import { LughatiApiStack } from '../lib/lughati-cloud-api-stack'; // 👈 nouvelle stack

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

new LughatiStack(app, `LughatiStack-${envName}`, {
  env: envs[envName],
  description: 'Lughati Arabic Learning Platform Infrastructure',
});

new LughatiApiStack(app, `LughatiApiStack-${envName}`, {
  env: envs[envName] // 👈 très important
});
