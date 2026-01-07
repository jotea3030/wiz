# Wiz Technical Exercise - Multi-Environment Setup

Complete infrastructure and application deployment for Wiz cloud security demonstration with both vulnerable (preprod) and secure (prod) configurations.

## 🏗️ Architecture Overview

### Preprod Environment (Vulnerable)
- **Purpose**: Demonstrate security vulnerabilities for Wiz detection
- **SSH**: Exposed to 0.0.0.0/0 ⚠️
- **Storage**: Public GCS bucket ⚠️
- **IAM**: Overpermissive compute.admin role ⚠️
- **Software**: MongoDB 4.4 on Ubuntu 22.04 (outdated) ⚠️
- **Kubernetes**: cluster-admin role for pods ⚠️
- **Network**: Database in public subnet ⚠️

### Prod Environment (Secure)
- **Purpose**: Production-ready secure configuration
- **SSH**: Restricted to specific IP ranges ✅
- **Storage**: Private GCS bucket ✅
- **IAM**: Least privilege permissions ✅
- **Software**: MongoDB 7.0 on Ubuntu 24.04 (current) ✅
- **Kubernetes**: Limited RBAC permissions ✅
- **Network**: Database in private subnet ✅

## 📋 Prerequisites

### Required Tools
- **gcloud CLI** (>= 400.0.0)
- **Terraform** (>= 1.5.0)
- **kubectl** (>= 1.27.0)
- **Helm** (>= 3.12.0)
- **Docker** (>= 20.10.0)

### GCP Requirements
- Active GCP project
- Billing enabled
- Required APIs enabled (handled by Terraform)
- Service account with Editor role

### Installation

```bash
# Install gcloud
curl https://sdk.cloud.google.com | bash

# Install Terraform
brew install terraform  # macOS
# or download from https://www.terraform.io/downloads

# Install kubectl
gcloud components install kubectl

# Install Helm
brew install helm  # macOS
# or: curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install Docker
# Follow instructions at https://docs.docker.com/get-docker/
```

## 🚀 Quick Start

### Option 1: Automated Deployment (Recommended)

```bash
# Set environment variables
export GCP_PROJECT_ID="clgcporg10-158"
export MONGODB_PASSWORD=$(openssl rand -base64 32)
export JWT_SECRET=$(openssl rand -base64 64)

# Deploy preprod (vulnerable)
./deploy.sh --environment preprod --action apply

# Deploy prod (secure)
./deploy.sh --environment prod --action apply
```

### Option 2: Manual Deployment

#### Deploy Infrastructure

```bash
cd terraform

# Initialize Terraform
terraform init \
  -backend-config="bucket=wiz-terraform-state-${GCP_PROJECT_ID}" \
  -backend-config="prefix=terraform/preprod/state"

# Create workspace
terraform workspace new preprod

# Plan deployment
terraform plan -var-file="preprod.tfvars" -var="mongodb_password=${MONGODB_PASSWORD}"

# Apply
terraform apply -var-file="preprod.tfvars" -var="mongodb_password=${MONGODB_PASSWORD}" -auto-approve
```

#### Deploy Application

```bash
# Get GKE credentials
gcloud container clusters get-credentials wiz-preprod-gke-cluster \
  --region us-central1 \
  --project ${GCP_PROJECT_ID}

# Install NGINX Ingress
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --wait

# Build and push Docker image
DOCKER_REPO="us-central1-docker.pkg.dev/${GCP_PROJECT_ID}/wiz-preprod-docker-repo"
gcloud auth configure-docker us-central1-docker.pkg.dev
docker build -t ${DOCKER_REPO}/todo-app:latest -f docker/Dockerfile .
docker push ${DOCKER_REPO}/todo-app:latest

# Get MongoDB IP
MONGODB_IP=$(gcloud compute instances describe wiz-preprod-mongodb-vm \
  --zone us-central1-a \
  --format='get(networkInterfaces[0].networkIP)')

# Deploy with Helm
helm upgrade --install todo-app ./helm/todo-app \
  --values ./helm/todo-app/values-preprod.yaml \
  --set image.repository=${DOCKER_REPO}/todo-app \
  --set mongodb.host=${MONGODB_IP} \
  --set mongodb.password=${MONGODB_PASSWORD} \
  --set jwt.secret=${JWT_SECRET} \
  --wait
```

