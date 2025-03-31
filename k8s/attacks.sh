#!/bin/bash

# Ensure script fails on any error
set -e
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

# Verify Kubernetes cluster access
kubectl cluster-info &> /dev/null || log_error "Unable to connect to Kubernetes cluster"

print_header "URL Shortener Pod Crash Test (Enhanced)"

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

# Get service endpoint
SERVICE_URL="http://url-shortener-service.default.svc.cluster.local"

# Create a configmap with the enhanced crash test scripts
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: crash-test-scripts
data:
  memory-exhaustion.sh: |
    #!/bin/sh
    echo "Starting ENHANCED memory exhaustion attack..."
    
    SERVICE_URL="$SERVICE_URL"
    
    # Function to create a massive payload
    create_massive_payload() {
      # Generate a string with ~2MB of data (4x larger than original)
      large_string=\$(yes "XABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" | head -c 2000000 | tr -d '\n')
      echo "{\"url\":\"https://example.com/\$large_string\"}"
    }
    
    # Send requests with large payloads in parallel - increased from 200 to 500
    for i in \$(seq 1 500); do
      echo "Sending massive payload \$i/500"
      payload=\$(create_massive_payload)
      curl -s -X POST -H "Content-Type: application/json" \\
        -d "\$payload" \\
        \$SERVICE_URL/shorten > /dev/null &
        
      # Send in smaller batches to avoid overwhelming the client
      if (( i % 5 == 0 )); then
        wait
      fi
    done
    
    wait
    echo "Enhanced memory exhaustion attack completed"
  
  connection-flood.sh: |
    #!/bin/sh
    echo "Starting ENHANCED connection flood attack..."
    
    SERVICE_URL="$SERVICE_URL"
    
    # Run massive parallel requests - increased waves from 20 to 50
    for wave in \$(seq 1 50); do
      echo "Starting connection wave \$wave/50"
      # Increased from 200 to 500 connections per wave
      for i in \$(seq 1 500); do
        random_str=\$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
        curl -s -X POST -H "Content-Type: application/json" \\
          -d "{\"url\":\"https://example.com/flood-\$wave-\$i-\$random_str\"}" \\
          \$SERVICE_URL/shorten > /dev/null &
      done
      
      # Faster wave frequency (reduced pause between waves)
      sleep 0.2
    done
    
    wait
    echo "Enhanced connection flood attack completed"
    
  cpu-exhaust.sh: |
    #!/bin/sh
    echo "Starting ENHANCED CPU exhaustion attack..."
    
    SERVICE_URL="$SERVICE_URL"
    
    # Function to send requests in a tight loop
    send_requests() {
      # Increased from 500 to 1000 requests per stream
      for j in \$(seq 1 1000); do
        curl -s -X POST -H "Content-Type: application/json" \\
          -d "{\"url\":\"https://example.com/cpu-\$1-\$j-\$(date +%s%N)\"}" \\
          \$SERVICE_URL/shorten > /dev/null &
        
        # Increased batch size to intensify load
        if (( j % 100 == 0 )); then
          wait
        fi
      done
      wait
    }
    
    # Run multiple parallel request streams - increased from 8 to 16
    for i in \$(seq 1 16); do
      send_requests \$i &
    done
    
    wait
    echo "Enhanced CPU exhaustion attack completed"
    
  combined-attack.sh: |
    #!/bin/sh
    echo "Starting ENHANCED combined attack..."
    
    SERVICE_URL="$SERVICE_URL"
    
    # Start CPU stress in background - increased from 4 to 8 streams
    for i in \$(seq 1 8); do
      (
        # Increased from 250 to 500 requests per stream
        for j in \$(seq 1 500); do
          curl -s -X POST -H "Content-Type: application/json" \\
            -d "{\"url\":\"https://example.com/combined-cpu-\$i-\$j-\$(date +%s%N)\"}" \\
            \$SERVICE_URL/shorten > /dev/null
        done
      ) &
    done
    
    # Start memory stress in background
    (
      # Generate large payloads - increased from 50 to 100
      for i in \$(seq 1 100); do
        # Increased payload size from 100KB to 500KB
        large_string=\$(yes "XABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" | head -c 500000 | tr -d '\n')
        curl -s -X POST -H "Content-Type: application/json" \\
          -d "{\"url\":\"https://example.com/\$large_string\"}" \\
          \$SERVICE_URL/shorten > /dev/null &
          
        # Smaller batches for higher concurrency
        if (( i % 3 == 0 )); then
          wait
        fi
      done
    ) &
    
    # Start connection flood in background - increased from 500 to 1000
    (
      for i in \$(seq 1 1000); do
        curl -s -X POST -H "Content-Type: application/json" \\
          -d "{\"url\":\"https://example.com/flood-\$i-\$(date +%s%N)\"}" \\
          \$SERVICE_URL/shorten > /dev/null &
          
        # Increased concurrency with smaller batches
        if (( i % 20 == 0 )); then
          wait
        fi
      done
    ) &
    
    # New attack vector: Rapid reconnects with invalid data
    (
      for i in \$(seq 1 300); do
        # Invalid JSON payloads to potentially trigger error handlers
        malformed_data="{ url: https://example.com/malformed-\$i, invalid json"
        curl -s -X POST -H "Content-Type: application/json" \\
          -d "\$malformed_data" \\
          \$SERVICE_URL/shorten > /dev/null &
          
        if (( i % 30 == 0 )); then
          wait
        fi
      done
    ) &
    
    wait
    echo "Enhanced combined attack completed"

  extreme-attack.sh: |
    #!/bin/sh
    echo "Starting EXTREME attack (will likely crash any service)..."
    
    SERVICE_URL="$SERVICE_URL"
    
    # Run all attack vectors simultaneously at maximum intensity
    
    # Multiple extreme memory loads
    for memthread in \$(seq 1 3); do
      (
        for i in \$(seq 1 50); do
          # Generate 5MB payloads
          giant_string=\$(yes "XABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" | head -c 5000000 | tr -d '\n')
          curl -s -X POST -H "Content-Type: application/json" \\
            -d "{\"url\":\"https://example.com/\$giant_string\"}" \\
            \$SERVICE_URL/shorten > /dev/null &
            
          if (( i % 2 == 0 )); then
            wait
          fi
        done
      ) &
    done
    
    # Extreme connection flood
    for wave in \$(seq 1 10); do
      (
        for i in \$(seq 1 1000); do
          random_str=\$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
          curl -s -X POST -H "Content-Type: application/json" \\
            -d "{\"url\":\"https://example.com/extreme-\$wave-\$i-\$random_str\"}" \\
            \$SERVICE_URL/shorten > /dev/null &
        done
        wait
      ) &
    done
    
    # CPU burnout
    for cputhread in \$(seq 1 8); do
      (
        for j in \$(seq 1 2000); do
          curl -s -X POST -H "Content-Type: application/json" \\
            -d "{\"url\":\"https://example.com/extreme-cpu-\$cputhread-\$j-\$(date +%s%N)\"}" \\
            \$SERVICE_URL/shorten > /dev/null &
            
          if (( j % 100 == 0 )); then
            wait
          fi
        done
      ) &
    done
    
    # Malformed data
    (
      for i in \$(seq 1 500); do
        # Various invalid payloads
        case \$((i % 4)) in
          0) payload="{url: invalid-json-\$i" ;;
          1) payload="{\"url\":null}" ;;
          2) payload="{\"url\":[\$(yes \"\\\"a\\\",\" | head -c 10000)]}" ;;
          3) payload="{\"not_url_field\":\"https://example.com/\$i\"}" ;;
        esac
        
        curl -s -X POST -H "Content-Type: application/json" \\
          -d "\$payload" \\
          \$SERVICE_URL/shorten > /dev/null &
          
        if (( i % 50 == 0 )); then
          wait
        fi
      done
    ) &
    
    wait
    echo "Extreme attack completed"
