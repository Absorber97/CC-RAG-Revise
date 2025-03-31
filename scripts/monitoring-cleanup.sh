#!/bin/bash

# Enhanced Monitoring Stack Cleanup
# Author: Steve Oak

echo "Cleaning up Kubernetes monitoring stack..."

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl not found. Please install kubectl and try again."
    exit 1
fi

# Delete specific resources first to avoid namespace stuck in Terminating state
echo "Removing Prometheus RBAC resources..."
kubectl delete clusterrolebinding prometheus --ignore-not-found
kubectl delete clusterrole prometheus --ignore-not-found

echo "Removing monitoring deployments and services..."
kubectl delete deployment --namespace monitoring --all --ignore-not-found
kubectl delete service --namespace monitoring --all --ignore-not-found
kubectl delete daemonset --namespace monitoring --all --ignore-not-found
kubectl delete configmap --namespace monitoring --all --ignore-not-found

# Delete the monitoring namespace
echo "Deleting monitoring namespace..."
kubectl delete namespace monitoring --force --grace-period=0 || echo "Namespace deletion initiated or already deleted."

# Check for stuck namespace
echo "Checking if monitoring namespace is stuck in Terminating state..."
if kubectl get namespace monitoring &>/dev/null; then
    echo "Namespace still exists, attempting to remove finalizers..."
    kubectl get namespace monitoring -o json | jq '.spec.finalizers = []' > ns.json
    if command -v kubectl-patch-ns &> /dev/null; then
        kubectl-patch-ns ns.json
    else
        echo "For stuck namespaces, you may need to patch the namespace manually:"
        echo "kubectl proxy"
        echo "curl -k -H \"Content-Type: application/json\" -X PUT --data-binary @ns.json http://127.0.0.1:8001/api/v1/namespaces/monitoring/finalize"
    fi
    rm -f ns.json
fi

# Kill any port-forwarding processes
echo "Terminating any port-forwarding processes..."
pkill -f 'kubectl port-forward.*monitoring' || echo "No port-forwarding processes found."

# Additional cleanup for common monitoring tools
echo "Cleaning up any lingering monitoring resources..."
kubectl delete pod,service,deployment,statefulset,configmap,pvc,pv,job,cronjob -l "app in (prometheus,grafana,alertmanager,node-exporter,kube-state-metrics)" --all-namespaces --ignore-not-found

echo ""
echo "Cleanup complete! The monitoring namespace and related resources have been removed."
echo ""
echo "If you're still experiencing issues, try these additional steps:"
echo "1. Check for stuck resources: kubectl get all -n monitoring"
echo "2. Restart your kubectl proxy if running"
echo "3. Verify port availability: lsof -i :3000 -i :9090"
echo "" 