### Option 3: GitHub Actions (CI/CD)

Configure GitHub Secrets:

| Secret Name | Description |
|-------------|-------------|
| `GCP_SA_KEY` | Service account JSON key |
| `GCP_PROJECT_ID` | GCP project ID |
| `MONGODB_PASSWORD` | MongoDB password |
| `JWT_SECRET` | JWT secret for app |
| `WIZ_CLIENT_ID` | Wiz API client ID (optional) |
| `WIZ_CLIENT_SECRET` | Wiz API secret (optional) |

Then trigger workflows:

```bash
# Via GitHub UI: Actions → Select workflow → Run workflow → Choose environment

# Or via gh CLI
gh workflow run infra-deploy.yml -f environment=preprod -f action=apply
gh workflow run app-deploy.yml -f environment=preprod
```

## 📁 Project Structure

```
wiz-exercise/
├── terraform/                  # Infrastructure as Code
│   ├── main.tf                # Main configuration
│   ├── variables.tf           # Variable definitions
│   ├── network.tf             # VPC, subnets, firewall
│   ├── gke.tf                 # GKE cluster
│   ├── vm.tf                  # MongoDB VM
│   ├── storage.tf             # GCS buckets
│   ├── outputs.tf             # Output values
│   ├── preprod.tfvars         # Preprod config (vulnerable)
│   └── prod.tfvars            # Prod config (secure)
├── helm/todo-app/             # Kubernetes deployment
│   ├── Chart.yaml
│   ├── values.yaml            # Default values
│   ├── values-preprod.yaml    # Preprod overrides
│   ├── values-prod.yaml       # Prod overrides
│   └── templates/             # K8s manifests
├── docker/                    # Container configuration
│   ├── Dockerfile
│   └── wizexercise.txt        # Verification file
├── .github/workflows/         # CI/CD pipelines
│   ├── infra-deploy.yml       # Infrastructure pipeline
│   └── app-deploy.yml         # Application pipeline
├── scripts/                   # Utility scripts
│   └── backup.go              # MongoDB backup
├── docs/                      # Documentation
│   ├── QUICKSTART.md
│   ├── PRESENTATION.md
│   ├── SECURITY_FINDINGS.md
│   └── PROJECT_NOTES.md
├── deploy.sh                  # Deployment script
├── cleanup.sh                 # Cleanup script
└── README.md                  # This file
```

## 🔐 Security Configuration Comparison

| Feature | Preprod (Vulnerable) | Prod (Secure) |
|---------|---------------------|---------------|
| SSH Access | 0.0.0.0/0 ⚠️ | Specific IPs ✅ |
| GCS Bucket | Public ⚠️ | Private ✅ |
| VM IAM Role | compute.admin ⚠️ | Minimal ✅ |
| MongoDB Version | 4.4 (2020) ⚠️ | 7.0 (current) ✅ |
| Ubuntu Version | 22.04 ⚠️ | 24.04 ✅ |
| K8s RBAC | cluster-admin ⚠️ | Limited ✅ |
| Network | Public subnet ⚠️ | Private subnet ✅ |
| Pod replicas | 2 | 3 |
| Resources | Minimal | Production-grade |
| Security Context | None ⚠️ | Enabled ✅ |
| Network Policies | Disabled ⚠️ | Enabled ✅ |
| Auto-scaling | No | Yes ✅ |

## 🧪 Verification & Testing

### Check Infrastructure

```bash
# List all resources
gcloud compute instances list --filter="name~wiz-preprod"
gcloud container clusters list --filter="name~wiz-preprod"
gsutil ls | grep wiz-preprod

# Get application URL
kubectl get svc -n ingress-nginx ingress-nginx-controller

# Verify wizexercise.txt
POD=$(kubectl get pods -l app=todo-app -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD -- cat /app/wizexercise.txt
```

### Test Application

```bash
# Get ingress IP
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Test login page
curl http://${INGRESS_IP}/

# Create test user
curl -X POST http://${INGRESS_IP}/signup \
  -H "Content-Type: application/json" \
  -d '{"username":"demo","email":"demo@example.com","password":"Demo123!"}'
```

### Verify Security Vulnerabilities (Preprod)

