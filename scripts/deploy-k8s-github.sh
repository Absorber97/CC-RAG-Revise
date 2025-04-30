#!/bin/bash
set -e

# Load environment variables
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

# Check for GitHub username
if [ -z "$GITHUB_USERNAME" ]; then
  echo "Error: GITHUB_USERNAME not set in .env file"
  echo "Please add GITHUB_USERNAME=your-github-username to your .env file"
  exit 1
fi

# Convert GitHub username to lowercase for Docker compatibility
GITHUB_USERNAME_LOWER=$(echo "$GITHUB_USERNAME" | tr '[:upper:]' '[:lower:]')

echo "🚀 Deploying application to Kubernetes using GitHub Container Registry..."

# Create generated directory if it doesn't exist
mkdir -p .generated

# Process the GitHub deployment file with the lowercase username
echo "🔄 Processing Kubernetes deployment file with GitHub username..."
export GITHUB_USERNAME_LOWER
cat kubernetes/github-deployment.yaml | envsubst > .generated/github-deployment.yaml

# Create the GitHub Container Registry secret for Kubernetes
echo "🔐 Creating GitHub Container Registry secret for Kubernetes..."

# Check if we have GitHub PAT in env
if [ -z "$GITHUB_PAT" ]; then
  echo "❗ GitHub Personal Access Token (GITHUB_PAT) not found in .env file"
  echo "Please provide your GitHub PAT:"
  read -s GITHUB_PAT
  echo ""
  
  if [ -z "$GITHUB_PAT" ]; then
    echo "❌ No GitHub PAT provided. Exiting."
    exit 1
  fi
fi

# Create or update the Docker registry secret
kubectl create secret docker-registry github-container-registry \
  --docker-server=ghcr.io \
  --docker-username=$GITHUB_USERNAME \
  --docker-password=$GITHUB_PAT \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ GitHub Container Registry secret created/updated"

# Run the secrets script if it exists
if [ -f "scripts/create-secrets.sh" ]; then
  echo "🔐 Creating application secrets..."
  ./scripts/create-secrets.sh
fi

# Apply the generated deployment and service files
echo "🚀 Applying Kubernetes resources..."
kubectl apply -f .generated/github-deployment.yaml
kubectl apply -f kubernetes/service.yaml

# Wait for deployment to be ready
echo "⏳ Waiting for deployment to be ready..."
kubectl rollout status deployment/streamlit-app

# Get the service URL
echo "🔍 Getting service URL..."
SERVICE_IP=$(kubectl get service streamlit-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

if [ -n "$SERVICE_IP" ]; then
  echo "✅ Deployment successful! Your application is available at: http://$SERVICE_IP"
else
  echo "⚠️ Service IP not yet available. Please check the service status with: kubectl get service streamlit-app"
fi

echo "✨ Deployment process completed!" 