#!/bin/bash
set -e

# Color codes for better visibility
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Use a different namespace name to avoid conflicts
INGRESS_NAMESPACE="ingress-nginx-new"

echo -e "${YELLOW}==== Starting Kubernetes Deployment with Ingress ====${NC}"

# Get the GCP project ID from gcloud
GCP_PROJECT_ID=$(gcloud config get-value project)
echo -e "${YELLOW}Using GCP Project ID: ${GREEN}$GCP_PROJECT_ID${NC}"

# Replace the placeholder in deployment.yaml
echo -e "${YELLOW}Updating project ID in deployment.yaml...${NC}"
sed -i.bak "s/\${GCP_PROJECT_ID}/$GCP_PROJECT_ID/g" kubernetes/deployment.yaml

# Clean up any existing resources that might cause issues
echo -e "${YELLOW}Cleaning up any existing ingress resources...${NC}"
kubectl delete ingress streamlit-app-ingress --ignore-not-found=true

# Create required namespaces directly
echo -e "${YELLOW}Creating namespaces...${NC}"
kubectl create namespace $INGRESS_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -

# Download and modify the Ingress manifest to use our new namespace
echo -e "${YELLOW}Downloading NGINX Ingress Controller manifest...${NC}"
curl -s https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.1.0/deploy/static/provider/cloud/deploy.yaml > ingress-nginx-deploy.yaml

# Replace the namespace in the downloaded manifest
echo -e "${YELLOW}Updating namespace in NGINX Ingress Controller manifest...${NC}"
sed -i.bak "s/namespace: ingress-nginx/namespace: $INGRESS_NAMESPACE/g" ingress-nginx-deploy.yaml

# Deploy the modified NGINX Ingress Controller
echo -e "${YELLOW}Deploying NGINX Ingress Controller using modified manifest...${NC}"
kubectl apply -f ingress-nginx-deploy.yaml

# Wait for the NGINX Ingress Controller to be ready
echo -e "${YELLOW}Waiting for NGINX Ingress Controller to be ready...${NC}"
echo -e "${YELLOW}This may take a few minutes...${NC}"
kubectl wait --namespace $INGRESS_NAMESPACE \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s || { 
    echo -e "${RED}Timeout waiting for Ingress Controller. Continuing anyway...${NC}"; 
  }

# Deploy cert-manager CRDs first (required before installing cert-manager)
echo -e "${YELLOW}Installing cert-manager CRDs...${NC}"
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.7.1/cert-manager.crds.yaml

# Then deploy cert-manager
echo -e "${YELLOW}Deploying cert-manager...${NC}"
kubectl apply -f kubernetes/ingress/cert-manager.yaml

# Wait for cert-manager to be ready
echo -e "${YELLOW}Waiting for cert-manager to be ready...${NC}"
kubectl wait --namespace cert-manager \
  --for=condition=ready pod \
  --selector=app=cert-manager \
  --timeout=120s || {
    echo -e "${RED}Timeout waiting for cert-manager. Continuing anyway...${NC}";
  }

# Create secrets from .env file if it exists
echo -e "${YELLOW}Creating Kubernetes secrets from .env file...${NC}"
if [ -f .env ]; then
  python3 fix-secrets.py
else
  echo -e "${YELLOW}No .env file found. Skipping secret creation...${NC}"
fi

# Deploy the application
echo -e "${YELLOW}Deploying the application...${NC}"
kubectl apply -f kubernetes/deployment.yaml
kubectl apply -f kubernetes/service.yaml

# Wait for deployment to be ready
echo -e "${YELLOW}Waiting for application deployment to be ready...${NC}"
kubectl wait --for=condition=available deployment/streamlit-app --timeout=300s || {
  echo -e "${RED}Timeout waiting for application deployment. Continuing anyway...${NC}";
}

# Get the external IP of the service
echo -e "${YELLOW}Getting the Load Balancer IP...${NC}"
echo -e "${YELLOW}This may take a few minutes...${NC}"
attempt=0
max_attempts=30
while true; do
  LOAD_BALANCER_IP=$(kubectl get svc ingress-nginx-controller -n $INGRESS_NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  if [ -n "$LOAD_BALANCER_IP" ]; then
    break
  fi
  attempt=$((attempt+1))
  if [ $attempt -ge $max_attempts ]; then
    echo -e "${RED}Failed to get Load Balancer IP after $max_attempts attempts${NC}"
    echo -e "${RED}Please check your cloud provider settings${NC}"
    exit 1
  fi
  echo -e "${YELLOW}Waiting for Load Balancer IP to be assigned (attempt $attempt/$max_attempts)...${NC}"
  sleep 10
done

echo -e "${GREEN}Load Balancer IP: $LOAD_BALANCER_IP${NC}"

# Update the Ingress configuration with the actual IP for nip.io
echo -e "${YELLOW}Updating Ingress configuration with nip.io domain...${NC}"
cat > kubernetes/ingress/app-ingress.yaml << EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: streamlit-app-ingress
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
spec:
  ingressClassName: nginx
  rules:
  - host: streamlit-app.${LOAD_BALANCER_IP}.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: streamlit-app
            port:
              number: 80
EOF

# Deploy the Ingress resource
echo -e "${YELLOW}Deploying Ingress resource...${NC}"
kubectl apply -f kubernetes/ingress/app-ingress.yaml

# Wait for ingress to be created
echo -e "${YELLOW}Waiting for Ingress to be processed...${NC}"
sleep 15

# Verify ingress is created
INGRESS_STATUS=$(kubectl get ingress streamlit-app-ingress -o jsonpath='{.status.loadBalancer}' 2>/dev/null || echo "NotFound")
if [ "$INGRESS_STATUS" = "NotFound" ]; then
  echo -e "${RED}Warning: Ingress resource was not found or has issues${NC}"
else
  echo -e "${GREEN}Ingress resource created successfully${NC}"
fi

# Print the final URL
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}Application deployed successfully!${NC}"
echo -e "${GREEN}You can access your application at:${NC}"
echo -e "${GREEN}http://streamlit-app.${LOAD_BALANCER_IP}.nip.io${NC}"
echo -e "${GREEN}============================================${NC}"

# Clean up backup files
rm -f kubernetes/deployment.yaml.bak
rm -f ingress-nginx-deploy.yaml.bak
rm -f ingress-nginx-deploy.yaml

echo -e "${YELLOW}Deployment completed.${NC}" 