EOF

# Function to run specific attack type
run_attack() {
  local attack_type=$1
  local duration=$2
  local attack_name=$3
  
  print_header "Running $attack_name Attack"
  
  # Create the attack pod with increased resources
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: url-shortener-$attack_type-attack
spec:
  containers:
  - name: attack-container
    image: curlimages/curl:7.83.1
    command: ["/bin/sh", "-c"]
    args:
    - |
      cp /config/$attack_type.sh /tmp/
      chmod +x /tmp/$attack_type.sh
      echo "Starting $attack_name attack..."
      /tmp/$attack_type.sh
      echo "Attack completed, keeping pod alive for logging..."
      sleep 30
    volumeMounts:
    - name: config-volume
      mountPath: /config
    resources:
      requests:
        cpu: 400m
        memory: 512Mi
      limits:
        cpu: 1
        memory: 1Gi
  volumes:
  - name: config-volume
    configMap:
      name: crash-test-scripts
EOF
  
  # Wait for attack pod to start
  echo "Waiting for attack pod to start..."
  kubectl wait --for=condition=Ready pod/url-shortener-$attack_type-attack --timeout=60s
  
  # Monitor pods during the attack
  echo "Running $attack_name attack and monitoring pods..."
  
  # Track start time
  start_time=$(date +%s)
  end_time=$((start_time + duration))
  
  # Create a monitoring log file
  log_file="$attack_type-attack-log.csv"
  echo "Timestamp,Replicas,PodCount,RestartCount,PendingPods,CPUUsage,MemoryUsage" > "$log_file"
  
  # Function to collect and display metrics
  collect_metrics() {
    # Get pod metrics
    replicas=$(kubectl get hpa url-shortener-hpa -o jsonpath='{.status.currentReplicas}' 2>/dev/null || echo "N/A")
    pod_count=$(kubectl get pods -l app=url-shortener --no-headers | wc -l)
    restart_count=$(kubectl get pods -l app=url-shortener -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount}{"\n"}{end}' | awk '{sum+=$1} END {print sum}')
    pending_pods=$(kubectl get pods -l app=url-shortener --no-headers | grep Pending | wc -l)
    
    # Collect CPU and memory usage if metrics server available
    if kubectl top pods -l app=url-shortener --no-headers 2>/dev/null; then
      cpu_usage=$(kubectl top pods -l app=url-shortener --no-headers 2>/dev/null | awk '{sum+=$2} END {print sum}')
      memory_usage=$(kubectl top pods -l app=url-shortener --no-headers 2>/dev/null | awk '{sum+=$3} END {print sum}')
    else
      cpu_usage="N/A"
      memory_usage="N/A"
    fi
    
    # Log metrics
    timestamp=$(date +"%H:%M:%S")
    echo "$timestamp,$replicas,$pod_count,$restart_count,$pending_pods,$cpu_usage,$memory_usage" >> "$log_file"
    
    # Display current state
    echo -e "${YELLOW}Time: $timestamp - Metrics: Replicas=$replicas, Pods=$pod_count, Restarts=$restart_count, Pending=$pending_pods, CPU=$cpu_usage, Mem=$memory_usage${NC}"
    kubectl get pods -l app=url-shortener
    
    # Check for crashes
    if [ "$restart_count" -gt 0 ]; then
      echo -e "${RED}DETECTED POD CRASHES: $restart_count restart(s)${NC}"
    fi
  }
  
  # Monitor in a loop
  while [ $(date +%s) -lt $end_time ]; do
    collect_metrics
    sleep 5
  done
  
  # Stop attack pod
  echo "Stopping $attack_name attack..."
  kubectl delete pod url-shortener-$attack_type-attack --grace-period=1
  
  # Final metrics collection
  print_header "$attack_name Attack Complete"
  collect_metrics
  
  # Display pod logs if crashes occurred
  restart_count=$(kubectl get pods -l app=url-shortener -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount}{"\n"}{end}' | awk '{sum+=$1} END {print sum}')
  if [ "$restart_count" -gt 0 ]; then
    echo -e "${RED}Pod crashes detected during attack!${NC}"
    echo "Recent events:"
    kubectl get events --sort-by='.lastTimestamp' | grep url-shortener | tail -n 10
    
    # Get pod names with restarts
    crashed_pods=$(kubectl get pods -l app=url-shortener -o jsonpath='{range .items[*]}{.metadata.name}{","}{.status.containerStatuses[0].restartCount}{"\n"}{end}' | grep -v ",0")
    
    if [ ! -z "$crashed_pods" ]; then
      echo -e "${YELLOW}Pods with restarts:${NC}"
      echo "$crashed_pods"
      
      # Get previous logs from first crashed pod
      first_crashed_pod=$(echo "$crashed_pods" | head -n 1 | cut -d ',' -f 1)
      echo -e "${YELLOW}Logs from crashed pod $first_crashed_pod (previous instance):${NC}"
      kubectl logs $first_crashed_pod --previous || echo "No previous logs available"
    fi
  else
    echo -e "${GREEN}No pod crashes detected during $attack_name attack${NC}"
  fi
}

