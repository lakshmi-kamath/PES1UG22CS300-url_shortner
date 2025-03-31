#!/bin/bash

# Ensure script fails on any error
set -e

# Colors for better readability
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to log error and exit
log_error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

# Function to print section header
print_header() {
    echo -e "\n${BLUE}===== $1 =====${NC}"
}

# Prerequisites check
command -v kubectl &> /dev/null || log_error "kubectl is not installed"

# Verify Kubernetes cluster access
kubectl cluster-info &> /dev/null || log_error "Unable to connect to Kubernetes cluster"

print_header "Setting up Kubernetes Monitoring Stack"

# Check if monitoring components already exist
if kubectl get deployment prometheus &> /dev/null; then
    echo -e "${YELLOW}Prometheus deployment already exists. Skipping creation.${NC}"
else
    echo -e "${GREEN}Creating Prometheus deployment...${NC}"
    kubectl apply -f prometheus-config.yaml
    kubectl apply -f prometheus-deployment.yaml
    kubectl apply -f prometheus-service.yaml
fi

if kubectl get deployment grafana &> /dev/null; then
    echo -e "${YELLOW}Grafana deployment already exists. Skipping creation.${NC}"
else
    echo -e "${GREEN}Creating Grafana deployment...${NC}"
    kubectl apply -f grafana-deployment.yaml
    kubectl apply -f grafana-service.yaml
    kubectl apply -f grafana-ingress.yaml
fi

print_header "Installing Node Exporter DaemonSet"
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
  labels:
    app: node-exporter
spec:
  selector:
    matchLabels:
      app: node-exporter
  template:
    metadata:
      labels:
        app: node-exporter
    spec:
      hostNetwork: true
      hostPID: true
      containers:
      - name: node-exporter
        image: prom/node-exporter:v1.5.0
        args:
        - --path.procfs=/host/proc
        - --path.sysfs=/host/sys
        ports:
        - containerPort: 9100
          protocol: TCP
          name: metrics
        volumeMounts:
        - name: proc
          mountPath: /host/proc
          readOnly: true
        - name: sys
          mountPath: /host/sys
          readOnly: true
      volumes:
      - name: proc
        hostPath:
          path: /proc
      - name: sys
        hostPath:
          path: /sys
EOF

print_header "Installing Kube State Metrics"
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kube-state-metrics
spec:
  selector:
    matchLabels:
      app: kube-state-metrics
  replicas: 1
  template:
    metadata:
      labels:
        app: kube-state-metrics
    spec:
      containers:
      - name: kube-state-metrics
        image: k8s.gcr.io/kube-state-metrics/kube-state-metrics:v2.7.0
        ports:
        - containerPort: 8080
          name: http-metrics
EOF

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: kube-state-metrics
  labels:
    app: kube-state-metrics
spec:
  ports:
  - name: http-metrics
    port: 8080
    targetPort: http-metrics
  selector:
    app: kube-state-metrics
EOF

print_header "Updating URL Shortener deployment with Prometheus annotations"
kubectl apply -f url-shortener-deployment.yaml

# Wait for deployments to be ready
print_header "Waiting for monitoring components to start"
kubectl rollout status deployment/prometheus
kubectl rollout status deployment/grafana
kubectl rollout status deployment/kube-state-metrics

print_header "Setting up default Grafana dashboards"
echo -e "${YELLOW}To access Grafana:${NC}"
echo "1. Access via ingress at: https://grafana.shorturl.local"
echo "2. Or use port-forwarding: kubectl port-forward svc/grafana 3000:3000"
echo "3. Login with username: admin, password: admin"
echo "4. Add Prometheus data source with URL: http://prometheus:9090"
echo "5. Import Kubernetes dashboard ID: 10856"

print_header "Setting up complete"
echo -e "${GREEN}Monitoring stack has been successfully deployed!${NC}"
echo -e "${YELLOW}Run the kubernetes-monitoring.sh script to check the current status of your URL shortener application.${NC}"