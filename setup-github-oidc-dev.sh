#!/usr/bin/env bash
# setup-github-oidc-dev.sh
# Creates a GitHub OIDC identity provider (account-wide, one-time) and a
# dev-scoped IAM role that GitHub Actions can assume to run Terraform.
#
# Assumes: repo = lmngxn/CICD-first-build, dev branch = main
# Change GITHUB_ORG_REPO / DEV_BRANCH below if either is different.

set -euo pipefail

GITHUB_ORG_REPO="lmngxn/CICD-first-build"
DEV_BRANCH="main"
ROLE_NAME="github-actions-terraform-dev"
PROVIDER_URL="https://token.actions.githubusercontent.com"
THUMBPRINT="227203b5317f3818cab5b5ce596132bf36748c0e"

# --- 0. Fetch numeric GitHub user and repo IDs via the public API ---
# GitHub's OIDC sub claim uses the format:
#   repo:<owner>@<user-id>/<repo>@<repo-id>:<event>
# so we must embed the numeric IDs in the trust policy condition.
GITHUB_USER="${GITHUB_ORG_REPO%%/*}"
GITHUB_REPO="${GITHUB_ORG_REPO##*/}"

echo "Fetching GitHub numeric IDs for ${GITHUB_ORG_REPO}..."
USER_ID=$(curl -sf "https://api.github.com/users/${GITHUB_USER}" | grep -m1 '"id":' | grep -o '[0-9]*')
REPO_ID=$(curl -sf "https://api.github.com/repos/${GITHUB_ORG_REPO}" | grep -m1 '"id":' | grep -o '[0-9]*')

if [ -z "$USER_ID" ] || [ -z "$REPO_ID" ]; then
  echo "Error: could not fetch GitHub IDs. Check that the repo is public or set GITHUB_TOKEN." >&2
  exit 1
fi

echo "  User ID : ${USER_ID}"
echo "  Repo ID : ${REPO_ID}"

GITHUB_SUB="repo:${GITHUB_USER}@${USER_ID}/${GITHUB_REPO}@${REPO_ID}:*"

# --- 1. OIDC provider (skip if one already exists for this URL) ---
EXISTING_PROVIDER=$(aws iam list-open-id-connect-providers \
  --query "OpenIDConnectProviderList[?contains(Arn, 'token.actions.githubusercontent.com')].Arn" \
  --output text)

if [ -n "$EXISTING_PROVIDER" ]; then
  echo "OIDC provider already exists: $EXISTING_PROVIDER"
  PROVIDER_ARN="$EXISTING_PROVIDER"
else
  echo "Creating GitHub OIDC provider..."
  PROVIDER_ARN=$(aws iam create-open-id-connect-provider \
    --url "$PROVIDER_URL" \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list "$THUMBPRINT" \
    --query "OpenIDConnectProviderArn" \
    --output text)
  echo "Created: $PROVIDER_ARN"
fi

# --- 2. Trust policy scoped to this repo using numeric IDs ---
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

cat > trust-policy-dev.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "${GITHUB_SUB}"
        }
      }
    }
  ]
}
EOF

# --- 3. Create the role ---
echo "Creating role $ROLE_NAME..."
aws iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document file://trust-policy-dev.json \
  --description "GitHub Actions - Terraform apply - dev (${GITHUB_ORG_REPO}, branch: $DEV_BRANCH)"

# --- 4. Scoped access: DynamoDB, Lambda, API Gateway, IAM (role mgmt only),
#        CloudWatch Logs, S3 — not full AdministratorAccess.
cat > dev-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DynamoDBFullAccess",
      "Effect": "Allow",
      "Action": "dynamodb:*",
      "Resource": "*"
    },
    {
      "Sid": "LambdaFullAccess",
      "Effect": "Allow",
      "Action": "lambda:*",
      "Resource": "*"
    },
    {
      "Sid": "ApiGatewayFullAccess",
      "Effect": "Allow",
      "Action": "apigateway:*",
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchLogsFullAccess",
      "Effect": "Allow",
      "Action": "logs:*",
      "Resource": "*"
    },
    {
      "Sid": "S3FullAccess",
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": "*"
    },
    {
      "Sid": "IAMRoleManagementForLambda",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:ListRoles",
        "iam:ListRolePolicies",
        "iam:ListAttachedRolePolicies",
        "iam:GetRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:PassRole"
      ],
      "Resource": "*"
    }
  ]
}
EOF
 
echo "Creating scoped policy ${ROLE_NAME}-policy..."
POLICY_ARN=$(aws iam create-policy \
  --policy-name "${ROLE_NAME}-policy" \
  --policy-document file://dev-policy.json \
  --description "Scoped dev CI policy: DynamoDB, Lambda, API Gateway, IAM (role mgmt), CloudWatch Logs, S3" \
  --query "Policy.Arn" \
  --output text)
 
echo "Attaching $POLICY_ARN..."
aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn "$POLICY_ARN"
 
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query "Role.Arn" --output text)

echo ""
echo "Done."
echo "Role ARN: $ROLE_ARN"
echo ""
echo "Add this to your GitHub Actions workflow:"
cat <<EOF
permissions:
  id-token: write
  contents: read

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: $ROLE_ARN
          aws-region: ap-southeast-1
EOF

rm -f trust-policy-dev.json