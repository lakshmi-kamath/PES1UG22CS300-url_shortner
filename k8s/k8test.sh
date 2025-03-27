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

echo -e "\nTesting complete. ✨"