# 📚 Lughati Cloud Infrastructure

This repository contains the infrastructure code for **Lughati**, an application designed to help children learn Arabic in a fun and interactive way.

Infrastructure is defined using the **AWS Cloud Development Kit (CDK)** in **TypeScript**.

---

## 🧱 Architecture Overview

This project provisions the core cloud services required to support the Lughati application backend:

- **API Gateway** – Exposes RESTful APIs  
- **AWS Lambda** – Handles business logic  
- **DynamoDB / S3** – Stores user data and learning content  
- **Cognito (optional)** – Provides authentication and user management  
- **CloudFront + S3 (optional)** – For hosting the frontend or media assets

---

## 🚀 Getting Started

### Prerequisites

- Node.js (v18+)
- AWS CLI configured with your credentials
- AWS CDK installed:
  ```bash
  npm install -g aws-cdk
  ```

### Setup

1. Install dependencies:
   ```bash
   npm install
   ```

2. Bootstrap your environment (once per AWS account/region):
   ```bash
   cdk bootstrap
   ```

3. Deploy the stack:
   ```bash
   cdk deploy
   ```

---

## 🛠 Project Structure

```
.
├── bin/                  # CDK entry point
├── lib/                  # Main infrastructure stacks
├── scripts/              # Setup and helper scripts
├── package.json          # Dependencies and scripts
├── tsconfig.json         # TypeScript configuration
├── cdk.json              # CDK project config
└── README.md             # This file
```

---

## 📄 License

MIT License © 2025 Amir Zidi

---

## 📬 Contact

For any questions or suggestions, feel free to reach out or open an issue.
