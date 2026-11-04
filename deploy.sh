#!/usr/bin/env bash

set -Eeuo pipefail

JOB_FILE="${1:-nomad-canary-demo.nomad}"
JOB_ID="nomad-canary-demo"

if [[ ! -f "$JOB_FILE" ]]; then
    echo "ERROR: Job file not found: $JOB_FILE"
    exit 1
fi

echo "======================================"
echo " Nomad Canary Deployment"
echo "======================================"

# Check prerequisites
if ! command -v nomad >/dev/null 2>&1; then
    echo "ERROR: Nomad CLI is not installed."
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is not installed."
    exit 1
fi

# Validate job configuration
echo "[1/3] Validating Nomad job..."

nomad job validate "$JOB_FILE"

# Submit the job and wait for deployment completion
echo "[2/3] Submitting job and waiting for deployment..."

if ! nomad job run -detach=false "$JOB_FILE"; then
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
