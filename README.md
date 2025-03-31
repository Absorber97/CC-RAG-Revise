# 🚀 SFBU RAG Chatbot - Kubernetes Deployment

This repository contains a Streamlit application that uses RAG (Retrieval-Augmented Generation) with Weaviate as a vector database to create a chatbot capable of answering questions based on uploaded documents.

## 📋 Table of Contents
- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Environment Variables](#environment-variables)
- [Deployment Options](#deployment-options)
  - [Initial Deployment](#initial-deployment)
  - [Update Existing Deployment](#update-existing-deployment)
  - [Load Balancing with Ingress](#load-balancing-with-ingress)
- [Application Usage](#application-usage)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)
- [Development](#development)

## 🔍 Overview

This application leverages OpenAI's language models and Weaviate's vector database capabilities to create a document-based question answering system. It processes various document formats, embeds them into vector representations, and uses retrieval-augmented generation to provide accurate answers based on the uploaded content.

## ✨ Features

- **Document Processing**: Upload and process various document types (PDF, text, web pages, or Wikipedia articles)
- **Vector Embedding**: Stores document chunks as vector embeddings using OpenAI embeddings
- **RAG Implementation**: Uses Retrieval-Augmented Generation for accurate and relevant answers
- **Kubernetes Deployment**: Scalable deployment with multiple replicas
- **Monitoring**: Integrated Prometheus and Grafana monitoring
- **Ingress Support**: Advanced deployment with NGINX Ingress Controller and Let's Encrypt SSL

## 🏗️ Architecture

The application is deployed with the following components:

- **Streamlit Frontend**: User interface for document upload and question answering
- **Weaviate Vector Database**: Stores document embeddings for efficient retrieval
- **OpenAI Integration**: Provides embeddings and language model capabilities
- **Kubernetes Resources**:
  - **Deployment**: Runs 3 replica pods, all configured as writers
  - **Service**: Exposes the application via a LoadBalancer
  - **Secrets**: Stores sensitive API keys and connection information
  - **Monitoring**: Prometheus and Grafana for application monitoring
  - **Ingress**: Optional NGINX Ingress Controller for routing and SSL

Each pod is configured with:
- Readiness and liveness probes
- Resource limits and requests
- Environment variables loaded from Kubernetes secrets

## 🔧 Prerequisites

- Docker installed on your local machine (optional for local testing)
- Google Cloud SDK (gcloud) installed and configured
- kubectl installed and configured
- A GKE (Google Kubernetes Engine) cluster created
- Access to Google Container Registry (GCR)
- OpenAI API key
- Weaviate Cloud instance (or self-hosted Weaviate) with API key

## 🔐 Environment Variables

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

## 🚢 Deployment Options

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

1. Run the update script:

```bash
./scripts/update.sh
```

This will build a new image with a timestamp tag, push it to GCR, and update the deployment.

### Automated CI/CD with GitHub Actions

This repository is configured with GitHub Actions for continuous integration and deployment. The workflow automatically builds, publishes, and deploys the application when changes are pushed to the main branch.

#### Setting Up GitHub Actions

1. Add the following secrets to your GitHub repository:
   - `GCP_PROJECT_ID`: Your Google Cloud project ID
   - `GKE_CLUSTER`: Your GKE cluster name
   - `GKE_ZONE`: Your GKE cluster zone
   - `GCP_SA_KEY`: Your GCP service account key (JSON format)
   - `OPENAI_API_KEY`: Your OpenAI API key
   - `WEAVIATE_URL`: Your Weaviate instance URL
   - `WEAVIATE_API_KEY`: Your Weaviate API key

2. Push changes to the main branch to trigger the deployment pipeline.

3. You can also manually trigger deployments from the "Actions" tab in your GitHub repository.

#### Required GCP Service Account Permissions

The service account used for GitHub Actions (referenced by `GCP_SA_KEY`) needs the following roles:

1. **Kubernetes Engine Admin** (`roles/container.admin`): Allows management of Kubernetes clusters and their Kubernetes API objects
2. **Storage Admin** (`roles/storage.admin`): Provides access to Google Container Registry for pushing and pulling images
3. **Service Account User** (`roles/iam.serviceAccountUser`): Allows the service account to impersonate service accounts
4. **Artifact Registry Administrator** (`roles/artifactregistry.admin`): Full control of Artifact Registry repositories (if using Artifact Registry)

You can create and configure a service account with these permissions using the following commands:

```bash
# Create a service account for GitHub Actions
export PROJECT_ID=your-project-id
export SA_NAME=github-actions-cicd

# Create the service account
gcloud iam service-accounts create $SA_NAME --display-name="GitHub Actions CI/CD"

# Get the service account email
export SA_EMAIL=$(gcloud iam service-accounts list --filter="displayName:GitHub Actions CI/CD" --format='value(email)')

# Grant the necessary roles
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$SA_EMAIL" --role="roles/container.admin"
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$SA_EMAIL" --role="roles/storage.admin"
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$SA_EMAIL" --role="roles/iam.serviceAccountUser"
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$SA_EMAIL" --role="roles/artifactregistry.admin"

# Create and download the JSON key file
gcloud iam service-accounts keys create key.json --iam-account=$SA_EMAIL

# Base64 encode the key for GitHub Secrets (Linux/macOS)
cat key.json | base64
```

Keep the JSON key secure and use it as the value for the `GCP_SA_KEY` secret in your GitHub repository.

#### Deployment with Monitoring

To deploy the application with monitoring, include `deploy-monitoring` in your commit message:

```bash
git commit -m "feature: add new functionality [deploy-monitoring]"
```

This will deploy both the application and the monitoring stack.

### Load Balancing with Ingress

This repository includes an advanced deployment option using Kubernetes Ingress for load balancing and SSL termination.

#### Features

- **NGINX Ingress Controller**: Routes external traffic to the application
- **Let's Encrypt SSL**: Automatic SSL certificate generation and renewal
- **nip.io Domain**: Uses nip.io service for easy DNS resolution without domain registration
- **Load Balancing**: Routes traffic across multiple application instances

#### Ingress Deployment

To deploy the application with Ingress support:

1. Make the Ingress deployment script executable:

```bash
chmod +x scripts/ingress-setup.sh
```

2. Run the Ingress deployment script:

```bash
./scripts/ingress-setup.sh
```

This will:
- Deploy the NGINX Ingress Controller
- Set up cert-manager for Let's Encrypt integration
- Deploy the application and service
- Configure the Ingress resource with the nip.io domain
- Obtain SSL certificates automatically

#### Accessing the Application with Ingress

After deployment, the script will output the URL where your application is accessible, usually in the format:

```
https://streamlit-app.[LOAD_BALANCER_IP].nip.io
```

## 📊 Monitoring

The application includes a comprehensive monitoring stack based on Prometheus and Grafana.

### Monitoring Components

- **Prometheus**: Collects metrics from the application, nodes, and Kubernetes
- **Grafana**: Visualizes the collected metrics with pre-configured dashboards
- **Node Exporter**: Collects hardware and OS metrics
- **Kube State Metrics**: Collects Kubernetes state metrics

### Deploying Monitoring

To deploy the monitoring stack:

```bash
chmod +x scripts/monitoring-setup.sh
./scripts/monitoring-setup.sh
```

### Initializing Grafana

A one-time setup script is provided to configure Grafana with default dashboards and data sources:

```bash
chmod +x scripts/grafana-init.sh
./scripts/grafana-init.sh
```

This script will:
1. Set up port forwarding to Grafana
2. Configure the Prometheus data source
3. Import a Streamlit application dashboard with CPU, memory, and request metrics
4. Set organization preferences

After running the script, Grafana will be accessible at http://localhost:3000 with default credentials (admin/admin).

### Accessing Monitoring Dashboards

1. Forward Prometheus port:
   ```bash
   kubectl port-forward -n monitoring service/prometheus-service 9090:9090
   ```
   Access at: http://localhost:9090

2. Forward Grafana port:
   ```bash
   kubectl port-forward -n monitoring service/grafana-service 3000:80
   ```
   Access at: http://localhost:3000
   Default credentials: admin/admin

## 💻 Application Usage

Once deployed, access the application through the LoadBalancer IP address or the Ingress URL. You can:

1. Upload documents (PDF, text, web pages, or Wikipedia articles)
2. Ask questions about the uploaded documents
3. View and interact with the chat history

The application leverages RAG to provide accurate answers based on the content of the uploaded documents.

## 🔍 Troubleshooting

### Pod Issues

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

### Ingress Issues

1. Check Ingress status:
```bash
kubectl get ingress
```

2. Check certificate status:
```bash
kubectl get certificate
```

3. Check Ingress controller logs:
```bash
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller
```

4. Check cert-manager logs:
```bash
kubectl logs -n cert-manager deployment/cert-manager
```

5. Verify TLS secret creation:
```bash
kubectl get secret streamlit-app-tls
```

### Monitoring Issues

1. Check monitoring stack status:
```bash
kubectl get pods -n monitoring
```

2. Check Prometheus targets:
```bash
kubectl port-forward -n monitoring service/prometheus-service 9090:9090
# Then visit http://localhost:9090/targets
```

3. Verify Streamlit metrics endpoint:
```bash
kubectl port-forward <streamlit-pod-name> 8501:8501
curl http://localhost:8501/_stcore/metrics
```

4. Reset monitoring if needed:
```bash
./scripts/cleanup-monitoring.sh
./scripts/monitoring-setup.sh
```

## 🛠️ Development

To modify or extend the application:

1. Update `streamlitui.py` for application changes
2. Update Kubernetes configuration in the `kubernetes/` directory if needed
3. Run the update script to deploy your changes

### Local Development

For local testing before deployment:

1. Create a `.env` file with your API keys
2. Install dependencies: `pip install -r requirements.txt`
3. Run the application: `streamlit run streamlitui.py`

### Building Custom Docker Images

If you want to build and use your own Docker image:

1. Modify the Dockerfile as needed
2. Build the image: `docker build -t your-registry/streamlit-app:tag .`
3. Push to your registry: `docker push your-registry/streamlit-app:tag`
4. Update the deployment YAML to use your image 