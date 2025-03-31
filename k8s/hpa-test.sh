#!/bin/bash

# Ensure script fails on any error
set -e

# Function to log error and exit
log_error() {
    echo "ERROR: $1" >&2
    exit 1
}

# Prerequisite checks
command -v kubectl &> /dev/null || log_error "kubectl is not installed"

# Verify Kubernetes cluster access
kubectl cluster-info &> /dev/null || log_error "Unable to connect to Kubernetes cluster"

echo "===== HPA Test ====="

# Check if metrics-server is installed
echo "Checking if metrics-server is installed..."
kubectl get deployment metrics-server -n kube-system || echo "Warning: Metrics server not found - HPA won't work without it!"

# Check if HPA exists
echo "Checking if URL Shortener HPA exists..."
kubectl get hpa url-shortener-hpa || log_error "HPA not found. Please create it first."

# Show initial state
echo "Initial state of HPA and pods:"
kubectl get hpa url-shortener-hpa
initial_replicas=$(kubectl get hpa url-shortener-hpa -o jsonpath='{.status.currentReplicas}')
echo "Initial replicas: $initial_replicas"
kubectl get pods -l app=url-shortener

# Get current target CPU percentage from HPA
target_cpu=$(kubectl get hpa url-shortener-hpa -o jsonpath='{.spec.metrics[0].resource.target.averageUtilization}')
echo "Target CPU utilization: ${target_cpu}%"

# Generate load to trigger autoscaling
echo "Generating load to trigger auto-scaling..."
# Create a separate pod for load generation with higher CPU request
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: load-generator
spec:
  containers:
  - name: busybox
    image: busybox:1.28
    resources:
      requests:
        cpu: 200m
        memory: 64Mi
    command: ["/bin/sh", "-c"]
    args:
    - |
      while true; do
        for i in \$(seq 1 100); do
          wget -q -O- http://url-shortener-service.default.svc.cluster.local/shorten --post-data '{"url":"https://example.com"}' --header='Content-Type:application/json'
          sleep 0.001
        done
      done
EOF

# Wait for load generator to start
echo "Waiting for load generator to start..."
kubectl wait --for=condition=Ready pod/load-generator --timeout=60s

# Wait for autoscaling to happen
echo "Waiting for HPA to scale pods up (this may take a few minutes)..."
scaled=false
for i in {1..30}; do
  echo "Checking HPA status (attempt $i of 30)..."
  kubectl get hpa url-shortener-hpa
  kubectl get pods -l app=url-shortener
  current_replicas=$(kubectl get hpa url-shortener-hpa -o jsonpath='{.status.currentReplicas}')
  current_cpu=$(kubectl get hpa url-shortener-hpa -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}')
  
  if [ -z "$current_cpu" ]; then
    current_cpu="<unknown>"
  fi
  
  echo "Current CPU utilization: $current_cpu% (target: ${target_cpu}%)"
  echo "Current replicas: $current_replicas"
  
  # If actual scaling has occurred, break
  if [ "$current_replicas" -gt "$initial_replicas" ]; then
    echo "✅ HPA is working! Pods scaled from $initial_replicas to $current_replicas"
    scaled=true
    break
  fi
  
  sleep 20
done

if [ "$scaled" = false ]; then
  echo "❌ HPA did not scale pods after 10 minutes. Possible issues:"
  echo "   - The metrics server might not be properly installed"
  echo "   - The load might not be sufficient to trigger scaling"
  echo "   - Resource requests might be set too high"
fi

# Clean up
echo "Stopping load generator..."
kubectl delete pod load-generator

echo "Waiting for pods to scale down (this will take longer due to scaleDown stabilization window)..."
echo "You can monitor with: kubectl get hpa url-shortener-hpa --watch"

echo "HPA test complete. ✨"