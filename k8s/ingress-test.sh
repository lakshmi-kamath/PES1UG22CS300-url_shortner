#!/bin/bash

# Ensure script fails on any error
set -e

# Function to log error and exit
log_error() {
    echo "ERROR: $1" >&2
    exit 1
}

# Function to log success
log_success() {
    echo "✅ $1"
}

# Prerequisites check
command -v curl &> /dev/null || log_error "curl is not installed"
command -v jq &> /dev/null || log_error "jq is not installed"
command -v kubectl &> /dev/null || log_error "kubectl is not installed"

# Host values to test
HOST="shorturl.local"
INGRESS_NAME="url-shortener-ingress"
SERVICE_NAME="url-shortener-service"
LOCAL_PORT=8080

echo "===== URL Shortener Ingress Test (Local Version) ====="
echo "Testing host: $HOST via local port forwarding"

# Check if ingress exists
kubectl get ingress "$INGRESS_NAME" &> /dev/null || log_error "Ingress $INGRESS_NAME not found"
echo "Ingress $INGRESS_NAME found"

# Get ingress details
echo "Ingress details:"
kubectl get ingress "$INGRESS_NAME" -o wide

# Check if port-forward is already running
port_forward_pid=$(pgrep -f "kubectl port-forward svc/$SERVICE_NAME $LOCAL_PORT:80" || echo "")
if [ -z "$port_forward_pid" ]; then
    echo "Starting port-forward from service $SERVICE_NAME to localhost:$LOCAL_PORT..."
    kubectl port-forward svc/$SERVICE_NAME $LOCAL_PORT:80 &
    PORT_FORWARD_PID=$!
    echo "Port-forward started with PID: $PORT_FORWARD_PID"
    # Give time for port-forwarding to establish
    sleep 3
    PORT_FORWARD_STARTED=true
else
    echo "Port-forward to $SERVICE_NAME already running with PID: $port_forward_pid"
    PORT_FORWARD_STARTED=false
fi

# Function to clean up port-forward on exit
cleanup() {
    if [ "$PORT_FORWARD_STARTED" = true ]; then
        echo "Stopping port-forward with PID: $PORT_FORWARD_PID"
        kill $PORT_FORWARD_PID 2>/dev/null || true
    fi
}

# Set up cleanup on script exit
trap cleanup EXIT

echo -e "\n===== Testing API Access ====="

# Test HTTP welcome endpoint
echo "Testing welcome endpoint..."
http_response=$(curl -s -H "Host: $HOST" http://localhost:$LOCAL_PORT/)
if [[ "$http_response" == *"Welcome to URL Shortener"* ]]; then
    log_success "Welcome endpoint works"
else
    echo "⚠️ Welcome endpoint returned unexpected response:"
    echo "$http_response"
fi

echo -e "\n===== Testing URL Shortening ====="

# Test URL shortening
LONG_URL="https://www.example.com/test/ingress/path"
echo "Creating short URL for: $LONG_URL"

short_url_response=$(curl -s -X POST -H "Host: $HOST" -H "Content-Type: application/json" \
                   -d "{\"url\":\"$LONG_URL\"}" \
                   http://localhost:$LOCAL_PORT/shorten)

echo "Response: $short_url_response"

# Check if jq is available for parsing JSON
if command -v jq &> /dev/null; then
    # Extract the short URL from the response using jq
    SHORT_URL=$(echo "$short_url_response" | jq -r '.short_url')
    
    if [ "$SHORT_URL" != "null" ] && [ -n "$SHORT_URL" ]; then
        # Extract just the code part if it's a full URL
        SHORT_CODE=$(echo "$SHORT_URL" | grep -o '[^/]*$')
        log_success "Created short URL code: $SHORT_CODE"
        
        # Test redirection
        echo -e "\n===== Testing Redirection ====="
        echo "Testing redirection for short code: $SHORT_CODE"
        
        # Use curl to follow redirects and get final URL
        redirect_result=$(curl -s -L -o /dev/null -w "%{url_effective}" -H "Host: $HOST" "http://localhost:$LOCAL_PORT/$SHORT_CODE")
        
        if [ "$redirect_result" == "$LONG_URL" ]; then
            log_success "Redirection successful: $SHORT_CODE → $LONG_URL"
        else
            echo "⚠️ Redirection failed:"
            echo "  Expected: $LONG_URL"
            echo "  Actual: $redirect_result"
        fi
    else
        echo "⚠️ Failed to extract short URL from response:"
        echo "$short_url_response"
    fi
else
    echo "⚠️ jq not installed, skipping JSON parsing of short URL response:"
    echo "$short_url_response"
fi

echo -e "\n===== Ingress Configuration Check ====="

# Check TLS configuration
tls_hosts=$(kubectl get ingress "$INGRESS_NAME" -o jsonpath='{.spec.tls[0].hosts[0]}' 2>/dev/null)
if [ -n "$tls_hosts" ]; then
    echo "TLS is configured for hosts: $tls_hosts"
    
    # Check TLS secret
    tls_secret=$(kubectl get ingress "$INGRESS_NAME" -o jsonpath='{.spec.tls[0].secretName}')
    if kubectl get secret "$tls_secret" &> /dev/null; then
        log_success "TLS secret $tls_secret exists"
    else
        echo "⚠️ Warning: TLS secret $tls_secret does not exist yet"
        echo "This is expected if cert-manager hasn't yet issued the certificate."
    fi
else
    echo "⚠️ No TLS configuration found in ingress"
fi

# Check important ingress annotations
annotations=$(kubectl get ingress "$INGRESS_NAME" -o jsonpath='{.metadata.annotations}')

if [[ "$annotations" == *"kubernetes.io/ingress.class"* ]]; then
    log_success "Ingress class annotation is set"
else
    echo "⚠️ Missing kubernetes.io/ingress.class annotation"
fi

if [[ "$annotations" == *"cert-manager.io/cluster-issuer"* ]]; then
    log_success "cert-manager cluster-issuer annotation is set"
else
    echo "⚠️ Missing cert-manager.io/cluster-issuer annotation"
fi

echo -e "\n===== Test Complete ====="
echo "Local testing for URL Shortener completed. ✨"