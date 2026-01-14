#!/bin/bash
set -e

echo "🍺 The Beer Cave Deployment Script"
echo "=================================="

# Get outputs from Terraform
cd infra
CLOUDFRONT_ID=$(terraform output -raw cloudfront_url | cut -d'.' -f1)
S3_BUCKET=$(terraform output -raw s3_bucket_name)
API_URL=$(terraform output -raw api_url)
cd ..

echo "📦 Building frontend..."
cd site
npm run build
cd ..

echo "☁️  Syncing to S3: $S3_BUCKET"
aws s3 sync site/dist/ s3://$S3_BUCKET/ --delete --profile mvp --region eu-west-2

echo "🔄 Invalidating CloudFront cache..."
DIST_ID=$(cd infra && terraform output -json | jq -r '.cloudfront_url.value' | sed 's/\.cloudfront\.net//' | sed 's/^d/E/')
aws cloudfront create-invalidation --distribution-id E32O4QPRMMAA4N --paths "/*" --profile mvp --region eu-west-2

echo ""
echo "✅ Deployment complete!"
echo "🌐 Site URL: https://$(cd infra && terraform output -raw cloudfront_url)"
echo "🔌 API URL: $API_URL"
echo ""
