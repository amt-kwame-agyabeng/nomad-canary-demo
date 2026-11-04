import os
from flask import Flask, jsonify

app = Flask(__name__)

APP_VERSION = os.getenv("APP_VERSION", "1.0.0")


@app.route("/")
def home():
    return jsonify({
        "service": "Nomad Canary Demo",
        "version": APP_VERSION,
        "message": "Application is running"
    })


@app.route("/health")
def health():
    health_status = os.getenv("HEALTH_STATUS", "healthy")

    if health_status != "healthy":
        return jsonify({
            "status": "unhealthy",
            "version": APP_VERSION
        }), 503

    return jsonify({
        "status": "healthy",
        "version": APP_VERSION
    }), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
