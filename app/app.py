import os
import string
import random
from flask import Flask, request, redirect, jsonify
import redis
import validators
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
import time
app = Flask(__name__)

REQUEST_COUNT = Counter(
    'url_shortener_request_count', 
    'App Request Count', 
    ['app_name', 'method', 'endpoint', 'http_status']
)
REQUEST_LATENCY = Histogram(
    'url_shortener_request_latency_seconds', 
    'Request latency in seconds', 
    ['app_name', 'endpoint']
)
URL_CREATION_COUNT = Counter(
    'url_shortener_creation_count', 
    'URL Creation Count', 
    ['app_name']
)
URL_REDIRECT_COUNT = Counter(
    'url_shortener_redirect_count', 
    'URL Redirect Count', 
    ['app_name']
)
# Get Redis host from environment variable, default to 'redis'
REDIS_HOST = os.environ.get('REDIS_HOST', 'redis')

# Initialize Redis connection with retry
def get_redis_client():
    try:
        return redis.Redis(
            host=REDIS_HOST, 
            port=6379, 
            db=0, 
            socket_connect_timeout=5,
            retry_on_timeout=True
        )
    except redis.exceptions.ConnectionError:
        print(f"Failed to connect to Redis at {REDIS_HOST}")
        return None

redis_client = get_redis_client()

def generate_short_url(length=6):
    """
    Generate a random short URL of specified length.
    Uses alphanumeric characters.
    """
    characters = string.ascii_letters + string.digits
    while True:
        short_url = ''.join(random.choice(characters) for _ in range(length))
        
        # Ensure the generated short URL is unique
        if not redis_client.exists(f"url:{short_url}"):
            return short_url

@app.before_request
def before_request():
    request.start_time = time.time()

@app.after_request
def after_request(response):
    request_latency = time.time() - request.start_time
    REQUEST_LATENCY.labels('url_shortener', request.path).observe(request_latency)
    REQUEST_COUNT.labels('url_shortener', request.method, request.path, response.status_code).inc()
    return response

# Add Prometheus metrics endpoint
@app.route('/metrics')
def metrics():
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}



@app.route('/shorten', methods=['POST'])
def shorten_url():
    """
    Endpoint to shorten a long URL
    """
    long_url = request.json.get('url')
    
    if not long_url:
        return jsonify({"error": "URL is required"}), 400
    
    # Validate URL format
    if not validators.url(long_url):
        return jsonify({"error": "Invalid URL format"}), 400
    
    # Check if URL already exists
    existing_short_url = redis_client.get(f"original:{long_url}")
    
    if existing_short_url:
        # If the URL has been shortened before, return existing short URL
        return jsonify({
            "short_url": existing_short_url.decode('utf-8'),
            "original_url": long_url
        }), 200
    
    # Generate a new short URL
    short_url = generate_short_url()
    
    # Store mappings in Redis
    # Map short URL to original URL
    redis_client.set(f"url:{short_url}", long_url)
    # Map original URL to short URL for quick lookup
    redis_client.set(f"original:{long_url}", short_url)
    
    # Increment URL creation metric
    URL_CREATION_COUNT.labels('url_shortener').inc()
    
    return jsonify({
        "short_url": short_url,
        "original_url": long_url
    }), 201

@app.route('/<short_url>', methods=['GET'])
def redirect_to_url(short_url):
    """
    Redirect short URL to original long URL
    """
    original_url = redis_client.get(f"url:{short_url}")
    
    if original_url:
        # Decode and redirect to the original URL
        decoded_url = original_url.decode('utf-8')
        # Increment URL redirect metric
        URL_REDIRECT_COUNT.labels('url_shortener').inc()
        return redirect(decoded_url)
    
    return jsonify({"error": "URL not found"}), 404
@app.route('/', methods=['GET'])
def home():
    """
    Simple home route
    """
    return jsonify({
        "message": "Welcome to URL Shortener",
        "endpoints": {
            "shorten": "POST /shorten with JSON body {\"url\": \"long_url\"}",
            "redirect": "GET /<short_url>"
        }
    }), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)