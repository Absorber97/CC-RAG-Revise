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

# Default tag using timestamp
TAG=${1:-$(date +%Y%m%d-%H%M%S)}

echo "🔄 Updating Streamlit app with tag: $TAG"

# Build the Docker image with platform specification for GKE compatibility
echo "🐳 Building Docker image..."
docker build --platform linux/amd64 -t gcr.io/${GCP_PROJECT_ID}/streamlit-app:${TAG} .

# Tag as latest as well
docker tag gcr.io/${GCP_PROJECT_ID}/streamlit-app:${TAG} gcr.io/${GCP_PROJECT_ID}/streamlit-app:latest

# Push the Docker images to Google Container Registry
echo "⬆️ Pushing images to Google Container Registry..."
docker push gcr.io/${GCP_PROJECT_ID}/streamlit-app:${TAG}
docker push gcr.io/${GCP_PROJECT_ID}/streamlit-app:latest

# Configure kubectl to connect to the GKE cluster
echo "☸️ Configuring kubectl to connect to GKE cluster..."
gcloud container clusters get-credentials ${GKE_CLUSTER} --zone ${GKE_ZONE} --project ${GCP_PROJECT_ID}

# Update the deployment with the new image
echo "🚀 Updating deployment with new image..."
kubectl set image deployment/streamlit-app streamlit=gcr.io/${GCP_PROJECT_ID}/streamlit-app:${TAG}

# Wait for the rollout to complete
echo "⏳ Waiting for rollout to complete..."
kubectl rollout status deployment/streamlit-app

echo "✅ Update completed successfully!"
echo "🔗 Your application is available at the same URL as before." 