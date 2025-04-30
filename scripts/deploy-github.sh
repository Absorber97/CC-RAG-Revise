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

# Default tag with timestamp
TAG=${1:-$(date +%Y%m%d-%H%M%S)}

echo "🔧 Building and pushing Streamlit app with tag: $TAG"

# Build the Docker image
echo "🐳 Building Docker image..."
docker build --platform linux/amd64 -t ghcr.io/$GITHUB_USERNAME_LOWER/sfbu-rag-chatbot:$TAG .
docker tag ghcr.io/$GITHUB_USERNAME_LOWER/sfbu-rag-chatbot:$TAG ghcr.io/$GITHUB_USERNAME_LOWER/sfbu-rag-chatbot:latest

# Push the Docker image to GitHub Container Registry
echo "⬆️ Pushing image to GitHub Container Registry..."
docker push ghcr.io/$GITHUB_USERNAME_LOWER/sfbu-rag-chatbot:$TAG
docker push ghcr.io/$GITHUB_USERNAME_LOWER/sfbu-rag-chatbot:latest

echo "✅ Docker image pushed successfully to GitHub Container Registry!"
echo "Image URL: ghcr.io/$GITHUB_USERNAME_LOWER/sfbu-rag-chatbot:$TAG"
echo "Image URL (latest): ghcr.io/$GITHUB_USERNAME_LOWER/sfbu-rag-chatbot:latest" 