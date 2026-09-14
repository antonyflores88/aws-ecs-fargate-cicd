# AWS ECS Fargate CI/CD Pipeline

Production-grade containerized deployment on AWS ECS Fargate with automated GitHub Actions CI/CD, OIDC authentication, Application Load Balancer, multi-AZ high availability, and Terraform Infrastructure as Code.

---

## Architecture

```
                         ┌──────────────────────────────────────┐
                         │         GitHub Actions CI/CD         │
                         │                                      │
                         │  Push → Test → Build → Push to ECR   │
                         │              → Deploy to ECS         │
                         │                                      │
                         │  Auth: AWS OIDC (zero stored secrets)│
                         └──────────────┬───────────────────────┘
                                        │
                                        ▼
┌───────────────────────────────────────────────────────────────────────┐
│                            AWS Cloud                                  │
│                                                                       │
│   ┌─────────────┐                                                     │
│   │   Amazon     │◄──── GitHub Actions pushes immutable images        │
│   │   ECR        │      tagged with git commit SHA                    │
│   └──────┬──────┘                                                     │
│          │                                                            │
│          │  (ECS pulls image)                                         │
│          ▼                                                            │
│   ┌─────────────────────────────────────────────────────────────┐     │
│   │                    VPC (10.100.0.0/16)                       │     │
│   │                                                              │     │
│   │   [Internet Gateway]                                         │     │
│   │         │                                                    │     │
│   │         ▼                                                    │     │
│   │   [Application Load Balancer] ── Port 80                     │     │
│   │         │                                                    │     │
│   │    ┌────┴────┐                                               │     │
│   │    ▼         ▼                                               │     │
│   │  ┌─────────────────┐  ┌─────────────────┐                   │     │
│   │  │ Public Subnet 1 │  │ Public Subnet 2 │                   │     │
│   │  │   (us-east-1a)  │  │   (us-east-1b)  │                   │     │
│   │  │                 │  │                  │                   │     │
│   │  │  ┌───────────┐  │  │  ┌───────────┐  │                   │     │
│   │  │  │  Fargate   │  │  │  │  Fargate   │  │                   │     │
│   │  │  │  Task      │  │  │  │  Task      │  │                   │     │
│   │  │  │ Port 8000  │  │  │  │ Port 8000  │  │                   │     │
│   │  │  └───────────┘  │  │  └───────────┘  │                   │     │
│   │  └─────────────────┘  └─────────────────┘                   │     │
│   │                                                              │     │
│   │         Logs ──────► [CloudWatch Log Group /ecs/ccm]         │     │
│   └──────────────────────────────────────────────────────────────┘     │
└───────────────────────────────────────────────────────────────────────┘
```

---