# Main menu for selecting attack type
select_attack_type() {
  echo -e "\n${YELLOW}Select an attack type to execute:${NC}"
  echo "1) Enhanced Memory Exhaustion Attack"
  echo "2) Enhanced Connection Flood Attack"
  echo "3) Enhanced CPU Exhaustion Attack"
  echo "4) Enhanced Combined Attack"
  echo "5) Extreme Attack (Maximum Intensity)"
  echo "6) Run All Attacks Sequentially"
  echo "q) Quit"
  
  read -p "Enter selection [1-6 or q]: " selection
  
  case $selection in
    1)
      run_attack "memory-exhaustion" 120 "Enhanced Memory Exhaustion"
      ;;
    2)
      run_attack "connection-flood" 120 "Enhanced Connection Flood"
      ;;
    3)
      run_attack "cpu-exhaust" 120 "Enhanced CPU Exhaustion"
      ;;
    4)
      run_attack "combined-attack" 180 "Enhanced Combined"
      ;;
    5)
      run_attack "extreme-attack" 240 "Extreme"
      ;;
    6)
      run_attack "memory-exhaustion" 90 "Enhanced Memory Exhaustion"
      sleep 30
      run_attack "connection-flood" 90 "Enhanced Connection Flood"
      sleep 30
      run_attack "cpu-exhaust" 90 "Enhanced CPU Exhaustion"
      sleep 30
      run_attack "combined-attack" 120 "Enhanced Combined"
      sleep 30
      run_attack "extreme-attack" 180 "Extreme"
      ;;
    q|Q)
      echo "Exiting..."
      exit 0
      ;;
    *)
      echo -e "${RED}Invalid selection!${NC}"
      select_attack_type
      ;;
  esac
}

