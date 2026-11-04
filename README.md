# Nomad Canary Deployment with Automatic Rollback

## 1. Project Overview

This project demonstrates an automated canary deployment pipeline using **HashiCorp Nomad**, **Consul**, **Docker**, **GitHub Actions**, and **GitHub Container Registry (GHCR)**.

The objective is to demonstrate how an application can be built, tested, published, and deployed to a Nomad cluster through a CI/CD pipeline, while using health checks and automatic rollback to reduce the risk of deploying unhealthy application versions.

The project also demonstrates manual recovery using Nomad's job revert functionality.

This implementation runs in a local development environment using WSL2 and Docker Desktop. It is intended as a proof of concept and is not configured as a production deployment.

## 2. Project Objectives

The main objectives are to:

- Build and containerize a sample web application.
- Automatically build and test Docker images through GitHub Actions.
- Publish versioned images to GitHub Container Registry.
- Deploy application updates to HashiCorp Nomad.
- Use Consul for application health monitoring.
- Configure Nomad canary deployments.
- Demonstrate automatic rollback when a deployment fails its health requirements.
- Demonstrate manual rollback using `nomad job revert`.
- Ensure the CI/CD pipeline reports deployment failures instead of treating job submission alone as success.
- Provide documentation and a review checklist for engineers.

## 3. Technology Stack

| Technology | Purpose |
|---|---|
| HashiCorp Nomad | Workload scheduling and deployment management |
| HashiCorp Consul | Service registration and health checks |
| Docker | Application containerization |
| GitHub Actions | CI/CD automation |
| GitHub Container Registry | Docker image storage |
| Python | Application development |
| Flask | Web application framework |
| Gunicorn | Python application server |
| Bash | Deployment automation |
| Ubuntu on WSL2 | Local development environment |

## 4. Architecture

The pipeline follows this sequence:

1. A developer pushes changes to the `main` branch.
2. GitHub Actions checks out the repository.
3. Docker builds the application image.
4. The application is tested using its health endpoint.
5. The pipeline verifies that an intentionally unhealthy configuration returns HTTP 503.
6. The image is published to GitHub Container Registry.
7. GitHub Actions dispatches the deployment job to a self-hosted runner.
8. The runner executes `deploy.sh`.
9. The script validates the Nomad job configuration and submits the deployment.
10. Nomad creates a canary allocation and evaluates its health.
11. Consul checks the application's `/health` endpoint.
12. Nomad promotes a healthy deployment or automatically reverts an unsuccessful deployment.

### Architecture Flow

```text
Developer
    |
    | Push to main
    v
GitHub Repository
    |
    v
GitHub Actions
    |
    +--------------------------+
    |                          |
    v                          v
Build Docker Image       Run Application Tests
    |                          |
    +------------+-------------+
                 |
                 v
       GitHub Container Registry
                 |
                 v
       Self-Hosted GitHub Runner
                 |
                 v
            deploy.sh
                 |
                 v
          Nomad Cluster
                 |
                 v
          Canary Allocation
                 |
                 v
           Consul Health Check
                 |
          +------+------+
          |             |
       Healthy       Unhealthy
          |             |
          v             v
     Promote        Auto Revert
     Deployment     to Stable Version
```

## 5. Application Details

The application is a lightweight Flask web service.

### Available Endpoints

| Endpoint | Description |
|---|---|
| `/` | Returns application information and version |
| `/health` | Returns the application's health status |

### Health Check Behaviour

The application uses an environment variable called `HEALTH_STATUS` to control its health response.

When the application is healthy:

- HTTP status: `200 OK`
- Response status: `healthy`

When the application is configured as unhealthy:

- HTTP status: `503 Service Unavailable`
- Response status: `unhealthy`

This makes it possible to simulate a failed deployment without introducing an actual application crash.

The `APP_VERSION` environment variable identifies the application version.

## 6. Repository Structure

```text
nomad-canary-demo/
│
├── app/
│   └── main.py
│
├── .github/
│   └── workflows/
│       └── deploy.yml
│
├── deployment-verification/
│   ├── consul-application-health-check.json
│   ├── final-allocation-status.txt
│   ├── final-nomad-job-status.txt
│   ├── manual-rollback-failed-deployment.txt
│   ├── manual-rollback-final-job-status.txt
│   ├── manual-rollback-health-check.txt
│   ├── manual-rollback-job-history.txt
│   ├── manual-rollback-successful-deployment.txt
│   ├── nomad-job-version-history.txt
│   ├── github-actions-successful-deployment.txt
│   └── github-actions-job-history.txt
│
├── .dockerignore
├── .gitignore
├── Dockerfile
├── deploy.sh
├── nomad-canary-demo.nomad
├── README.md
└── requirements.txt
```

