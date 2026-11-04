# Nomad Canary Deployment – Engineering Handover Runbook

**Project:** Nomad Canary Deployment with Automatic Rollback
**Repository:** https://github.com/amt-kwame-agyabeng/nomad-canary-demo
**Environment:** Local WSL2 development lab
**Deployment platform:** HashiCorp Nomad
**Service discovery and health monitoring:** HashiCorp Consul

---

## 1. Purpose

This runbook provides operational instructions for running, validating, troubleshooting, and recovering the Nomad canary deployment demonstration.

It is intended for engineers reviewing the implementation or reproducing the deployment in an isolated development environment.

**Important:** The current implementation uses Nomad and Consul development agents. It is a proof of concept and must not be treated as a production deployment configuration.

## 2. System Components

| Component | Responsibility |
|---|---|
| GitHub Actions | Build, test, publish, and initiate deployment |
| GitHub Container Registry | Store versioned application images |
| Self-hosted runner | Execute deployment commands in the local lab |
| Docker | Run the application container |
| Nomad | Schedule and manage application allocations |
| Consul | Register the service and perform health checks |
| Flask application | Expose application and health endpoints |
| `deploy.sh` | Validate and execute deployment operations |

## 3. Prerequisites

Before beginning, confirm that the following are available:

- WSL2 with Ubuntu.
- Docker Desktop running with WSL integration enabled.
- Docker CLI.
- Nomad CLI and agent.
- Consul CLI and agent.
- Git.
- Access to the GitHub repository.
- GitHub Actions enabled.
- A configured self-hosted runner with the required repository access.

Verify the tools:

```bash
docker version
nomad version
consul version
git --version
```

## 4. Start the Local Environment

### 4.1 Start Consul

Open a WSL terminal:

```bash
consul agent -dev -client=127.0.0.1
```

Keep this terminal running.

Verify membership:

```bash
consul members
```

Expected result: the local Consul agent is alive.

### 4.2 Start Nomad

Open another WSL terminal:

```bash
nomad agent -dev
```

Keep this terminal running.

Verify the Nomad node:

```bash
nomad node status
```

Expected result: the local Nomad node is ready.

### 4.3 Verify Docker

```bash
docker info
```

Confirm that the Docker daemon is accessible.

## 5. Verify the Application and Job Configuration

Navigate to the repository:

```bash
cd ~/nomad-canary-demo
```

Check the application source:

```bash
cat app/main.py
```

Validate the Nomad job configuration:

```bash
nomad job validate nomad-canary-demo.nomad
```

The configuration should validate successfully.

A `shutdown_delay` warning may appear because the service group does not explicitly configure a shutdown delay. This is a warning, not necessarily a validation failure, and should be reviewed before production use.

## 6. Deployment Procedure

### 6.1 Automated Deployment

The normal deployment process is initiated by pushing a change to the `main` branch.

```bash
git add .
git commit -m "Update application"
git push origin main
```

The GitHub Actions workflow performs two jobs.

**Build, Test and Publish**

- Checks out the source code.
- Builds the Docker image.
- Tests the healthy application response.
- Verifies the unhealthy endpoint returns HTTP 503.
- Publishes the image to GHCR.

**Deploy to Nomad**

- Runs on the configured self-hosted runner.
- Checks out the repository.
- Constructs the commit-specific image reference.
- Executes `deploy.sh`.
- Waits for the Nomad deployment to complete.
- Verifies the deployment result.

Monitor the workflow:

https://github.com/amt-kwame-agyabeng/nomad-canary-demo/actions

### 6.2 Manual Deployment

The deployment script accepts a job file and Docker image reference.

```bash
./deploy.sh nomad-canary-demo.nomad <image-reference>
```

Example:

```bash
./deploy.sh nomad-canary-demo.nomad \
  ghcr.io/amt-kwame-agyabeng/nomad-canary-demo:latest
```

For reproducible deployments, use a commit-specific image tag instead of `latest`.

The script validates the job, submits the deployment, waits for completion, and checks the latest deployment status and allocation counts.

## 7. Deployment Verification

After deployment, execute:

### Check job status

```bash
nomad job status nomad-canary-demo
```

Confirm:

- Job status is `running`.
- Latest deployment status is `successful`.
- The expected allocation is running.
- Healthy allocations meet the desired count.
- Unhealthy allocations are zero.

### Check job history

```bash
nomad job history nomad-canary-demo
```

### Check deployments

```bash
nomad job deployments nomad-canary-demo
```

### Check allocations

```bash
nomad job allocs nomad-canary-demo
```

### Check Consul health

```bash
curl -s \
  http://127.0.0.1:8500/v1/health/checks/nomad-canary-demo
```

### Check the application

Find the current allocation's dynamic host port from Nomad and run:

```bash
curl -i http://127.0.0.1:<allocated-port>/health
```

Expected result:

```text
HTTP/1.1 200 OK
```

The response should indicate:

