#!/bin/bash
set -e

# Load environment variables
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

# Check if required environment variables are set
if [ -z "$GCP_PROJECT_ID" ] || [ -z "$GKE_CLUSTER" ] || [ -z "$GKE_ZONE" ]; then
  echo "Error: Missing required environment variables (GCP_PROJECT_ID, GKE_CLUSTER, GKE_ZONE)"
  echo "Please check your .env file."
  exit 1
fi

# Make scripts executable
chmod +x scripts/create-secrets.sh

# Default tag
TAG=${1:-latest}

echo "🔧 Building and deploying Streamlit app with tag: $TAG"

# Build the Docker image with platform specification for GKE compatibility
echo "🐳 Building Docker image..."
docker build --platform linux/amd64 -t gcr.io/${GCP_PROJECT_ID}/streamlit-app:${TAG} .

# Push the Docker image to Google Container Registry
echo "⬆️ Pushing image to Google Container Registry..."
docker push gcr.io/${GCP_PROJECT_ID}/streamlit-app:${TAG}

# Configure kubectl to connect to the GKE cluster
echo "☸️ Configuring kubectl to connect to GKE cluster..."
gcloud container clusters get-credentials ${GKE_CLUSTER} --zone ${GKE_ZONE} --project ${GCP_PROJECT_ID}

# Process Kubernetes manifests with environment variables
echo "🔄 Processing Kubernetes manifests..."
mkdir -p .generated

# Generate the properly encoded secrets
echo "🔒 Creating properly encoded Kubernetes secrets..."
./scripts/create-secrets.sh

# Process other YAML files (don't process secret.yaml as it's handled separately)
for file in kubernetes/*.yaml; do
  if [[ "$file" != *"secret.yaml"* ]]; then
    filename=$(basename "$file")
    cat "$file" | envsubst > ".generated/$filename"
  fi
done

# Apply Kubernetes secrets
echo "🔒 Applying Kubernetes secrets..."
kubectl apply -f .generated/secret.yaml

# Apply Kubernetes manifests
echo "🚀 Deploying application to Kubernetes..."
kubectl apply -f .generated/deployment.yaml
kubectl apply -f .generated/service.yaml

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

# Check pod logs for potential errors
echo "📋 Checking pod logs for errors..."
FIRST_POD=$(kubectl get pods -l app=streamlit-app -o jsonpath="{.items[0].metadata.name}")
if [ -n "$FIRST_POD" ]; then
  kubectl logs $FIRST_POD -c streamlit --tail=50
fi

echo "✨ Deployment process completed!" 