The `deployment-verification/` directory contains command-line evidence collected during the deployment experiments.

## 7. Prerequisites

The following tools are required:

- Windows 11 or another supported operating system.
- WSL2 with Ubuntu.
- Docker Desktop with WSL integration enabled.
- Docker CLI.
- HashiCorp Nomad CLI and agent.
- HashiCorp Consul CLI and agent.
- Git.
- GitHub account.
- GitHub Actions enabled for the repository.
- A configured GitHub self-hosted runner for Nomad deployment.

The local Nomad and Consul agents must remain available while the deployment workflow is running.

### Important

This project uses Nomad and Consul development mode for local testing. Development mode is not suitable for production environments.

## 8. Local Environment Setup

### 8.1 Start Consul

Open a WSL terminal and run:

```bash
consul agent -dev -client=127.0.0.1
```

Keep the terminal open.

Verify the agent:

```bash
consul members
```

### 8.2 Start Nomad

Open another WSL terminal and run:

```bash
nomad agent -dev
```

Keep this terminal open as well.

Verify Nomad:

```bash
nomad node status
```

Confirm that the local Nomad node is available.

### 8.3 Verify Docker

```bash
docker version
```

Confirm that both the Docker client and server are available.

## 9. Running the Application Locally

Clone the repository:

```bash
git clone https://github.com/amt-kwame-agyabeng/nomad-canary-demo.git
```

Navigate into the project:

```bash
cd nomad-canary-demo
```

Build the Docker image:

```bash
docker build -t nomad-canary-demo:local .
```

Start the container:

```bash
docker run -d \
  --name nomad-canary-demo-test \
  -p 5000:5000 \
  nomad-canary-demo:local
```

Test the application:

```bash
curl http://localhost:5000/
```

Check application health:

```bash
curl -i http://localhost:5000/health
```

Expected health response:

```json
{
  "status": "healthy",
  "version": "1.0.0"
}
```

Clean up the test container:

```bash
docker rm -f nomad-canary-demo-test
```

## 10. GitHub Actions CI/CD Pipeline

The workflow is defined in:

```text
.github/workflows/deploy.yml
```

It is triggered by:

- A push to the `main` branch.
- A manually initiated `workflow_dispatch` event.

The workflow contains two jobs.

### Job 1: Build, Test and Publish

This job runs on a GitHub-hosted Ubuntu runner.

Its responsibilities include:

1. Checking out the repository.
2. Setting up Docker Buildx.
3. Building the Docker image.
4. Starting a test container.
5. Testing the `/health` endpoint.
6. Testing the unhealthy response and confirming HTTP 503.
7. Cleaning up test containers.
8. Authenticating with GitHub Container Registry.
9. Publishing the image.

Images are tagged using the Git commit SHA and `latest`.

Example:

```text
ghcr.io/amt-kwame-agyabeng/nomad-canary-demo:<commit-sha>
ghcr.io/amt-kwame-agyabeng/nomad-canary-demo:latest
```

### Job 2: Deploy to Nomad

This job runs on the configured self-hosted Linux runner.

It depends on the successful completion of the build job.

The deployment job:

1. Checks out the repository.
2. Constructs the image reference using the current commit SHA.
3. Executes `deploy.sh`.
4. Waits for Nomad deployment completion.
5. Verifies deployment status and allocation counts.

The deployment job is restricted to the `main` branch and the supported push or manual workflow events.

### GitHub Actions Configuration

The repository requires:

- GitHub Actions enabled.
- Appropriate action permissions and allowlist entries.
- `GITHUB_TOKEN` permissions for publishing packages.
- A registered self-hosted runner with the labels `self-hosted`, `Linux`, and `X64`.

The runner must have access to the local Docker and Nomad environments.

**Security note:** A persistent self-hosted runner attached to a public repository introduces additional security risk. Only trusted code should be deployed through this runner. Pull-request workflows must not be allowed to execute untrusted code on it. Do not expose the local Nomad or Consul APIs publicly or provide production credentials to this demonstration environment.

## 11. Nomad Canary Deployment Configuration

