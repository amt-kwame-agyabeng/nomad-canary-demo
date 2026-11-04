#!/usr/bin/env bash

set -Eeuo pipefail

JOB_FILE="${1:-nomad-canary-demo.nomad}"
IMAGE="${2:-}"

JOB_ID="nomad-canary-demo"

if [[ ! -f "$JOB_FILE" ]]; then
    echo "ERROR: Job file not found: $JOB_FILE"
    exit 1
fi

if [[ -z "$IMAGE" ]]; then
    echo "ERROR: Docker image reference was not provided."
    echo "Usage: ./deploy.sh <job-file> <image-reference>"
    exit 1
fi

echo "======================================"
echo " Nomad Canary Deployment"
echo "======================================"
echo "Image: $IMAGE"

# Check prerequisites
for cmd in nomad jq docker; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: Required command not found: $cmd"
        exit 1
    fi
done

# Validate job configuration
echo "[1/3] Validating Nomad job..."

nomad job validate -var="image=$IMAGE" "$JOB_FILE"

# Submit the job and wait for deployment completion
echo "[2/3] Submitting job and waiting for deployment..."

if ! nomad job run -detach=false -var="image=$IMAGE" "$JOB_FILE"; then
    echo "ERROR: Nomad deployment failed."
    exit 1
fi

# Verify deployment result
echo "[3/3] Verifying deployment health..."

STATUS_JSON="$(nomad job status -json "$JOB_ID")"

DEPLOYMENT_STATUS="$(echo "$STATUS_JSON" | jq -r '.[0].LatestDeployment.Status // "unknown"')"

RUNNING_ALLOCATIONS="$(echo "$STATUS_JSON" | jq '[.[0].Summary.Summary[] | .Running] | add // 0')"

FAILED_ALLOCATIONS="$(echo "$STATUS_JSON" | jq '[.[0].Summary.Summary[] | .Failed] | add // 0')"

echo "Deployment status: $DEPLOYMENT_STATUS"
echo "Running allocations: $RUNNING_ALLOCATIONS"
echo "Failed allocations: $FAILED_ALLOCATIONS"

if [[ "$DEPLOYMENT_STATUS" != "successful" ]]; then
    echo "ERROR: Deployment was not successful."
    exit 1
fi

if [[ "$RUNNING_ALLOCATIONS" -lt 1 || "$FAILED_ALLOCATIONS" -gt 0 ]]; then
    echo "ERROR: Allocation health verification failed."
    exit 1
fi

echo "======================================"
echo " Deployment completed successfully!"
echo "======================================"
