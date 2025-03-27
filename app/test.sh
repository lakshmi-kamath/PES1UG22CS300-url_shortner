#!/bin/bash

# Base URL of the application
BASE_URL="http://localhost:5001"

# Function to create a short URL
create_short_url() {
    local long_url="$1"
    
    response=$(curl -s -X POST "$BASE_URL/shorten" \
         -H "Content-Type: application/json" \
         -d "{\"url\":\"$long_url\"}")
    
    # Extract short URL using jq for reliable JSON parsing
    short_url=$(echo "$response" | jq -r '.short_url')
    
    # Verify that a short URL was extracted
    if [ -z "$short_url" ] || [ "$short_url" == "null" ]; then
        echo "Error: Failed to extract short URL"
        echo "Response was: $response"
        exit 1
    fi
    
    echo "$short_url"
}

# Function to test redirection
test_redirection() {
    local short_url="$1"
    local expected_url="$2"
    
    # Perform redirect and capture the actual redirected URL
    actual_url=$(curl -sS -L -o /dev/null -w "%{url_effective}" "$BASE_URL/$short_url")
    
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

# Test URLs
URLS=(
    "https://www.example.com/very/long/url/that/needs/shortening"
    "https://www.openai.com/research/advanced-language-models"
    "https://www.anthropic.com/product/claude-ai-assistant"
)

# Run tests
echo "Starting URL Shortener Redirection Tests"

# Store short URLs
declare -a SHORT_URLS=()

# Create short URLs
echo -e "\n===== URL Shortening Tests ====="
for url in "${URLS[@]}"; do
    short_url=$(create_short_url "$url")
    SHORT_URLS+=("$short_url")
    echo "Created short URL: $short_url for $url"
done

# Test redirections
echo -e "\n===== Redirection Tests ====="
for i in "${!URLS[@]}"; do
    test_redirection "${SHORT_URLS[i]}" "${URLS[i]}"
done

echo -e "\nTesting complete."