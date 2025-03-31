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
command -v jq &> /dev/null || log_error "jq is not installed"
command -v bc &> /dev/null || log_error "bc is not installed"

# Verify Kubernetes cluster access
kubectl cluster-info &> /dev/null || log_error "Unable to connect to Kubernetes cluster"

print_header "URL Shortener Extreme Stress Test"

# Check if metrics-server is installed
echo "Checking if metrics-server is installed..."
kubectl get deployment metrics-server -n kube-system 2>/dev/null || echo -e "${YELLOW}Warning: Metrics server not found - HPA won't work without it!${NC}"

# Check if HPA exists
echo "Checking if URL Shortener HPA exists..."
kubectl get hpa url-shortener-hpa 2>/dev/null || log_error "HPA not found. Please create it first."

# Show initial state
echo "Initial state of HPA and pods:"
kubectl get hpa url-shortener-hpa
initial_replicas=$(kubectl get hpa url-shortener-hpa -o jsonpath='{.status.currentReplicas}')
echo "Initial replicas: $initial_replicas"
kubectl get pods -l app=url-shortener
kubectl top pods -l app=url-shortener 2>/dev/null || echo -e "${YELLOW}Warning: Could not get resource usage. Ensure metrics-server is running.${NC}"

# Get current target CPU percentage from HPA
target_cpu=$(kubectl get hpa url-shortener-hpa -o jsonpath='{.spec.metrics[0].resource.target.averageUtilization}')
echo -e "${YELLOW}Target CPU utilization: ${target_cpu}%${NC}"

# Get service endpoint
SERVICE_URL="http://url-shortener-service.default.svc.cluster.local"

# Create a configmap with the stress test script
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: extreme-stress-test-script
data:
  stress-test.sh: |
    #!/bin/sh
    if [ -z "\$1" ]; then
      echo "Usage: \$0 <requests_per_second> <number_of_workers>"
      exit 1
    fi
    
    RPS=\$1
    WORKERS=\${2:-1}
    SLEEP_TIME=\$(echo "scale=6; 1 / (\$RPS / \$WORKERS)" | bc)
    
    echo "Starting extreme stress test with total \$RPS requests per second across \$WORKERS workers"
    echo "Each worker will send 1 request every \$SLEEP_TIME seconds"
    
    # Function for a single worker
    worker() {
      WORKER_ID=\$1
      while true; do
        time_start=\$(date +%s.%N)
        
        # Generate random URL with worker ID
        RANDOM_URL="https://example.com/path\$RANDOM/\$WORKER_ID/\$RANDOM"
        
        # Send request to shorten URL
        curl -s -X POST -H "Content-Type: application/json" \\
          -d "{\\"url\\":\\"\$RANDOM_URL\\"}" \\
          ${SERVICE_URL}/shorten > /dev/null
          
        time_end=\$(date +%s.%N)
        time_diff=\$(echo "\$time_end - \$time_start" | bc)
        sleep_adjusted=\$(echo "\$SLEEP_TIME - \$time_diff" | bc)
        
        # Ensure sleep time is not negative
        if (( \$(echo "\$sleep_adjusted > 0" | bc -l) )); then
          sleep \$sleep_adjusted
        fi
      done
    }
    
    # Start workers in background
    for i in \$(seq 1 \$WORKERS); do
      worker \$i &
    done
    
    # Wait for all workers
    wait
EOF

