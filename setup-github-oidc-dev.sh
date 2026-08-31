#!/usr/bin/env bash
# setup-github-oidc-dev.sh
# Creates a GitHub OIDC identity provider (account-wide, one-time) and a
# scoped IAM role that GitHub Actions can assume to run Terraform.
#
# Usage:
#   bash setup-github-oidc-dev.sh --profile dev-account --env dev   --branch main
#   bash setup-github-oidc-dev.sh --profile stg-account --env staging --branch staging

set -euo pipefail

# --- Parse arguments ---
AWS_PROFILE=""
ENV_NAME="dev"
TARGET_BRANCH="main"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) AWS_PROFILE="$2"; shift 2 ;;
    --env)     ENV_NAME="$2";    shift 2 ;;
    --branch)  TARGET_BRANCH="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$AWS_PROFILE" ]; then
  echo "Error: --profile is required (e.g. --profile dev-account)" >&2
  exit 1
fi

AWS="aws --profile $AWS_PROFILE"

GITHUB_ORG_REPO="lmngxn/CICD-first-build"
ROLE_NAME="github-actions-terraform-${ENV_NAME}"
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
EXISTING_PROVIDER=$($AWS iam list-open-id-connect-providers \
  --query "OpenIDConnectProviderList[?contains(Arn, 'token.actions.githubusercontent.com')].Arn" \
  --output text)

if [ -n "$EXISTING_PROVIDER" ]; then
  echo "OIDC provider already exists: $EXISTING_PROVIDER"
  PROVIDER_ARN="$EXISTING_PROVIDER"
else
  echo "Creating GitHub OIDC provider..."
  PROVIDER_ARN=$($AWS iam create-open-id-connect-provider \
    --url "$PROVIDER_URL" \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list "$THUMBPRINT" \
    --query "OpenIDConnectProviderArn" \
    --output text)
  echo "Created: $PROVIDER_ARN"
fi

# --- 2. Trust policy scoped to this repo using numeric IDs ---
ACCOUNT_ID=$($AWS sts get-caller-identity --query Account --output text)

TRUST_POLICY_FILE="trust-policy-${ENV_NAME}.json"
INLINE_POLICY_FILE="${ENV_NAME}-policy.json"

cat > "$TRUST_POLICY_FILE" <<EOF
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
$AWS iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document "file://${TRUST_POLICY_FILE}" \
  --description "GitHub Actions - Terraform apply - ${ENV_NAME} (${GITHUB_ORG_REPO}, branch: ${TARGET_BRANCH})"

# --- 4. Scoped access: DynamoDB, Lambda, API Gateway, IAM (role mgmt only),
#        CloudWatch Logs, S3 — not full AdministratorAccess.
cat > "$INLINE_POLICY_FILE" <<'EOF'
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
POLICY_ARN=$($AWS iam create-policy \
  --policy-name "${ROLE_NAME}-policy" \
  --policy-document "file://${INLINE_POLICY_FILE}" \
  --description "Scoped ${ENV_NAME} CI policy: DynamoDB, Lambda, API Gateway, IAM (role mgmt), CloudWatch Logs, S3" \
  --query "Policy.Arn" \
  --output text)

echo "Attaching $POLICY_ARN..."
$AWS iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn "$POLICY_ARN"

ROLE_ARN=$($AWS iam get-role --role-name "$ROLE_NAME" --query "Role.Arn" --output text)

echo ""
echo "Done. [${ENV_NAME}]"
echo "Role ARN: $ROLE_ARN"
echo ""
echo "Add this to your GitHub Actions workflow (${ENV_NAME} job):"
cat <<EOF
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: $ROLE_ARN
          aws-region: ap-southeast-1
EOF

rm -f "$TRUST_POLICY_FILE" "$INLINE_POLICY_FILE"