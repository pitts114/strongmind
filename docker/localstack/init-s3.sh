#!/bin/bash

# Wait for LocalStack to be ready
echo "Waiting for LocalStack to be ready..."
sleep 2

# Create S3 bucket for user avatars
echo "Creating S3 bucket: user-avatars"
awslocal s3 mb s3://user-avatars

# Set bucket to public-read for testing
echo "Setting bucket policy for user-avatars"
awslocal s3api put-bucket-acl --bucket user-avatars --acl public-read

# List buckets to verify
echo "Verifying S3 buckets:"
awslocal s3 ls

echo "LocalStack S3 initialization complete!"