# Run extreme load test
run_extreme_load_test() {
  local rps=$1
  local workers=$2
  local duration=$3
  local stage=$4
  
  print_header "Extreme Load Test - Stage $stage: $rps req/s with $workers workers for $duration seconds"
  
  # Create the load generator pod with higher resource limits
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: extreme-load-generator-$stage
spec:
  containers:
  - name: load-generator
    image: curlimages/curl:7.83.1
    command: ["/bin/sh", "-c"]
    args:
    - |
      cp /config/stress-test.sh /tmp/
      chmod +x /tmp/stress-test.sh
      /tmp/stress-test.sh $rps $workers
    volumeMounts:
    - name: config-volume
      mountPath: /config
    resources:
      requests:
        cpu: 500m
        memory: 512Mi
      limits:
        cpu: 1000m
        memory: 1Gi
  volumes:
  - name: config-volume
    configMap:
      name: extreme-stress-test-script
EOF
  
  # Wait for load generator to start
  echo "Waiting for extreme load generator to start..."
  kubectl wait --for=condition=Ready pod/extreme-load-generator-$stage --timeout=60s

  # Monitor HPA and pod metrics during the test
  echo "Running extreme load test for $duration seconds..."
  
  # Start periodic metrics collection
  end_time=$(($(date +%s) + $duration))
  
  echo "Time,Replicas,CPU%,Memory,PodStatus" > extreme-metrics-stage-$stage.csv
  
  while [ $(date +%s) -lt $end_time ]; do
    current_time=$(date +"%H:%M:%S")
    
    # Get current replicas
    current_replicas=$(kubectl get hpa url-shortener-hpa -o jsonpath='{.status.currentReplicas}' 2>/dev/null || echo "N/A")
    
    # Get CPU and memory
    kubectl top pods -l app=url-shortener --no-headers 2>/dev/null | awk '{cpu_sum+=$2; mem_sum+=$3} END {if(NR>0) printf "%s,%s,%s,%s,", "'$current_time'", "'$current_replicas'", cpu_sum/NR, mem_sum/NR}' >> extreme-metrics-stage-$stage.csv
    
    # Get pod status
    kubectl get pods -l app=url-shortener -o jsonpath='{range .items[*]}{.status.phase}{","}{.status.containerStatuses[0].ready}{","}{end}' >> extreme-metrics-stage-$stage.csv
    echo "" >> extreme-metrics-stage-$stage.csv
    
    # Show current state
    echo -e "${YELLOW}Time: $current_time - Remaining: $((end_time - $(date +%s))) seconds${NC}"
    echo "HPA Status:"
    kubectl get hpa url-shortener-hpa
    echo "Pod Status:"
    kubectl get pods -l app=url-shortener
    echo "Resource Usage:"
    kubectl top pods -l app=url-shortener 2>/dev/null || echo "Could not get resource usage."
    
    # Check for pod restarts or crashes
    pod_restarts=$(kubectl get pods -l app=url-shortener -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount}{end}')
    if [ "$pod_restarts" -gt 0 ]; then
      echo -e "${RED}ALERT: Pod crashes detected! Restart count: $pod_restarts${NC}"
    fi
    
    sleep 5
  done
  
  # Stop the load generator
  echo "Stopping extreme load generator..."
  kubectl delete pod extreme-load-generator-$stage --grace-period=1
  
  # Show current state after test
  echo -e "${GREEN}Extreme load test completed.${NC}"
  echo "Current state of HPA and pods:"
  kubectl get hpa url-shortener-hpa
  kubectl get pods -l app=url-shortener
  kubectl top pods -l app=url-shortener 2>/dev/null || echo "Could not get resource usage."
  
  # Get events related to pods
  echo -e "\n${YELLOW}Recent pod events:${NC}"
  kubectl get events --field-selector involvedObject.kind=Pod --sort-by='.lastTimestamp' | tail -n 20
}

# Define stages of extreme load testing
print_header "Starting Extreme Load Testing Sequence"

# First stage: Warm-up
run_extreme_load_test 200 4 60 1

# Second stage: Heavy load
run_extreme_load_test 500 8 120 2

# Third stage: Crash-inducing load
run_extreme_load_test 1000 16 180 3

# Fourth stage: Recovery observation
run_extreme_load_test 100 2 120 4

print_header "Extreme Load Testing Complete"
echo -e "${GREEN}URL Shortener extreme stress test completed! 🚀${NC}"
echo -e "${YELLOW}Check extreme-metrics-stage-*.csv files for detailed metrics${NC}"

# Print final summary
echo -e "\n${BLUE}Test Summary:${NC}"
echo "Initial pod count: $initial_replicas"
final_replicas=$(kubectl get hpa url-shortener-hpa -o jsonpath='{.status.currentReplicas}')
echo "Final pod count: $final_replicas"

# Check for any crashes during the test
pod_crashes=$(kubectl get pods -l app=url-shortener -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount}{" "}{end}')
total_crashes=0
for crash in $pod_crashes; do
  total_crashes=$((total_crashes + crash))
done

if [ "$total_crashes" -gt 0 ]; then
  echo -e "${RED}Pod crashes detected during test: $total_crashes restarts${NC}"
else
  echo -e "${GREEN}No pod crashes detected during test${NC}"
fi

echo -e "\n${YELLOW}Review your pod logs for detailed error information:${NC}"
echo "kubectl logs -l app=url-shortener"