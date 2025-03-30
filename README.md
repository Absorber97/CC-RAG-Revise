# SFBU RAG Chatbot - Kubernetes Deployment

This repository contains a Streamlit application that uses RAG (Retrieval-Augmented Generation) with Weaviate as a vector database to create a chatbot capable of answering questions based on uploaded documents.

## Setup and Deployment

### Prerequisites

- Docker installed on your local machine (optional)
- Google Cloud SDK (gcloud) installed and configured
- kubectl installed
- A GKE (Google Kubernetes Engine) cluster created
- Access to Google Container Registry (GCR)

### Environment Variables

Configure the following environment variables in a `.env` file:

```
# API Keys
OPENAI_API_KEY=your_openai_api_key

# Weaviate Configuration
WEAVIATE_URL=your_weaviate_url
WEAVIATE_API_KEY=your_weaviate_api_key

# GCP Configuration
GCP_PROJECT_ID=your_gcp_project_id
GKE_CLUSTER=your_gke_cluster_name
GKE_ZONE=your_gke_zone
```

> **Important**: Make sure your .env file contains valid values for all required variables. The deployment will fail if these are missing or incorrect.

### Initial Deployment

1. Make the deployment scripts executable:

```bash
chmod +x scripts/deploy.sh scripts/update.sh scripts/create-secrets.sh
```

2. Run the deployment script:

```bash
./scripts/deploy.sh
```

This will:
- Build the Docker image
- Push it to Google Container Registry
- Properly encode and apply Kubernetes secrets
- Apply Kubernetes configurations
- Deploy the application to your GKE cluster

### Update Existing Deployment

To update your deployment after making changes:

1. Make the update script executable:

```bash
chmod +x scripts/update.sh
```

2. Run the update script:

```bash
./scripts/update.sh
```

This will build a new image with a timestamp tag, push it to GCR, and update the deployment.

## Architecture

The application is deployed with the following components:

- **Deployment**: Runs 3 replica pods, all configured as writers
- **Service**: Exposes the application via a LoadBalancer
- **Secrets**: Stores sensitive API keys and connection information

Each pod is configured with:
- Readiness and liveness probes
- Resource limits and requests
- Environment variables loaded from Kubernetes secrets

## Usage

Once deployed, access the application through the LoadBalancer IP address. You can:

1. Upload documents (PDF, text, web pages, or Wikipedia articles)
2. Ask questions about the uploaded documents
3. View and interact with the chat history

## Development

To modify or extend the application:

1. Update `streamlitui.py` for application changes
2. Update Kubernetes configuration in the `kubernetes/` directory if needed
3. Run the update script to deploy your changes

## Troubleshooting

If you encounter issues:

1. Check pod logs:
```bash
kubectl logs -l app=streamlit-app
```

2. Check pod status:
```bash
kubectl get pods -l app=streamlit-app
```

3. Check service status:
```bash
kubectl get service streamlit-app
```

4. Verify secrets are properly created:
```bash
kubectl get secrets app-secrets
``` 