The Nomad job configuration is defined in:

```text
nomad-canary-demo.nomad
```

The deployment uses the following update settings:

| Setting | Value | Purpose |
|---|---|---|
| `max_parallel` | `1` | Limits simultaneous updates |
| `canary` | `1` | Creates one canary allocation |
| `auto_promote` | `true` | Automatically promotes a healthy canary |
| `auto_revert` | `true` | Reverts an unsuccessful deployment |
| `health_check` | `checks` | Uses service health checks |
| `min_healthy_time` | `10s` | Minimum healthy period |
| `healthy_deadline` | `2m` | Maximum time to become healthy |
| `progress_deadline` | `5m` | Maximum deployment progress period |

### Health Monitoring

Consul registers the application service and checks its health endpoint.

The health check uses:

```hcl
check {
  name     = "application-health"
  type     = "http"
  path     = "/health"
  interval = "10s"
  timeout  = "2s"
}
```

Nomad uses the registered health check when evaluating the deployment.

The job uses host networking in this local WSL environment because the required Nomad bridge CNI plugin was unavailable.

## 12. Deployment Script

The deployment script is:

```text
deploy.sh
```

It automates the following operations:

1. Checks required command-line tools.
2. Validates the Nomad job configuration.
3. Submits the job using the specified Docker image.
4. Waits for deployment completion.
5. Retrieves the Nomad job status.
6. Checks the latest deployment status.
7. Checks running and failed allocation counts.
8. Returns a non-zero exit status when deployment verification fails.

### Usage

```bash
./deploy.sh nomad-canary-demo.nomad <image-reference>
```

Example:

```bash
./deploy.sh nomad-canary-demo.nomad \
  ghcr.io/amt-kwame-agyabeng/nomad-canary-demo:latest
```

The CI/CD workflow uses the commit-specific image tag rather than relying on `latest`.

## 13. Deployment Experiments and Results

Three deployment scenarios were tested.

### Experiment 1: Successful Deployment

A healthy application version was submitted to Nomad.

Results:

- Nomad created the deployment.
- The canary allocation passed its health checks.
- Nomad promoted the canary.
- The deployment completed successfully.
- One healthy allocation remained running.

### Experiment 2: Automatic Rollback

The application configuration was intentionally changed to:

```hcl
env {
  HEALTH_STATUS = "unhealthy"
}
```

The updated job was submitted while automatic rollback was enabled.

Results:

- Nomad created a new canary allocation.
- The application returned HTTP 503 from its health endpoint.
- The canary did not become healthy.
- The deployment failed after reaching its progress deadline.
- Nomad automatically initiated a rollback.
- The previous stable version was restored.

The automatic rollback was confirmed through Nomad deployment status, job history, allocation status, and Consul health-check results.

**Important:** In this experiment, rollback occurred after the deployment progress deadline. It was not an instantaneous response to the first HTTP 503 response.

### Experiment 3: Manual Rollback

A second failure simulation was performed with:

```hcl
auto_revert = false
```

The unhealthy application configuration was retained.

The deployment failed because its canary did not meet the health requirements.

The operator then executed:

```bash
nomad job revert nomad-canary-demo 4
```

Results:

- The failed deployment was not automatically reverted.
- The previous stable job version was identified.
- The operator manually reverted to job version 4.
- Nomad created job version 6.
- The manual rollback deployment completed successfully.
- The previous healthy application allocation was restored.

The successful manual rollback took approximately 14 seconds in this experiment.

## 14. Latest CI/CD Deployment Verification

The GitHub Actions workflow completed successfully.

**Workflow:** Retry automated Nomad deployment workflow #5

**Commit:** `0d3d699`

**Branch:** `main`

**Result:** Success

**Total duration:** 1 minute 26 seconds

The self-hosted runner reported:

```text
Running job: Deploy to Nomad
Job Deploy to Nomad completed with result: Succeeded
```

The corresponding Nomad deployment was verified with:

```text
Status = running

Latest Deployment
Status = successful
Description = Deployment completed successfully

Deployed
Task Group  Auto Revert  Promoted  Desired  Canaries  Placed  Healthy  Unhealthy
web         true         true      1        1         1       1        0
```

The deployed application was running as job version 7.

This confirms that the GitHub Actions pipeline successfully built, published, and deployed the application to the local Nomad environment.

## 15. Verification Commands

### Check Nomad Job Status

```bash
nomad job status nomad-canary-demo
```