```bash
# 1. Check SSH exposure
gcloud compute firewall-rules describe wiz-preprod-allow-ssh

# 2. Test public bucket access (should work without auth)
BUCKET=$(terraform output -raw backup_bucket_name)
curl -I https://storage.googleapis.com/${BUCKET}/

# 3. Check overpermissive IAM
gcloud projects get-iam-policy clgcporg10-158 \
  --filter="bindings.members:serviceAccount:wiz-preprod-mongodb-vm"

# 4. Check outdated software
gcloud compute ssh wiz-preprod-mongodb-vm --zone us-central1-a \
  --command="mongod --version && lsb_release -a"

# 5. Check K8s RBAC
kubectl get clusterrolebindings | grep todo-app

# 6. Check network placement
gcloud compute instances describe wiz-preprod-mongodb-vm \
  --format="get(networkInterfaces[0].accessConfigs[0].natIP)"
```

## 🗑️ Cleanup

### Single Environment

```bash
# Clean up preprod
./cleanup.sh --environment preprod

# Clean up prod
./cleanup.sh --environment prod
```

### Both Environments

```bash
# Clean up everything
./cleanup.sh --environment all --force
```

### Manual Cleanup

```bash
# Delete Helm releases
helm uninstall todo-app -n default
helm uninstall ingress-nginx -n ingress-nginx

# Destroy infrastructure
cd terraform
terraform workspace select preprod
terraform destroy -var-file="preprod.tfvars" -var="mongodb_password=dummy" -auto-approve

# Clean up remaining resources
gcloud compute instances list --filter="name~wiz-preprod" --format="value(name)" | \
  xargs -I {} gcloud compute instances delete {} --zone=us-central1-a --quiet
```

## 📊 Cost Estimation

### Preprod (Cost-Optimized)
- GKE: 1x e2-small node (~$25/month)
- MongoDB VM: 1x e2-micro (~$7/month)
- Load Balancer: ~$18/month
- **Total: ~$50/month**

### Prod (Production-Grade)
- GKE: 3x e2-medium nodes (~$100/month)
- MongoDB VM: 1x e2-small (~$14/month)
- Load Balancer: ~$18/month
- **Total: ~$130/month**

## 🔧 Troubleshooting

### Common Issues

**1. Terraform state locked**
```bash
# Force unlock (use with caution)
terraform force-unlock <LOCK_ID>
```

**2. GKE credentials not working**
```bash
# Re-authenticate
gcloud container clusters get-credentials wiz-preprod-gke-cluster \
  --region us-central1
```

**3. MongoDB connection failed**
```bash
# Check MongoDB VM status
gcloud compute instances describe wiz-preprod-mongodb-vm \
  --zone us-central1-a

# Check firewall rules
gcloud compute firewall-rules list --filter="name~mongodb"

# SSH and check MongoDB
gcloud compute ssh wiz-preprod-mongodb-vm --zone us-central1-a
sudo systemctl status mongod
```

**4. Pods not starting**
```bash
# Check pod logs
kubectl logs -l app=todo-app --tail=100

# Check events
kubectl get events --sort-by='.lastTimestamp'

# Describe pod
kubectl describe pod -l app=todo-app
```

## 📚 Additional Resources

- [Terraform Documentation](https://www.terraform.io/docs)
- [GKE Best Practices](https://cloud.google.com/kubernetes-engine/docs/best-practices)
- [Helm Documentation](https://helm.sh/docs/)
- [MongoDB Security Checklist](https://docs.mongodb.com/manual/administration/security-checklist/)
- [Wiz Documentation](https://docs.wiz.io/)

## 🤝 Contributing

This is a technical exercise for demonstration purposes. For production use:
1. Review and adjust security configurations
2. Implement proper secret management (e.g., Secret Manager)
3. Enable monitoring and alerting
4. Configure backup and disaster recovery
5. Implement proper network segmentation

## 📝 License

This project is for educational and demonstration purposes.

## 📧 Support

For issues or questions:
1. Check the troubleshooting section
2. Review logs and error messages
3. Consult GCP and Terraform documentation
4. Contact your Wiz representative

---

**⚠️ Important Notes:**
- Preprod environment contains intentional security vulnerabilities
- Never use preprod configuration in production
- Always review costs before deploying
- Clean up resources when done to avoid charges
