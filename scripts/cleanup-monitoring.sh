#!/bin/bash

# Comprehensive Monitoring Cleanup and Restart Script
# Author: Steve Oak

# Set error handling
set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

function print_header() {
    echo -e "\n${GREEN}==== $1 ====${NC}\n"
}

function print_warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

function print_error() {
    echo -e "${RED}ERROR: $1${NC}"
}

function print_success() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
}

print_header "Kubernetes Monitoring Cleanup and Restart"

# Ensure kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl not found. Please install kubectl and try again."
    exit 1
fi

# Check if monitoring namespace exists
if kubectl get namespace monitoring &>/dev/null; then
    print_header "Cleaning up existing monitoring resources"
    
    # Remove RBAC resources first
    echo "Removing Prometheus RBAC resources..."
    kubectl delete clusterrolebinding prometheus --ignore-not-found
    kubectl delete clusterrole prometheus --ignore-not-found
    
    # Delete deployments and services
    echo "Removing deployments and services..."
    kubectl delete deployment --namespace monitoring --all --ignore-not-found
    kubectl delete service --namespace monitoring --all --ignore-not-found
    kubectl delete daemonset --namespace monitoring --all --ignore-not-found
    kubectl delete configmap --namespace monitoring --all --ignore-not-found
    
    # Force delete namespace as last resort
    echo "Deleting monitoring namespace..."
    kubectl delete namespace monitoring --force --grace-period=0 || true
    
    # Check if namespace is stuck
    if kubectl get namespace monitoring &>/dev/null; then
        print_warning "Namespace is stuck in Terminating state."
        print_warning "You may need to manually patch the namespace."
        print_warning "Try running: ./scripts/monitoring-cleanup.sh"
    fi
    
    # Kill any port forwarding
    echo "Terminating port-forwarding processes..."
    pkill -f 'kubectl port-forward.*monitoring' || echo "No port-forwarding processes found."
    
    # Wait for namespace to be fully deleted
    echo "Waiting for monitoring namespace to be deleted..."
    for i in {1..30}; do
        if ! kubectl get namespace monitoring &>/dev/null; then
            break
        fi
        echo -n "."
        sleep 2
    done
    echo ""
    
    # Final check
    if kubectl get namespace monitoring &>/dev/null; then
        print_error "Monitoring namespace still exists. Please run the full cleanup script:"
        print_error "./scripts/monitoring-cleanup.sh"
        exit 1
    fi
else
    print_warning "Monitoring namespace does not exist. Proceeding with installation."
fi

# Create monitoring namespace
print_header "Creating monitoring namespace"
kubectl create namespace monitoring

# Apply all monitoring resources
print_header "Deploying monitoring stack"

echo "Applying RBAC configuration..."
kubectl apply -f kubernetes/monitoring/prometheus-rbac.yaml

echo "Applying Prometheus configuration..."
kubectl apply -f kubernetes/monitoring/prometheus-config.yaml

echo "Deploying node-exporter..."
kubectl apply -f kubernetes/monitoring/node-exporter.yaml

echo "Deploying kube-state-metrics..."
kubectl apply -f kubernetes/monitoring/kube-state-metrics.yaml 

echo "Deploying Prometheus server..."
kubectl apply -f kubernetes/monitoring/prometheus-deployment.yaml

echo "Deploying Grafana configuration..."
kubectl apply -f kubernetes/monitoring/grafana-configmaps.yaml

echo "Deploying Grafana server..."
kubectl apply -f kubernetes/monitoring/grafana-deployment.yaml

# Wait for deployments to be ready
print_header "Waiting for monitoring stack to be ready"

echo "Waiting for Prometheus..."
kubectl rollout status deployment/prometheus -n monitoring --timeout=120s || print_warning "Prometheus deployment timed out"

echo "Waiting for Grafana..."
kubectl rollout status deployment/grafana -n monitoring --timeout=120s || print_warning "Grafana deployment timed out"

echo "Waiting for kube-state-metrics..."
kubectl rollout status deployment/kube-state-metrics -n monitoring --timeout=120s || print_warning "kube-state-metrics deployment timed out"

# Setup port forwarding for Grafana
print_header "Setting up port forwarding"

echo "Starting Grafana port forwarding on port 3000..."
kubectl port-forward -n monitoring svc/grafana 3000:3000 > /dev/null 2>&1 &
GRAFANA_PID=$!

echo "Starting Prometheus port forwarding on port 9090..."
kubectl port-forward -n monitoring svc/prometheus-service 9090:9090 > /dev/null 2>&1 &
PROMETHEUS_PID=$!

# Print access information
print_header "Monitoring setup complete!"
echo "Grafana is accessible at: http://localhost:3000"
echo "Prometheus is accessible at: http://localhost:9090"
echo ""
echo "Port forwarding processes running with PIDs: $GRAFANA_PID (Grafana), $PROMETHEUS_PID (Prometheus)"
echo "To stop port forwarding, run: kill $GRAFANA_PID $PROMETHEUS_PID"
echo ""
echo "For cluster access, use the service node port or LoadBalancer if configured."
echo ""
print_success "Monitoring stack has been successfully deployed!" 