```json
{
  "status": "healthy",
  "version": "1.0.0"
}
```

The version may differ depending on the deployed image.

## 8. Automatic Rollback Procedure

### 8.1 Failure Simulation

The demonstration simulates an unhealthy application using:

```hcl
env {
  HEALTH_STATUS = "unhealthy"
}
```

The application then returns HTTP 503 from `/health`.

This setting is for controlled testing only. Remove it when restoring the healthy configuration.

### 8.2 Expected Nomad Behaviour

The Nomad update configuration includes:

```hcl
update {
  max_parallel      = 1
  canary            = 1
  auto_promote      = true
  auto_revert       = true
  health_check      = "checks"
  min_healthy_time  = "10s"
  healthy_deadline  = "2m"
  progress_deadline = "5m"
}
```

When the canary does not satisfy the health requirements:

1. Nomad evaluates the deployment health.
2. The canary fails to become healthy.
3. The deployment reaches its progress deadline.
4. Nomad marks the deployment as failed.
5. Automatic rollback is initiated.
6. The previous stable job version is restored.

**Operational note:** The demonstration showed rollback after the progress deadline, not immediately after the first failed health check.

### 8.3 Verify Automatic Rollback

Run:

```bash
nomad job status nomad-canary-demo
```

Then:

```bash
nomad job history nomad-canary-demo
```

Confirm that:

- The failed deployment is recorded.
- The rollback deployment succeeds.
- The previous stable application version is running.
- The Consul health check returns to passing.

## 9. Manual Rollback Procedure

Manual rollback is required when automatic rollback is disabled or when an operator needs to initiate recovery.

### 9.1 Identify the Stable Version

```bash
nomad job history nomad-canary-demo
```

Identify the most recent stable job version.

### 9.2 Execute the Revert

```bash
nomad job revert nomad-canary-demo <stable-version>
```

Example from the completed experiment:

```bash
nomad job revert nomad-canary-demo 4
```

### 9.3 Verify Recovery

```bash
nomad job status nomad-canary-demo
```

Check the deployment:

```bash
nomad job deployments nomad-canary-demo
```

Check the application health endpoint using the current allocation's port:

```bash
curl -i http://127.0.0.1:<allocated-port>/health
```

Expected result: HTTP 200 and a healthy application response.

**Important:** Use the actual stable version identified from job history. Do not assume version 4 is the correct rollback target in a future deployment.

## 10. Troubleshooting Guide

| Symptom | Checks and recommended action |
|---|---|
| Nomad node unavailable | Confirm the Nomad development agent is running |
| Consul health check critical | Check Consul membership, allocation status, and application endpoint |
| Docker image pull failure | Check the image reference and GHCR package accessibility |
| Deployment remains pending | Inspect Nomad job status and allocation events |
| Canary becomes unhealthy | Inspect application health and Nomad deployment status |
| Automatic rollback does not occur | Verify `auto_revert`, deployment state, and update configuration |
| GitHub deployment job does not start | Check build job result, branch condition, and runner availability |
| Runner is offline | Start the runner using `./run.sh` in `~/actions-runner` |
| Docker driver unavailable | Start Docker Desktop and verify Docker connectivity |

Useful commands:

```bash
nomad status
nomad node status
nomad job status nomad-canary-demo
nomad job history nomad-canary-demo
nomad job allocs nomad-canary-demo
consul members
docker ps
```

## 11. Evidence and Verification Records

The repository contains a `deployment-verification/` directory with records from the experiments.

Important records include:

- `consul-application-health-check.json`
- `final-allocation-status.txt`
- `final-nomad-job-status.txt`
- `nomad-job-version-history.txt`
- `manual-rollback-failed-deployment.txt`
- `manual-rollback-final-job-status.txt`
- `manual-rollback-health-check.txt`
- `manual-rollback-job-history.txt`
- `manual-rollback-successful-deployment.txt`
- `github-actions-successful-deployment.txt`
- `github-actions-job-history.txt`

The failed manual deployment record was reconstructed from the terminal output because the deployment ID was no longer retrievable through the Nomad deployment-status command. It should therefore be treated as a manually documented experiment record rather than a direct deployment-status export.

---

## 12. GitHub Actions Failure-Path Validation

### Purpose

This test verifies that an unsuccessful Nomad canary deployment causes the GitHub Actions deployment job to fail while Nomad automatically restores the previous stable version.

Perform this test only in the isolated development lab.

### Pre-test checks

Confirm that:
- Nomad and Consul are running.
- The self-hosted GitHub Actions runner is online.
- The current Nomad job is healthy and stable.
- The Nomad update block has `canary = 1` and `auto_revert = true`.
- The normal job configuration does not contain an unhealthy health-status override.

Record the current stable job version before testing.

### Execute the controlled failure

1. Temporarily add the following environment block inside the Nomad task:

   ```hcl
   env {
     HEALTH_STATUS = "unhealthy"
   }
   ```