# Run the menu
select_attack_type

print_header "Attack Testing Complete"

# Final summary
final_replicas=$(kubectl get hpa url-shortener-hpa -o jsonpath='{.status.currentReplicas}')
total_restarts=$(kubectl get pods -l app=url-shortener -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount}{"\n"}{end}' | awk '{sum+=$1} END {print sum}')

echo -e "${BLUE}Test Summary:${NC}"
echo "Initial pod count: $initial_replicas"
echo "Final pod count: $final_replicas"
echo "Total pod restarts: $total_restarts"

if [ "$total_restarts" -gt 0 ]; then
  echo -e "${RED}Pod crashes were successfully induced!${NC}"
else
  echo -e "${YELLOW}No pod crashes detected. Your service is very resilient!${NC}"
  echo "Consider:"
  echo "1. Running the extreme attack for a longer duration"
  echo "2. Further modifying the attack scripts to be even more aggressive"
  echo "3. Checking if your service has memory/request limits that are too high"
  echo "4. Examining your autoscaling settings"
fi

echo -e "\n${GREEN}Enhanced URL Shortener crash testing completed! 🚀${NC}"
echo -e "${YELLOW}Check the *-attack-log.csv files for detailed metrics${NC}"
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

# Verify Kubernetes cluster access
kubectl cluster-info &> /dev/null || log_error "Unable to connect to Kubernetes cluster"

