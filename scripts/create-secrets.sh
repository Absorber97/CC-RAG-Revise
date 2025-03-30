#!/bin/bash
set -e

# Check if .env file exists
if [ ! -f .env ]; then
  echo "Error: .env file not found!"
  echo "Please create a .env file with OPENAI_API_KEY, WEAVIATE_URL, and WEAVIATE_API_KEY"
  exit 1
fi

# Source the .env file
source .env

# Verify required variables
if [ -z "$OPENAI_API_KEY" ] || [ -z "$WEAVIATE_URL" ] || [ -z "$WEAVIATE_API_KEY" ]; then
  echo "Error: Missing required environment variables"
  echo "Please ensure OPENAI_API_KEY, WEAVIATE_URL, and WEAVIATE_API_KEY are set in your .env file"
  exit 1
fi

# Create a temporary secrets file with base64 encoded values
echo "Creating Kubernetes secrets with proper encoding..."

# Base64 encode the variables (with consideration for different OS)
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS
  OPENAI_API_KEY_BASE64=$(echo -n "$OPENAI_API_KEY" | base64)
  WEAVIATE_URL_BASE64=$(echo -n "$WEAVIATE_URL" | base64)
  WEAVIATE_API_KEY_BASE64=$(echo -n "$WEAVIATE_API_KEY" | base64)
else
  # Linux and others
  OPENAI_API_KEY_BASE64=$(echo -n "$OPENAI_API_KEY" | base64 -w 0)
  WEAVIATE_URL_BASE64=$(echo -n "$WEAVIATE_URL" | base64 -w 0)
  WEAVIATE_API_KEY_BASE64=$(echo -n "$WEAVIATE_API_KEY" | base64 -w 0)
fi

# Create temporary directory for generated files
mkdir -p .generated

# Create the secrets file with actual base64 encoded values
cat kubernetes/secret.yaml | \
  sed "s|OPENAI_API_KEY_BASE64|$OPENAI_API_KEY_BASE64|g" | \
  sed "s|WEAVIATE_URL_BASE64|$WEAVIATE_URL_BASE64|g" | \
  sed "s|WEAVIATE_API_KEY_BASE64|$WEAVIATE_API_KEY_BASE64|g" \
  > .generated/secret.yaml

echo "Secret configuration created successfully at .generated/secret.yaml"
echo "Apply with: kubectl apply -f .generated/secret.yaml" 