#!/bin/sh

set -e

if [ -z "$AWS_S3_BUCKET" ]; then
  echo "AWS_S3_BUCKET is not set. Quitting."
  exit 1
fi

if [ -z "$AWS_ACCESS_KEY_ID" ]; then
  echo "AWS_ACCESS_KEY_ID is not set. Quitting."
  exit 1
fi

if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
  echo "AWS_SECRET_ACCESS_KEY is not set. Quitting."
  exit 1
fi

# Default to us-east-1 if AWS_REGION not set.
if [ -z "$AWS_REGION" ]; then
  AWS_REGION="us-east-1"
fi

# Override default AWS endpoint if user sets AWS_S3_ENDPOINT.
if [ -n "$AWS_S3_ENDPOINT" ]; then
  ENDPOINT_APPEND="--endpoint-url $AWS_S3_ENDPOINT"
fi

# Append date to index.html
echo $'\n<!-- Build: '${GITHUB_SHA:-[none]}' '$(date -u)' -->' >> ${SOURCE_DIR:-.}/index.html

# Create a dedicated profile for this action to avoid conflicts
# with past/future actions.
# https://github.com/jakejarvis/s3-sync-action/issues/1
aws configure --profile s3-sync-action <<-EOF > /dev/null 2>&1
${AWS_ACCESS_KEY_ID}
${AWS_SECRET_ACCESS_KEY}
${AWS_REGION}
text
EOF

# Sync using our dedicated profile and suppress verbose messages.
# All other flags are optional via the `args:` directive.
sh -c "aws s3 sync ${SOURCE_DIR:-.} s3://${AWS_S3_BUCKET}/${DEST_DIR} \
              --profile s3-sync-action \
              --no-progress \
              ${ENDPOINT_APPEND} $*"
              
if [ -n "$AWS_CF_ID" ]; then
  sh -c "aws cloudfront create-invalidation --distribution-id ${AWS_CF_ID} --paths \"/*\""
fi

# Set far expire headers for static files
if [ -n "$EXPIRE_HEADERS" ]; then
  aws s3 cp s3://${AWS_S3_BUCKET}/ s3://${AWS_S3_BUCKET}/ --exclude "*" \
    --include "*.css" \
    --include "*.js" \
    --include "*.svg" \
    --include "*.png" \
    --include "*.jpg" \
    --include "*.webp" \
    --include "*.woff2" \
  --recursive --metadata-directive REPLACE --expires 2100-01-01T00:00:00Z --acl public-read \
  --cache-control max-age=2592000,public
fi

# Clear out credentials after we're done.
# We need to re-run `aws configure` with bogus input instead of
# deleting ~/.aws in case there are other credentials living there.
# https://forums.aws.amazon.com/thread.jspa?threadID=148833
aws configure --profile s3-sync-action <<-EOF > /dev/null 2>&1
null
null
null
text
EOF