print_header "URL Shortener Pod Crash Test"

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

# Get service endpoint
SERVICE_URL="http://url-shortener-service.default.svc.cluster.local"

# Create a configmap with the crash test scripts
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: crash-test-scripts
data:
  memory-exhaustion.sh: |
    #!/bin/sh
    echo "Starting memory exhaustion attack..."
    
    SERVICE_URL="$SERVICE_URL"
    
    # Function to create a large payload
    create_large_payload() {
      # Generate a string with ~500KB of data
      large_string=\$(yes "XABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" | head -c 500000 | tr -d '\n')
      echo "{\"url\":\"https://example.com/\$large_string\"}"
    }
    
    # Send requests with large payloads in parallel
    for i in \$(seq 1 200); do
      echo "Sending large payload \$i/200"
      payload=\$(create_large_payload)
      curl -s -X POST -H "Content-Type: application/json" \\
        -d "\$payload" \\
        \$SERVICE_URL/shorten > /dev/null &
        
      # Send in batches to avoid overwhelming the client
      if (( i % 10 == 0 )); then
        wait
      fi
    done
    
    wait
    echo "Memory exhaustion attack completed"
  
  connection-flood.sh: |
    #!/bin/sh
    echo "Starting connection flood attack..."
    
    SERVICE_URL="$SERVICE_URL"
    
    # Run massive parallel requests
    for wave in \$(seq 1 20); do
      echo "Starting connection wave \$wave/20"
      for i in \$(seq 1 200); do
        random_str=\$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
        curl -s -X POST -H "Content-Type: application/json" \\
          -d "{\"url\":\"https://example.com/flood-\$wave-\$i-\$random_str\"}" \\
          \$SERVICE_URL/shorten > /dev/null &
      done
      
      # Small pause between waves
      sleep 0.5
    done
    
    wait
    echo "Connection flood attack completed"
    
  cpu-exhaust.sh: |
    #!/bin/sh
    echo "Starting CPU exhaustion attack..."
    
    SERVICE_URL="$SERVICE_URL"
    
    # Function to send requests in a tight loop
    send_requests() {
      for j in \$(seq 1 500); do
        curl -s -X POST -H "Content-Type: application/json" \\
          -d "{\"url\":\"https://example.com/cpu-\$1-\$j-\$(date +%s%N)\"}" \\
          \$SERVICE_URL/shorten > /dev/null &
        
        # Small delay to avoid local client issues
        if (( j % 50 == 0 )); then
          wait
        fi
      done
      wait
    }
    
    # Run multiple parallel request streams
    for i in \$(seq 1 8); do
      send_requests \$i &
    done
    
    wait
    echo "CPU exhaustion attack completed"
    
  combined-attack.sh: |
    #!/bin/sh
    echo "Starting combined attack..."
    
    SERVICE_URL="$SERVICE_URL"
    
    # Start CPU stress in background
    for i in \$(seq 1 4); do
      (
        for j in \$(seq 1 250); do
          curl -s -X POST -H "Content-Type: application/json" \\
            -d "{\"url\":\"https://example.com/combined-cpu-\$i-\$j-\$(date +%s%N)\"}" \\
            \$SERVICE_URL/shorten > /dev/null
        done
      ) &
    done
    
    # Start memory stress in background
    (
      # Generate large payloads
      for i in \$(seq 1 50); do
        large_string=\$(yes "XABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" | head -c 100000 | tr -d '\n')
        curl -s -X POST -H "Content-Type: application/json" \\
          -d "{\"url\":\"https://example.com/\$large_string\"}" \\
          \$SERVICE_URL/shorten > /dev/null &
          
        if (( i % 5 == 0 )); then
          wait
        fi
      done
    ) &
    
    # Start connection flood in background
    (
      for i in \$(seq 1 500); do
        curl -s -X POST -H "Content-Type: application/json" \\
          -d "{\"url\":\"https://example.com/flood-\$i-\$(date +%s%N)\"}" \\
          \$SERVICE_URL/shorten > /dev/null &
          
        if (( i % 50 == 0 )); then
          wait
        fi
      done
    ) &
    
    wait
    echo "Combined attack completed"
