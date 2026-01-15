#!/bin/bash
set -e

echo "👤 Creating Admin User..."

# Get variables from Terraform outputs
cd infra
POOL_ID=$(terraform output -raw cognito_user_pool_id)
REGION="eu-west-2" # From variables.tf
PROFILE="mvp"      # From variables.tf
cd ..

EMAIL=$1
PASSWORD=$2

if [ -z "$EMAIL" ] || [ -z "$PASSWORD" ]; then
    echo "Usage: ./scripts/create_admin.sh <email> <password>"
    exit 1
fi

echo "Creating user $EMAIL in pool $POOL_ID..."

aws cognito-idp admin-create-user \
    --user-pool-id "$POOL_ID" \
    --username "$EMAIL" \
    --user-attributes Name=email,Value="$EMAIL" Name=email_verified,Value=true \
    --profile "$PROFILE" \
    --region "$REGION"

aws cognito-idp admin-set-user-password \
    --user-pool-id "$POOL_ID" \
    --username "$EMAIL" \
    --password "$PASSWORD" \
    --permanent \
    --profile "$PROFILE" \
    --region "$REGION"

echo "✅ Admin user created successfully!"