## Key Engineering Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Container Orchestration** | ECS Fargate (serverless) | No EC2 instances to patch or manage. AWS handles compute, scaling, and task health. |
| **CI/CD Authentication** | AWS OIDC (OpenID Connect) | Zero long-lived secrets stored in GitHub. Temporary credentials are issued per workflow run and expire automatically. |
| **Networking** | Public subnets + strict Security Groups | Fargate tasks run in public subnets with `assign_public_ip = true` for ECR/CloudWatch connectivity. Security Groups restrict all inbound traffic to ALB-only. See [Architecture Decisions](#architecture-decisions) below. |
| **Deployment Strategy** | Rolling update (min 100%, max 200%) | During deployment, new tasks start alongside old ones. Traffic shifts only after health checks pass. Zero downtime. |
| **Image Tagging** | Git commit SHA + `latest` | Every deployed image is traceable to an exact commit. Enables instant rollback to any previous version. |
| **Container Security** | Non-root user in Dockerfile | Application runs as `appuser`, not root. Limits blast radius if the container is compromised. |
| **Observability** | CloudWatch Logs + Container Insights | Centralized logging with 7-day retention. Per-task CPU/memory metrics via Container Insights. |
| **IaC** | Terraform with pinned provider versions | `.terraform.lock.hcl` committed for reproducible builds. State files excluded via `.gitignore`. |

---

## Architecture Decisions

### Why Public Subnets for Fargate Tasks?

Fargate tasks require outbound internet access to pull container images from ECR and send logs to CloudWatch. There are three common patterns:

| Pattern | How It Works | Extra Cost |
|---------|-------------|------------|
| **Public Subnets** (this project) | Tasks get a public IP for outbound access. SG blocks all direct inbound. | $0 |
| **Private Subnets + NAT Gateway** | Tasks in private subnets, NAT provides outbound. | ~$32/AZ/month |
| **Private Subnets + VPC Endpoints** | PrivateLink endpoints for ECR, S3, CloudWatch. | ~$7/endpoint/AZ/month |

This project uses **public subnets with ALB-only ingress Security Groups**, providing equivalent network isolation at zero additional cost. In an enterprise environment with compliance requirements (PCI-DSS, HIPAA), private subnets with NAT Gateways or VPC Endpoints would be the appropriate choice for defense-in-depth.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **Application** | Python 3.11, FastAPI, Uvicorn |
| **Container** | Docker (non-root, multi-stage ready) |
| **Orchestration** | AWS ECS Fargate |
| **Registry** | Amazon ECR (scan-on-push enabled) |
| **Load Balancing** | Application Load Balancer (multi-AZ) |
| **Networking** | Custom VPC, 2 public subnets, IGW |
| **IAM** | Least-privilege roles (ECS Execution, Task, OIDC) |
| **CI/CD** | GitHub Actions with AWS OIDC |
| **IaC** | Terraform (>= 1.5.0) |
| **Observability** | CloudWatch Logs, Container Insights |

---

## Project Structure

```
.
├── .github/
│   └── workflows/
│       └── ci-cd.yml          # GitHub Actions pipeline
├── ccm-infra/
│   ├── main.tf                # Core infrastructure (VPC, ECS, ALB, IAM, OIDC)
│   ├── variables.tf           # Input variables
│   ├── output.tf              # Infrastructure outputs
│   ├── providers.tf           # AWS provider configuration
│   └── .terraform.lock.hcl    # Provider version lock
├── tests/
│   └── test_main.py           # FastAPI endpoint tests
├── main.py                    # FastAPI application
├── Dockerfile                 # Container image (non-root)
├── requirements.txt           # Python dependencies
└── .gitignore                 # Excludes state files, secrets, caches
```

---

## CI/CD Pipeline

The pipeline is triggered on every push to `main` and on pull requests:

```
┌─────────────┐     ┌──────────────────┐     ┌──────────────────┐
│   Test &     │────►│  Build & Push    │────►│   Deploy to      │
│   Lint       │     │  to ECR          │     │   ECS Fargate    │
│              │     │                  │     │                  │
│ • pytest     │     │ • OIDC Auth      │     │ • Update task    │
│ • tf fmt     │     │ • Docker build   │     │   definition     │
│              │     │ • Tag with SHA   │     │ • Rolling deploy │
│ (all pushes) │     │ (main only)      │     │ • Wait for       │
│              │     │                  │     │   stability      │
└─────────────┘     └──────────────────┘     └──────────────────┘
```

- **Pull Requests**: Only test & lint runs (quality gate before merge)
- **Push to main**: Full pipeline — test, build, push to ECR, deploy to ECS
- **Authentication**: AWS OIDC — no stored AWS credentials

---

## Deployment

### Prerequisites
- AWS CLI configured with appropriate permissions
- Terraform >= 1.5.0
- Docker

### 1. Deploy Infrastructure
```bash
cd ccm-infra
terraform init
terraform plan
terraform apply
```

### 2. Configure GitHub Actions
After `terraform apply`, retrieve the OIDC role ARN:
```bash
terraform output github_actions_role_arn
```
Add it as a GitHub repository secret:
- Go to **Settings → Secrets and variables → Actions**
- Create secret: `AWS_ROLE_ARN` with the role ARN value

### 3. Push and Deploy
```bash
git push origin main
```
The pipeline handles everything: test → build → push → deploy.

### Tear Down
```bash
cd ccm-infra
terraform destroy
```

---

## Local Development

```bash
# Run the application locally
docker build -t ccm-app .
docker run -p 8000:8000 ccm-app

# Access the app
curl http://localhost:8000        # Home page
curl http://localhost:8000/health  # Health check
```

