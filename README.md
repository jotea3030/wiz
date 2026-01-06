# Wiz Technical Exercise - Todo Application Deployment

## Overview

This repository contains a complete solution for deploying a secure two-tier web application on Google Cloud Platform (GCP) with intentional security misconfigurations for demonstration purposes.

## Architecture

```
Internet → Load Balancer → GKE Cluster (Private) → MongoDB VM (Public Subnet)
                                                   ↓
                                            GCS Bucket (Public Read)
```

### Components:
- **Frontend**: Golang Todo application in Docker container
- **Kubernetes**: GKE cluster in private subnet
- **Database**: MongoDB 4.4 (outdated) on Ubuntu 20.04 VM
- **Backup**: Automated daily backups to GCS bucket (public read)
- **Load Balancer**: NGINX Ingress Controller
- **IaC**: Terraform for infrastructure, Helm for K8s resources
- **CI/CD**: GitHub Actions for automated deployment
- **Security**: Wiz for cloud security posture management

## Project Structure

```
wiz-exercise/
├── terraform/              # Infrastructure as Code
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── network.tf
│   ├── gke.tf
│   ├── vm.tf
│   ├── storage.tf
│   └── iam.tf
├── helm/                   # Kubernetes deployments
│   └── todo-app/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── ingress.yaml
│           ├── serviceaccount.yaml
│           └── clusterrolebinding.yaml
├── docker/                 # Application containerization
│   ├── Dockerfile
│   └── wizexercise.txt
├── scripts/                # Automation scripts
│   ├── backup.go
│   └── setup-mongodb.sh
├── .github/workflows/      # CI/CD pipelines
│   ├── infra-deploy.yml
│   └── app-deploy.yml
└── docs/                   # Documentation
    ├── PRESENTATION.md
    └── SECURITY_FINDINGS.md
```

## Prerequisites

- GCP Project: `clgcporg10-158`
- GitHub Repository: https://github.com/jotea3030/wiz
- Terraform >= 1.14.3
- kubectl >= 1.33
- Helm >= 4.04
- Docker >= 29.1.3
- gcloud SDK >= 550.0.0 
- gsutil >= 5.35

## Intentional Security Misconfigurations

### 1. VM Security Issues
- SSH exposed to 0.0.0.0/0 (public internet)
- Overly permissive IAM role (compute.admin)
- Outdated OS (Ubuntu 22.04 LTS)
- Outdated MongoDB (4.4.20 - released 2020)

### 2. Storage Security Issues
- GCS bucket allows public read access
- Database backups publicly accessible
- No encryption at rest configuration

### 3. Kubernetes Security Issues
- Container assigned cluster-admin role
- Excessive RBAC permissions
- No network policies

### 4. Network Security Issues
- MongoDB VM in public subnet
- Broad security group rules

## Cost Management

This deployment is designed to stay well under the $200 budget:

- **GKE Cluster**: 1 e2-small node (~$25/month prorated)
- **VM**: e2-micro for MongoDB (~$7/month prorated)
- **Storage**: Minimal GCS usage (~$1/month)
- **Load Balancer**: Regional LB (~$18/month prorated)
- **Estimated 2-week cost**: ~$25-30

## Setup Instructions

### 1. Clone the Repository

```bash
git clone https://github.com/jotea3030/wiz.git
cd wiz
```

### 2. Configure GCP Authentication

```bash
gcloud auth login
gcloud config set project clgcporg10-158 
gcloud auth application-default login
```

### 3. Set Up GitHub Secrets

Add these secrets to your GitHub repository:
- `GCP_PROJECT_ID`: clgcporg10-158
- `GCP_SA_KEY`: Service account JSON key
- `MONGODB_PASSWORD`: Database password
- `JWT_SECRET`: JWT secret for application

### 4. Deploy Infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### 5. Configure kubectl

```bash
gcloud container clusters get-credentials wiz-gke-cluster \
  --region us-central1 \
  --project clgcporg10-158 
```

### 6. Deploy Application with Helm

```bash
cd helm
helm install todo-app ./todo-app \
  --set mongodb.host=<MONGODB_VM_IP> \
  --set mongodb.password=<MONGODB_PASSWORD> \
  --set jwtSecret=<JWT_SECRET>
```

### 7. Verify Deployment

```bash
# Check pods
kubectl get pods

# Check ingress
kubectl get ingress

# Test application
curl http://<LOAD_BALANCER_IP>
```

## CI/CD Pipeline

### Infrastructure Pipeline
Triggers on changes to `terraform/**`
- Validates Terraform code
- Runs security scans with Wiz
- Plans infrastructure changes
- Applies on merge to main

### Application Pipeline
Triggers on changes to application code
- Builds Docker image
- Scans image for vulnerabilities with Wiz
- Pushes to Google Container Registry
- Deploys to GKE via Helm

## Verification Steps

### 1. Verify wizexercise.txt in Container

```bash
# Get pod name
POD_NAME=$(kubectl get pods -l app=todo-app -o jsonpath='{.items[0].metadata.name}')

# Check file exists
kubectl exec $POD_NAME -- cat /app/wizexercise.txt
```

### 2. Verify Database Connection

```bash
# Create a test todo
curl -X POST http://<LOAD_BALANCER_IP>/todo \
  -H "Content-Type: application/json" \
  -d '{"name": "Test Todo", "status": "pending"}'

# Verify in MongoDB
ssh <VM_IP>
mongo -u admin -p
use go-mongodb
db.todos.find()
```

### 3. Verify Backup Script

```bash
# SSH to VM
ssh <VM_IP>

# Check cron job
crontab -l

# Manually run backup
/usr/local/bin/backup-mongodb.sh

# Verify in GCS
gsutil ls gs://wiz-mongodb-backups/
```

### 4. Verify Public Access to Backups

```bash
# Test public read without authentication
curl https://storage.googleapis.com/wiz-mongodb-backups/<backup-file>
```

## Security Tool Demonstration (Wiz)

The Wiz platform will detect:

1. **Critical Vulnerabilities**
   - Outdated MongoDB version (CVEs)
   - Outdated Ubuntu version (CVEs)
   - Container vulnerabilities

2. **Misconfigurations**
   - Public SSH access
   - Overly permissive IAM roles
   - Public storage bucket
   - Excessive Kubernetes RBAC

3. **Network Exposure**
   - Internet-facing database VM
   - Open security groups

4. **Compliance Issues**
   - CIS Benchmark failures
   - PCI-DSS violations

## Cleanup

```bash
# Delete Helm release
helm uninstall todo-app

# Destroy infrastructure
cd terraform
terraform destroy

# Clean up GCS bucket
gsutil -m rm -r gs://wiz-mongodb-backups
```

## Presentation Checklist

- [ ] Architecture diagram explanation
- [ ] Live demo of application functionality
- [ ] Demonstrate kubectl commands
- [ ] Show wizexercise.txt in container
- [ ] Demonstrate database connection
- [ ] Show backup automation
- [ ] Demonstrate public bucket access
- [ ] Walk through Terraform code
- [ ] Explain CI/CD pipelines
- [ ] Demonstrate Wiz findings
- [ ] Discuss security implications
- [ ] Show remediation recommendations

## Support

For questions during the exercise, contact your Wiz hiring manager.

## License

MIT License - This is an educational exercise