EOF

# Function to run specific attack type
run_attack() {
  local attack_type=$1
  local duration=$2
  local attack_name=$3
  
  print_header "Running $attack_name Attack"
  
  # Create the attack pod
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: url-shortener-$attack_type-attack
spec:
  containers:
  - name: attack-container
    image: curlimages/curl:7.83.1
    command: ["/bin/sh", "-c"]
    args:
    - |
      cp /config/$attack_type.sh /tmp/
      chmod +x /tmp/$attack_type.sh
      echo "Starting $attack_name attack..."
      /tmp/$attack_type.sh
      echo "Attack completed, keeping pod alive for logging..."
      sleep 30
    volumeMounts:
    - name: config-volume
      mountPath: /config
    resources:
      requests:
        cpu: 200m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi
  volumes:
  - name: config-volume
    configMap:
      name: crash-test-scripts
EOF
  
  # Wait for attack pod to start
  echo "Waiting for attack pod to start..."
  kubectl wait --for=condition=Ready pod/url-shortener-$attack_type-attack --timeout=60s
  
  # Monitor pods during the attack
  echo "Running $attack_name attack and monitoring pods..."
  
  # Track start time
  start_time=$(date +%s)
  end_time=$((start_time + duration))
  
  # Create a monitoring log file
  log_file="$attack_type-attack-log.csv"
  echo "Timestamp,Replicas,PodCount,RestartCount,PendingPods,CPUUsage" > "$log_file"
  
  # Function to collect and display metrics
  collect_metrics() {
    # Get pod metrics
    replicas=$(kubectl get hpa url-shortener-hpa -o jsonpath='{.status.currentReplicas}' 2>/dev/null || echo "N/A")
    pod_count=$(kubectl get pods -l app=url-shortener --no-headers | wc -l)
    restart_count=$(kubectl get pods -l app=url-shortener -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount}{"\n"}{end}' | awk '{sum+=$1} END {print sum}')
    pending_pods=$(kubectl get pods -l app=url-shortener --no-headers | grep Pending | wc -l)
    cpu_usage=$(kubectl top pods -l app=url-shortener --no-headers 2>/dev/null | awk '{sum+=$2} END {print sum}')
    
    # Log metrics
    timestamp=$(date +"%H:%M:%S")
    echo "$timestamp,$replicas,$pod_count,$restart_count,$pending_pods,$cpu_usage" >> "$log_file"
    
    # Display current state
    echo -e "${YELLOW}Time: $timestamp - Metrics: Replicas=$replicas, Pods=$pod_count, Restarts=$restart_count, Pending=$pending_pods, CPU=$cpu_usage${NC}"
    kubectl get pods -l app=url-shortener
    
    # Check for crashes
    if [ "$restart_count" -gt 0 ]; then
      echo -e "${RED}DETECTED POD CRASHES: $restart_count restart(s)${NC}"
    fi
  }
  
  # Monitor in a loop
  while [ $(date +%s) -lt $end_time ]; do
    collect_metrics
    sleep 5
  done
  
  # Stop attack pod
  echo "Stopping $attack_name attack..."
  kubectl delete pod url-shortener-$attack_type-attack --grace-period=1
  
  # Final metrics collection
  print_header "$attack_name Attack Complete"
  collect_metrics
  
  # Display pod logs if crashes occurred
  restart_count=$(kubectl get pods -l app=url-shortener -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount}{"\n"}{end}' | awk '{sum+=$1} END {print sum}')
  if [ "$restart_count" -gt 0 ]; then
    echo -e "${RED}Pod crashes detected during attack!${NC}"
    echo "Recent events:"
    kubectl get events --sort-by='.lastTimestamp' | grep url-shortener | tail -n 10
    
    # Get pod names with restarts
    crashed_pods=$(kubectl get pods -l app=url-shortener -o jsonpath='{range .items[*]}{.metadata.name}{","}{.status.containerStatuses[0].restartCount}{"\n"}{end}' | grep -v ",0")
    
    if [ ! -z "$crashed_pods" ]; then
      echo -e "${YELLOW}Pods with restarts:${NC}"
      echo "$crashed_pods"
      
      # Get previous logs from first crashed pod
      first_crashed_pod=$(echo "$crashed_pods" | head -n 1 | cut -d ',' -f 1)
      echo -e "${YELLOW}Logs from crashed pod $first_crashed_pod (previous instance):${NC}"
      kubectl logs $first_crashed_pod --previous || echo "No previous logs available"
    fi
  else
    echo -e "${GREEN}No pod crashes detected during $attack_name attack${NC}"
  fi
}