2. Validate the job specification:

   ```bash
   nomad job validate -var="image=ghcr.io/amt-kwame-agyabeng/nomad-canary-demo:latest" nomad-canary-demo.nomad
   ```

3. Commit and push the test configuration to the repository's `main` branch.

4. Monitor the GitHub Actions workflow.

### Expected GitHub Actions result

- Build, Test and Publish should complete successfully.
- Deploy to Nomad should fail when Nomad reports an unsuccessful rollout.
- The deployment script should return a non-zero exit status.

A failed deployment job is the expected result of this controlled negative test.

### Verify automatic rollback

Check the Nomad job:

```bash
nomad job status nomad-canary-demo
```

Review its version history:

```bash
nomad job history nomad-canary-demo
```

Check the Consul health status:

```bash
curl -s http://127.0.0.1:8500/v1/health/checks/nomad-canary-demo
```

Confirm that:
- The intentionally unhealthy version is no longer running.
- Nomad has successfully restored the previous stable configuration.
- One healthy allocation is running.
- No unhealthy allocations remain.
- Consul reports the application health check as passing.
- The application responds with HTTP 200.

### Recorded test results — 4 November 2026

| Item | Result |
|---|---|
| Previous stable job version | 10 |
| Unhealthy job version | 11 |
| Automatic rollback version | 12 |
| GitHub Actions deployment result | Failed |
| Final Nomad deployment | Successful |
| Final running allocation | 1 |
| Healthy allocations | 1 |
| Unhealthy allocations | 0 |
| Consul health status | Passing |
| Application health response | HTTP 200 |

GitHub Actions recorded the deployment job as started at 16:46:44 UTC and completed at 16:52:43 UTC with a failed result.

Nomad independently completed the automatic rollback, restoring the previous healthy configuration without manual intervention.

The complete test evidence is stored in:

`deployment-verification/github-actions-failure-test.txt`

### Restore the healthy configuration

After the test:
1. Remove the temporary `HEALTH_STATUS = "unhealthy"` environment block.
2. Validate the restored Nomad job specification.
3. Commit and push the healthy configuration.
4. Confirm that the subsequent GitHub Actions deployment succeeds.
5. Verify that the Nomad job and Consul health check remain healthy.

**Operational note:** The failed GitHub Actions deployment and successful Nomad rollback are separate outcomes. CI correctly reports the unsuccessful rollout, while Nomad independently restores the previously stable application.

## 13. Security and Operational Considerations

The current implementation is restricted to a local development lab.

Before production adoption, engineers should review:

- Nomad and Consul production configurations.
- Authentication and access-control policies.
- TLS and secure service communication.
- Self-hosted runner isolation and permissions.
- GitHub Actions permissions and third-party action pinning.
- Container image vulnerability scanning.
- Secret management.
- Network exposure and firewall rules.
- Persistent monitoring and alerting.
- Backup and recovery requirements.

The GitHub repository is public and uses a persistent self-hosted runner with access to local Docker and Nomad. Only trusted deployment code should run on that runner. Untrusted pull-request code must not be executed there.

Nomad and Consul development APIs must not be exposed to the public internet.

## 14. Production Readiness Review

Before adapting this implementation to a real environment, the reviewing engineer should confirm:

- [ ] Production Nomad cluster architecture is defined.
- [ ] Consul availability and service discovery are configured.
- [ ] Job update and rollback settings have been reviewed.
- [ ] Application health checks represent meaningful application health.
- [ ] Container images are immutable and traceable.
- [ ] CI/CD deployment permissions are appropriately restricted.
- [ ] Self-hosted runners are isolated and secured.
- [ ] Secrets are managed outside source control.
- [ ] Deployment failure and rollback scenarios have been tested.
- [ ] Logging, metrics, and alerting are configured.
- [ ] Recovery and escalation procedures are documented.

## 15. Demonstration Results

The completed proof of concept demonstrated:

| Scenario | Result |
|---|---|
| Healthy application deployment | Successful |
| Unhealthy canary deployment | Failed as expected |
| Automatic rollback | Successful |
| Manual rollback | Successful |
| GitHub Actions image build and tests | Successful |
| GitHub Actions deployment job | Successful |
| Final Nomad allocation | One running, healthy allocation |

The latest verified deployment was job version 7.

GitHub Actions workflow run #5 completed successfully in 1 minute 26 seconds.

## 16. Handover Notes

The engineer receiving this project should:

1. Review the repository README.
2. Review the Nomad job configuration.
3. Review the GitHub Actions workflow.
4. Review the deployment script.
5. Reproduce the healthy deployment.
6. Review the automatic rollback evidence.
7. Reproduce the manual rollback if required.
8. Complete the production-readiness checklist before considering any real deployment.

**Project repository:**
https://github.com/amt-kwame-agyabeng/nomad-canary-demo

**GitHub Actions runs:**
https://github.com/amt-kwame-agyabeng/nomad-canary-demo/actions

---



**End of Runbook**