### Check Job History

```bash
nomad job history nomad-canary-demo
```

### Check Deployments

```bash
nomad job deployments nomad-canary-demo
```

### Check Allocations

```bash
nomad job allocs nomad-canary-demo
```

### Check Consul Service Health

```bash
curl -s \
  http://127.0.0.1:8500/v1/health/checks/nomad-canary-demo
```

### Check Application Health

Use the current allocation's assigned dynamic host port:

```bash
curl -i http://127.0.0.1:<allocated-port>/health
```

The expected successful response is HTTP 200.

## 16. Manual Recovery Procedure

If automatic rollback is disabled or manual intervention is required:

1. Identify the failed deployment.
2. Inspect the job history.
3. Identify the previous stable version.
4. Execute the revert command.
5. Wait for the rollback deployment to complete.
6. Verify that the application health check passes.

Example:

```bash
nomad job history nomad-canary-demo
```

Then:

```bash
nomad job revert nomad-canary-demo <stable-version>
```

Finally:

```bash
nomad job status nomad-canary-demo
```

Confirm that the deployment is successful and the expected allocation is healthy.

## 17. Troubleshooting

| Problem | Possible cause | Suggested action |
|---|---|---|
| Docker driver unavailable | Docker daemon not running | Start Docker Desktop and verify `docker version` |
| Nomad node unavailable | Nomad agent stopped | Restart the local Nomad development agent |
| Consul health check failing | Consul agent stopped or application unhealthy | Check Consul membership and application health |
| Docker image pull failure | Incorrect image reference or package access | Verify GHCR image name and package visibility |
| GitHub Actions job fails at startup | Repository action policy blocks an action | Review repository Actions permissions and allowlist |
| Self-hosted runner offline | Runner process stopped | Start `./run.sh` in the runner directory |
| Deployment fails | Canary does not meet health requirements | Inspect Nomad deployment and allocation status |
| Bridge networking unavailable | CNI bridge plugin missing | Use the configured host networking approach for this lab |

## 18. Engineering Review Checklist

Engineers reviewing Nomad job configurations should consider the following:

- [ ] Is the Nomad job configuration valid?
- [ ] Is the deployment strategy appropriate for the application?
- [ ] Is `canary` configured appropriately?
- [ ] Is `max_parallel` set to a safe value?
- [ ] Is automatic promotion configured intentionally?
- [ ] Is automatic rollback enabled where required?
- [ ] Are health checks configured correctly?
- [ ] Are health-check intervals and timeouts appropriate?
- [ ] Is `min_healthy_time` sufficient?
- [ ] Are `healthy_deadline` and `progress_deadline` realistic?
- [ ] Are resource allocations appropriate?
- [ ] Are container images versioned and traceable?
- [ ] Does the CI/CD pipeline wait for deployment completion?
- [ ] Does the pipeline fail when deployment verification fails?
- [ ] Is a manual rollback procedure documented?
- [ ] Are secrets and deployment credentials managed securely?
- [ ] Are production deployment settings reviewed separately from development settings?

## 19. Limitations and Future Improvements

This is a local proof-of-concept implementation. The following improvements would be appropriate before production adoption:

- Run Nomad and Consul in a properly configured production cluster.
- Configure Nomad and Consul high availability.
- Replace development mode with production agent configurations.
- Configure secure service communication and access control.
- Introduce a hardened and appropriately isolated CI/CD runner.
- Pin third-party GitHub Actions to verified commit SHAs.
- Introduce a controlled container image vulnerability-scanning stage.
- Add persistent monitoring and alerting.
- Improve deployment observability and reporting.
- Test rollback behaviour under additional failure scenarios.
- Introduce a production-ready networking and service-discovery configuration.

## 20. Conclusion

This project demonstrates an automated canary deployment and rollback workflow using GitHub Actions, Docker, Nomad, and Consul.

The implementation successfully demonstrated application building and testing, image publishing, automated deployment, health-based canary promotion, automatic rollback, and manual rollback.

The final CI/CD workflow successfully deployed application version 7 to the local Nomad environment, with one healthy allocation and no unhealthy allocations.

The project provides a practical foundation for reviewing and implementing safer deployment strategies in Nomad-based environments.

## 21. Repository

GitHub Repository:

https://github.com/amt-kwame-agyabeng/nomad-canary-demo

GitHub Actions:

https://github.com/amt-kwame-agyabeng/nomad-canary-demo/actions


