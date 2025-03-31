# Streamlit Application Monitoring

This directory contains Kubernetes manifests for monitoring a Streamlit application using Prometheus and Grafana.

## Components

1. **Prometheus**: Collects and stores metrics from various sources
   - Collects metrics from annotated pods
   - Scrapes the Streamlit application's built-in metrics endpoint (`/_stcore/metrics`)
   - Stores time-series data

2. **Grafana**: Visualizes the metrics collected by Prometheus
   - Pre-configured dashboard for Streamlit application monitoring
   - Various panels for different metrics visualization

3. **Node Exporter**: Collects hardware and OS metrics
   - CPU, memory, disk, and network usage on each node
   - Runs as a DaemonSet to ensure coverage of all nodes

4. **Kube State Metrics**: Collects Kubernetes state metrics
   - Pod, deployment, and node state
   - Resource requests and limits
   - Pod status and health

## Key Metrics

The monitoring stack collects and visualizes the following metrics:

### Streamlit-specific Metrics
- Cache memory usage by type (`cache_memory_bytes`)
- Session state
- Runtime performance

### Kubernetes Resource Metrics
- CPU usage per pod
- Memory consumption per pod
- Network traffic (ingress/egress)
- Container restarts

### Node Metrics
- Node CPU utilization
- Node memory usage
- Disk space usage
- Network performance

## Streamlit Metrics Endpoint

Since Streamlit version 1.18.0, metrics are exposed at the `/_stcore/metrics` endpoint instead of `/metrics`. The deployment has been configured with the proper annotations to point Prometheus to this new path:

```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/path: "/_stcore/metrics"
  prometheus.io/port: "8501"
```

## Setup

1. Apply the RBAC configuration:
   ```
   kubectl apply -f prometheus-rbac.yaml
   ```

2. Deploy Prometheus with the correct configuration:
   ```
   kubectl apply -f prometheus-config.yaml
   kubectl apply -f prometheus-deployment.yaml
   ```

3. Deploy the node exporter:
   ```
   kubectl apply -f node-exporter.yaml
   ```

4. Deploy kube-state-metrics:
   ```
   kubectl apply -f kube-state-metrics.yaml
   ```

5. Configure and deploy Grafana:
   ```
   kubectl apply -f grafana-configmaps.yaml
   kubectl apply -f grafana-deployment.yaml
   ```

6. Ensure the Streamlit deployment has the proper annotations:
   ```
   kubectl apply -f ../streamlit-app-deployment.yaml
   ```

## Accessing Dashboards

1. Forward Prometheus port:
   ```
   kubectl port-forward -n monitoring service/prometheus-service 9090:9090
   ```
   Access at: http://localhost:9090

2. Forward Grafana port:
   ```
   kubectl port-forward -n monitoring service/grafana-service 3000:80
   ```
   Access at: http://localhost:3000
   Default credentials: admin/admin

## Troubleshooting

If metrics are not showing in Grafana:

1. Check Prometheus targets:
   ```
   curl -s http://localhost:9090/api/v1/targets | jq
   ```

2. Verify Streamlit metrics endpoint:
   ```
   kubectl port-forward <streamlit-pod-name> 8501:8501
   curl http://localhost:8501/_stcore/metrics
   ```

3. Ensure the Prometheus configuration has a job for Streamlit apps:
   ```
   kubectl get configmap prometheus-config -n monitoring -o yaml
   ```

## References

- [Prometheus Documentation](https://prometheus.io/docs/introduction/overview/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Streamlit Metrics](https://discuss.streamlit.io/t/prometheus-integration-for-streamlit-app-metrics/61731)
- [Red Hat Blog: Streamlit for Infrastructure Monitoring](https://www.redhat.com/en/blog/streamlit-monitor-infrastructure) 