#!/bin/bash

# Ensure script fails on any error
set -e

# Function to log error and exit
log_error() {
    echo "ERROR: $1" >&2
    exit 1
}

# Function to create a short URL with local port-forward
create_short_url() {
    local long_url="$1"
    local base_url="$2"
    
    # Validate inputs
    [ -z "$long_url" ] && log_error "Long URL is empty"
    [ -z "$base_url" ] && log_error "Base URL is empty"

    # Require jq for JSON parsing
    command -v jq &> /dev/null || log_error "jq is not installed. Please install jq."

    # Perform URL shortening request
    response=$(curl -s -X POST "$base_url/shorten" \
         -H "Content-Type: application/json" \
         -d "{\"url\":\"$long_url\"}") || log_error "Curl request failed"
    
    # Extract short URL
    short_url=$(echo "$response" | jq -r '.short_url')
    
    # Validate short URL
    if [ -z "$short_url" ] || [ "$short_url" == "null" ]; then
        echo "Error: Failed to extract short URL"
        echo "Response was: $response"
        exit 1
    fi
    
    echo "$short_url"
}

# Function to test redirection with local port-forward
test_redirection() {
    local short_url="$1"
    local expected_url="$2"
    local base_url="$3"
    
    # Perform redirect and capture the actual redirected URL
    actual_url=$(curl -sS -L -o /dev/null -w "%{url_effective}" "$base_url/$short_url")
    
    if [ "$actual_url" == "$expected_url" ]; then
        echo "✅ Redirection successful: $short_url → $expected_url"
    else
        echo "❌ Redirection failed:"
        echo "   Short URL: $short_url"
        echo "   Expected: $expected_url"
        echo "   Actual:   $actual_url"
        exit 1
    fi
}
# New function to test pod deletion resilience
test_pod_deletion_resilience() {
    local base_url="$1"
    
    echo "=== Pod Deletion Resilience Test ==="
    
    # Get initial pod count
    initial_pod_count=$(kubectl get pods -l app=url-shortener | grep Running | wc -l)
    echo "Initial pod count: $initial_pod_count"
    
    # Get current pods
    pods=($(kubectl get pods -l app=url-shortener -o jsonpath='{.items[*].metadata.name}'))
    
    if [ ${#pods[@]} -eq 0 ]; then
        log_error "No URL Shortener pods found"
    fi
    
    # Select a pod to delete
    pod_to_delete=${pods[0]}
    echo "Selected pod for deletion: $pod_to_delete"
    
    # Use a previously created URL for resilience testing
    original_long_url="https://www.example.com/very/long/url/that/needs/shortening"
    pre_deletion_short_url=$(create_short_url "$original_long_url" "$base_url")
    echo "Created pre-deletion short URL: $pre_deletion_short_url"
    
    # Delete the selected pod
    kubectl delete pod "$pod_to_delete"
    
    # Wait and verify pod replacement
    echo "Waiting for pod replacement..."
    
    # Wait for new pod to be in Running state (with timeout)
    timeout=180  # 3 minutes
    while [ $timeout -gt 0 ]; do
        current_pod_count=$(kubectl get pods -l app=url-shortener | grep Running | wc -l)
        
        if [ "$current_pod_count" -ge "$initial_pod_count" ]; then
            echo "Pod replaced successfully"
            break
        fi
        
        sleep 5
        ((timeout-=5))
    done
    
    # Verify pod replacement
    if [ $timeout -le 0 ]; then
        log_error "Pod replacement timed out after 3 minutes"
    fi
    
    # Verify application functionality after pod deletion
    echo "Checking application responsiveness..."
    
    # Try creating a new short URL using another existing URL
    new_long_url="https://theuselessweb.com/very/long/url/that/needs/shortening"
    post_deletion_short_url=$(create_short_url "$new_long_url" "$base_url")
    echo "Created post-deletion short URL: $post_deletion_short_url"
    
    # Verify original short URL still works
    echo "Verifying original short URL redirection..."
    test_redirection "$pre_deletion_short_url" "$original_long_url" "$base_url"
    
    # Verify new short URL works
    echo "Verifying new short URL redirection..."
    test_redirection "$post_deletion_short_url" "$new_long_url" "$base_url"
    
    echo "✅ Pod Deletion Resilience Test Passed:"
    echo "   - Original pod deleted successfully"
    echo "   - Replacement pod created"
    echo "   - Application remained responsive"
    echo "   - Previous short URLs still work"
    echo "   - New short URLs can be created"
}


# Prerequisite checks
command -v kubectl &> /dev/null || log_error "kubectl is not installed"
command -v curl &> /dev/null || log_error "curl is not installed"
command -v jq &> /dev/null || log_error "jq is not installed"

# Verify Kubernetes cluster access
kubectl cluster-info &> /dev/null || log_error "Unable to connect to Kubernetes cluster"

# Use local port-forward
BASE_URL="http://localhost:8080"
echo "Testing URL Shortener at: $BASE_URL"

# Recommend port-forwarding
echo "IMPORTANT: Ensure you have run 'kubectl port-forward service/url-shortener-service 8080:80' in another terminal"
echo "Waiting 5 seconds to allow port-forward to be established..."
sleep 5

# Test URLs
URLS=(
    "https://www.example.com/very/long/url/that/needs/shortening"
    "https://www.openai.com/research/advanced-language-models"
    "https://www.anthropic.com/product/claude-ai-assistant"
)

# Run tests
echo "Starting URL Shortener Redirection Tests in Kubernetes"

# Check pods
echo "Verifying services..."
kubectl get pods

# Store short URLs
declare -a SHORT_URLS=()

# Create short URLs
echo -e "\n===== URL Shortening Tests ====="
for url in "${URLS[@]}"; do
    short_url=$(create_short_url "$url" "$BASE_URL")
    SHORT_URLS+=("$short_url")
    echo "Created short URL: $short_url for $url"
done

# Test redirections
echo -e "\n===== Redirection Tests ====="
for i in "${!URLS[@]}"; do
    test_redirection "${SHORT_URLS[i]}" "${URLS[i]}" "$BASE_URL"
done

# Additional Kubernetes-specific tests
echo -e "\n===== Kubernetes Deployment Tests ====="

# Check deployments
echo "Checking URL Shortener deployment status..."
kubectl rollout status deployment/url-shortener-deployment

# Check Redis deployment
echo "Checking Redis deployment status..."
kubectl rollout status deployment/redis-deployment

# Check services
echo "Verifying services..."
kubectl get services

# Add Pod Deletion Resilience Test
echo -e "\n===== Pod Deletion Resilience Test ====="
test_pod_deletion_resilience "$BASE_URL"

# Check pods
echo "Verifying services..."
kubectl get pods


echo -e "\nTesting complete. ✨"