# Main menu for selecting attack type
select_attack_type() {
  echo -e "\n${YELLOW}Select an attack type to execute:${NC}"
  echo "1) Memory Exhaustion Attack"
  echo "2) Connection Flood Attack"
  echo "3) CPU Exhaustion Attack"
  echo "4) Combined Attack (Most likely to cause crashes)"
  echo "5) Run All Attacks Sequentially"
  echo "q) Quit"
  
  read -p "Enter selection [1-5 or q]: " selection
  
  case $selection in
    1)
      run_attack "memory-exhaustion" 120 "Memory Exhaustion"
      ;;
    2)
      run_attack "connection-flood" 120 "Connection Flood"
      ;;
    3)
      run_attack "cpu-exhaust" 120 "CPU Exhaustion"
      ;;
    4)
      run_attack "combined-attack" 180 "Combined"
      ;;
    5)
      run_attack "memory-exhaustion" 90 "Memory Exhaustion"
      sleep 30
      run_attack "connection-flood" 90 "Connection Flood"
      sleep 30
      run_attack "cpu-exhaust" 90 "CPU Exhaustion"
      sleep 30
      run_attack "combined-attack" 120 "Combined"
      ;;
    q|Q)
      echo "Exiting..."
      exit 0
      ;;
    *)
      echo -e "${RED}Invalid selection!${NC}"
      select_attack_type
      ;;
  esac
}

# Run the menu
select_attack_type

print_header "Attack Testing Complete"

# Final summary
final_replicas=$(kubectl get hpa url-shortener-hpa -o jsonpath='{.status.currentReplicas}')
total_restarts=$(kubectl get pods -l app=url-shortener -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount}{"\n"}{end}' | awk '{sum+=$1} END {print sum}')

echo -e "${BLUE}Test Summary:${NC}"
echo "Initial pod count: $initial_replicas"
echo "Final pod count: $final_replicas"
echo "Total pod restarts: $total_restarts"

if [ "$total_restarts" -gt 0 ]; then
  echo -e "${RED}Pod crashes were successfully induced!${NC}"
else
  echo -e "${YELLOW}No pod crashes detected. Your service is resilient or the attacks weren't intense enough.${NC}"
  echo "Consider:"
  echo "1. Running the combined attack for a longer duration"
  echo "2. Modifying the attack scripts to be more aggressive"
  echo "3. Checking if your service has memory/request limits that are too high"
fi

echo -e "\n${GREEN}URL Shortener crash testing completed! 🚀${NC}"
echo -e "${YELLOW}Check the *-attack-log.csv files for detailed metrics${NC}"