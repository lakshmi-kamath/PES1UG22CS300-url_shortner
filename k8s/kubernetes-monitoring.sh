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

print_header "URL Shortener Monitoring Dashboard"

# Check deployment status
print_header "Deployment Status"
kubectl get deployments -o wide | grep -E 'url-shortener|redis'

# Check pod status
print_header "Pod Status"
kubectl get pods -l app=url-shortener -o wide

# Check HPA status
print_header "HPA Status"
kubectl get hpa url-shortener-hpa

# Check Services
print_header "Services Status"
kubectl get services | grep -E 'url-shortener|redis'

# Check Ingress
print_header "Ingress Status"
kubectl get ingress url-shortener-ingress

# Function to show recent logs for a specific pod
show_pod_logs() {
    local pod_name=$1
    local lines=${2:-50}
    
    echo -e "${YELLOW}Recent logs for $pod_name (last $lines lines):${NC}"
    kubectl logs $pod_name --tail=$lines
}

# Show logs for all URL shortener pods
print_header "URL Shortener Logs"
url_shortener_pods=$(kubectl get pods -l app=url-shortener -o jsonpath='{.items[*].metadata.name}')

for pod in $url_shortener_pods; do
    show_pod_logs $pod 20
    echo -e "\n${YELLOW}---${NC}\n"
done

# Show logs for Redis pod
print_header "Redis Logs"
redis_pod=$(kubectl get pods -l app=redis -o jsonpath='{.items[0].metadata.name}')
show_pod_logs $redis_pod 20

# Show resource usage
print_header "Resource Usage"
kubectl top pods | grep -E 'url-shortener|redis' || echo -e "${YELLOW}Resource metrics not available. Make sure metrics-server is installed.${NC}"

# Check for any events in the last 15 minutes
print_header "Recent Cluster Events"
kubectl get events --sort-by='.lastTimestamp' | tail -n 10

print_header "Monitoring Complete"
echo -e "${GREEN}URL Shortener monitoring check completed successfully!${NC}"