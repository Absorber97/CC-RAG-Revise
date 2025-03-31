#!/bin/bash

# Set up monitoring stack with Prometheus and Grafana
# Author: Steve Oak

set -e

echo "Setting up monitoring stack..."

# Clean up any existing port forwarding
if [ -f .grafana-port-forward.pid ]; then
  echo "Cleaning up existing port forwarding..."
  kill $(cat .grafana-port-forward.pid) 2>/dev/null || true
  rm .grafana-port-forward.pid
fi

# Check if monitoring namespace exists and is terminating
echo "Checking namespace status..."
NS_STATUS=$(kubectl get namespace monitoring -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

if [ "$NS_STATUS" == "Terminating" ]; then
  echo "Monitoring namespace is still terminating. Waiting for deletion to complete..."
  
  # Wait for namespace to be fully deleted (timeout after 2 minutes)
  for i in $(seq 1 24); do
    if ! kubectl get namespace monitoring > /dev/null 2>&1; then
      echo "Namespace has been deleted successfully."
      break
    fi
    
    if [ $i -eq 24 ]; then
      echo "Namespace is stuck in Terminating state. Please check Kubernetes resources manually."
      echo "You can try forcing namespace deletion with: kubectl delete namespace monitoring --force --grace-period=0"
      exit 1
    fi
    
    echo "Still waiting for namespace deletion... (attempt $i/24)"
    sleep 5
  done
fi

# Create monitoring namespace
echo "Creating monitoring namespace..."
kubectl create namespace monitoring

# Deploy Prometheus
echo "Deploying Prometheus..."
kubectl apply -f kubernetes/monitoring/prometheus-configmap.yaml
kubectl apply -f kubernetes/monitoring/prometheus-deployment.yaml

# Wait for Prometheus to be ready
echo "Waiting for Prometheus to be ready..."
kubectl wait --namespace monitoring --for=condition=available deployment/prometheus --timeout=300s

# Deploy Grafana
echo "Deploying Grafana..."
kubectl apply -f kubernetes/monitoring/grafana-configmaps.yaml
kubectl apply -f kubernetes/monitoring/grafana-deployment.yaml

# Wait for Grafana to be ready
echo "Waiting for Grafana to be ready..."
kubectl wait --namespace monitoring --for=condition=available deployment/grafana --timeout=300s

# Get Grafana service information
echo "Checking for external LoadBalancer IP..."
GRAFANA_SERVICE=$(kubectl get service -n monitoring grafana-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

if [ -z "$GRAFANA_SERVICE" ]; then
  echo "Grafana service external IP not available yet. Providing access instructions..."
  
  echo ""
  echo "To access Grafana, run the following command in a separate terminal:"
  echo "-----------------------------------------------------------------"
  echo "kubectl port-forward -n monitoring svc/grafana-service 3000:80"
  echo "-----------------------------------------------------------------"
  echo ""
  echo "Then access Grafana at: http://localhost:3000"
  echo "  - Username: admin"
  echo "  - Password: admin"
else
  echo "Grafana dashboard is available at: http://$GRAFANA_SERVICE"
  echo "  - Username: admin"
  echo "  - Password: admin"
fi

echo ""
echo "Monitoring setup complete!"
echo "To view resource usage:"
echo "1. Open Grafana dashboard"
echo "2. Navigate to the 'Streamlit App Dashboard'"
echo "3. You can customize the dashboard further by clicking the gear icon"
echo ""
echo "To stop monitoring, run: ./scripts/monitoring-cleanup.sh" 