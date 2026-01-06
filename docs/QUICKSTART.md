# Quick Start Guide

This guide will help you deploy the Wiz technical exercise from scratch.

## Prerequisites

### Local Environment
- [ ] Git installed
- [ ] gcloud CLI installed and authenticated
- [ ] kubectl installed (v1.27+)
- [ ] Terraform installed (v1.5+)
- [ ] Helm installed (v3.12+)
- [ ] Docker installed

### GCP Setup
- [ ] GCP Project: `clgcporg10-158`
- [ ] Organization: `clgcporg10-158`
- [ ] Billing enabled
- [ ] APIs enabled (will be done by Terraform)

### GitHub Setup
- [ ] Repository created: `https://github.com/jotea3030/wiz`
- [ ] Secrets configured (see below)

---

## Step 1: Initial GCP Configuration

### 1.1 Authenticate with GCP
```bash
# Login to GCP
gcloud auth login

# Set project
gcloud config set project clgcporg10-158 

# Set default region
gcloud config set compute/region us-central1

# Set default zone
gcloud config set compute/zone us-central1-a

# Application default credentials for Terraform
gcloud auth application-default login
```

### 1.2 Create Service Account for GitHub Actions
```bash
# Create service account
gcloud iam service-accounts create github-actions \
  --display-name="GitHub Actions Service Account"

# Grant necessary roles
gcloud projects add-iam-policy-binding clgcporg10-158 \
  --member="serviceAccount:github-actions@clgcporg10-158.iam.gserviceaccount.com" \
  --role="roles/editor"

gcloud projects add-iam-policy-binding clgcporg10-158 \
  --member="serviceAccount:github-actions@clgcporg10-158.iam.gserviceaccount.com" \
  --role="roles/container.admin"

gcloud projects add-iam-policy-binding clgcporg10-158 \
  --member="serviceAccount:github-actions@clgcporg10-158.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser"

# Create and download key
gcloud iam service-accounts keys create ~/github-actions-key.json \
  --iam-account=github-actions@clgcporg10-158.iam.gserviceaccount.com

# Display key (copy this for GitHub secret)
cat ~/github-actions-key.json
```

### 1.3 Create Terraform State Bucket
```bash
# Create bucket for Terraform state
gsutil mb -p clgcporg10-158 -l us-central1 gs://wiz-terraform-state

# Enable versioning
gsutil versioning set on gs://wiz-terraform-state

# Set lifecycle policy
cat > /tmp/lifecycle.json <<EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {"numNewerVersions": 5}
      }
    ]
  }
}
EOF

gsutil lifecycle set /tmp/lifecycle.json gs://wiz-terraform-state
```

---

## Step 2: GitHub Repository Setup

### 2.1 Clone Repository
```bash
git clone https://github.com/jotea3030/wiz.git
cd wiz
```

### 2.2 Configure GitHub Secrets

Go to: `https://github.com/jotea3030/wiz/settings/secrets/actions`

Add the following secrets:

| Secret Name | Value | How to Get |
|------------|-------|------------|
| `GCP_PROJECT_ID` | `clgcporg10-158` | Your project ID |
| `GCP_SA_KEY` | Contents of `github-actions-key.json` | From step 1.2 |
| `MONGODB_PASSWORD` | Generate strong password | `openssl rand -base64 32` |
| `JWT_SECRET` | Generate random string | `openssl rand -base64 64` |
| `WIZ_CLIENT_ID` | From Wiz console | Settings → Service Accounts |
| `WIZ_CLIENT_SECRET` | From Wiz console | Settings → Service Accounts |

```bash
# Generate MongoDB password
openssl rand -base64 32

# Generate JWT secret
openssl rand -base64 64
```

---

## Step 3: Local Deployment (Manual)

If you want to deploy locally before using CI/CD:

### 3.1 Deploy Infrastructure with Terraform
```bash
cd terraform

# Initialize Terraform
terraform init \
  -backend-config="bucket=wiz-terraform-state" \
  -backend-config="prefix=terraform/state"

# Review the plan
terraform plan \
  -var="project_id=clgcporg10-158" \
  -var="mongodb_password=YOUR_MONGODB_PASSWORD" \
  -out=tfplan

# Apply the configuration
terraform apply tfplan

# Save outputs
terraform output -json > ../terraform-outputs.json

# Get important values
terraform output -raw mongodb_vm_internal_ip
terraform output -raw gke_cluster_name
terraform output -raw docker_repository
```

### 3.2 Configure kubectl
```bash
# Get GKE credentials
gcloud container clusters get-credentials wiz-exercise-gke-cluster \
  --region us-central1 \
  --project clgcporg10-158

# Verify connection
kubectl cluster-info
kubectl get nodes
```

### 3.3 Install NGINX Ingress Controller
```bash
# Add Helm repo
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install NGINX Ingress
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.metrics.enabled=true \
  --wait

# Wait for external IP
kubectl get svc -n ingress-nginx -w
```

### 3.4 Build and Push Docker Image
```bash
cd ../docker

# Get repo URL from Terraform output
DOCKER_REPO=$(cd ../terraform && terraform output -raw docker_repository)

# Configure Docker for GCP
gcloud auth configure-docker us-central1-docker.pkg.dev

# Build image
docker build -t ${DOCKER_REPO}/todo-app:latest -f Dockerfile ../app

# Verify wizexercise.txt
docker run --rm ${DOCKER_REPO}/todo-app:latest cat /app/wizexercise.txt

# Push image
docker push ${DOCKER_REPO}/todo-app:latest
```

### 3.5 Deploy Application with Helm
```bash
cd ../helm

# Get MongoDB internal IP
MONGODB_IP=$(cd ../terraform && terraform output -raw mongodb_vm_internal_ip)

# Deploy with Helm
helm upgrade --install todo-app ./todo-app \
  --namespace default \
  --create-namespace \
  --set image.repository=${DOCKER_REPO}/todo-app \
  --set image.tag=latest \
  --set mongodb.host=${MONGODB_IP} \
  --set mongodb.password=YOUR_MONGODB_PASSWORD \
  --set jwt.secret=YOUR_JWT_SECRET \
  --wait \
  --timeout 10m

# Check deployment
kubectl get pods
kubectl get svc
kubectl get ingress

# Verify wizexercise.txt
POD_NAME=$(kubectl get pods -l app=todo-app -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD_NAME -- cat /app/wizexercise.txt
```

### 3.6 Get Application URL
```bash
# Get Ingress IP (may take a few minutes)
INGRESS_IP=$(kubectl get ingress todo-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "Application URL: http://${INGRESS_IP}"

# Test application
curl -I http://${INGRESS_IP}
```

---

## Step 4: CI/CD Deployment (Automated)

### 4.1 Push to GitHub
```bash
# Add all files
git add .

# Commit
git commit -m "Initial Wiz exercise setup"

# Push to main branch
git push origin main
```

### 4.2 Monitor Deployment
1. Go to: `https://github.com/jotea3030/wiz/actions`
2. Watch the "Deploy Infrastructure" workflow
3. Once complete, watch the "Build and Deploy Application" workflow
4. Check workflow logs for any errors

### 4.3 Manual Workflow Trigger (if needed)
```bash
# Trigger infrastructure deployment
gh workflow run infra-deploy.yml --ref main

# Trigger application deployment
gh workflow run app-deploy.yml --ref main
```

---

## Step 5: Verification

### 5.1 Verify Infrastructure
```bash
# List compute instances
gcloud compute instances list

# List GKE clusters
gcloud container clusters list

# List storage buckets
gsutil ls

# Check MongoDB VM
gcloud compute ssh wiz-exercise-mongodb-vm --zone us-central1-a
```

### 5.2 Verify Kubernetes
```bash
# Get cluster credentials
gcloud container clusters get-credentials wiz-exercise-gke-cluster \
  --region us-central1

# Check nodes
kubectl get nodes -o wide

# Check pods
kubectl get pods -A

# Check todo-app
kubectl get pods -l app=todo-app
kubectl logs -l app=todo-app --tail=50

# Verify wizexercise.txt
POD_NAME=$(kubectl get pods -l app=todo-app -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD_NAME -- cat /app/wizexercise.txt
```

### 5.3 Verify Application
```bash
# Get application URL
INGRESS_IP=$(kubectl get ingress todo-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Application URL: http://${INGRESS_IP}"

# Open in browser
open "http://${INGRESS_IP}"

# Or test with curl
curl http://${INGRESS_IP}
```

### 5.4 Verify Database
```bash
# SSH to MongoDB VM
gcloud compute ssh wiz-exercise-mongodb-vm --zone us-central1-a

# Connect to MongoDB
mongo -u admin -p YOUR_MONGODB_PASSWORD

# Check databases
show dbs

# Check collections
use go-mongodb
show collections

# Check data
db.users.find().pretty()
db.todos.find().pretty()

# Exit
exit
exit
```

### 5.5 Verify Backups
```bash
# List backups
gsutil ls gs://wiz-mongodb-backups-*/

# Verify public access (should work without auth)
BACKUP_FILE=$(gsutil ls gs://wiz-mongodb-backups-*/ | head -1)
curl -I $BACKUP_FILE
```

### 5.6 Verify Security Misconfigurations
```bash
# Check SSH firewall rule (should be 0.0.0.0/0)
gcloud compute firewall-rules describe wiz-exercise-allow-ssh-public

# Check GCS bucket IAM (should have allUsers)
gsutil iam get gs://wiz-mongodb-backups-*/

# Check VM IAM role (should have compute.admin)
gcloud projects get-iam-policy clgcporg10-158 \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:wiz-exercise-mongodb-vm@*"

# Check Kubernetes RBAC (should have cluster-admin)
kubectl get clusterrolebinding todo-app-admin -o yaml
```

---

## Step 6: Demonstration Preparation

### 6.1 Create Test Data
```bash
# Get application URL
INGRESS_IP=$(kubectl get ingress todo-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Sign up for an account (do this in browser)
open "http://${INGRESS_IP}"

# Or use API
curl -X POST http://${INGRESS_IP}/signup \
  -H "Content-Type: application/json" \
  -d '{"username":"demo","email":"demo@example.com","password":"Demo123!"}'

# Login
curl -X POST http://${INGRESS_IP}/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"Demo123!"}'

# Create some todos
curl -X POST http://${INGRESS_IP}/todo \
  -H "Content-Type: application/json" \
  -b cookies.txt \
  -d '{"name":"Prepare presentation","status":"pending"}'
```

### 6.2 Take Screenshots
Take screenshots of:
- [ ] GCP Console - Compute instances
- [ ] GCP Console - GKE cluster
- [ ] GCP Console - Storage buckets
- [ ] Application running in browser
- [ ] kubectl get pods output
- [ ] Wiz console findings
- [ ] GitHub Actions workflows

### 6.3 Prepare Commands Cheat Sheet
Create a file with commonly used commands:
```bash
# kubectl commands
kubectl get pods
kubectl get svc
kubectl get ingress
kubectl exec POD_NAME -- cat /app/wizexercise.txt

# MongoDB commands
gcloud compute ssh wiz-exercise-mongodb-vm --zone us-central1-a
mongo -u admin -p PASSWORD
use go-mongodb
db.todos.find()

# Backup commands
gsutil ls gs://wiz-mongodb-backups-*/
```

---

## Step 7: Wiz Platform Setup

### 7.1 Connect GCP Project to Wiz
1. Log into Wiz console
2. Go to Settings → Cloud Accounts
3. Click "Add Cloud Account"
4. Select "Google Cloud Platform"
5. Follow the wizard to connect `clgcporg10-158`

### 7.2 Run Initial Scan
1. Wait for initial scan to complete (15-30 minutes)
2. Review findings in dashboard
3. Filter for "Critical" and "High" severity
4. Review specific findings:
   - Public SSH access
   - Public storage bucket
   - Overly permissive IAM
   - Outdated software
   - Kubernetes RBAC issues

### 7.3 Prepare Wiz Demo
- [ ] Familiarize yourself with Wiz UI
- [ ] Know where to find each security finding
- [ ] Practice navigating the security graph
- [ ] Understand remediation recommendations

---

## Troubleshooting

### Issue: Terraform fails to create resources
**Solution**: Check quotas and enable APIs
```bash
gcloud services list --enabled
gcloud services enable compute.googleapis.com container.googleapis.com
```

### Issue: GKE nodes not ready
**Solution**: Check node pool and events
```bash
kubectl get nodes
kubectl describe node NODE_NAME
gcloud container operations list
```

### Issue: Ingress has no IP address
**Solution**: Check ingress controller and load balancer
```bash
kubectl get svc -n ingress-nginx
kubectl describe ingress todo-app
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
```

### Issue: Application can't connect to MongoDB
**Solution**: Check network connectivity and credentials
```bash
# From a test pod
kubectl run -it --rm debug --image=busybox --restart=Never -- sh
nc -zv MONGODB_IP 27017

# Check MongoDB logs
gcloud compute ssh wiz-exercise-mongodb-vm --zone us-central1-a
tail -f /var/log/mongodb/mongod.log
```

### Issue: Docker push fails
**Solution**: Authenticate to Artifact Registry
```bash
gcloud auth configure-docker us-central1-docker.pkg.dev
gcloud auth print-access-token | docker login -u oauth2accesstoken --password-stdin https://us-central1-docker.pkg.dev
```

---

## Cleanup

To avoid charges after the exercise:

### Option 1: Terraform Destroy
```bash
cd terraform
terraform destroy \
  -var="project_id="clgcporg10-158 \
  -var="mongodb_password=YOUR_PASSWORD"
```

### Option 2: Manual Cleanup
```bash
# Delete GKE cluster
gcloud container clusters delete wiz-exercise-gke-cluster \
  --region us-central1 \
  --quiet

# Delete Compute instances
gcloud compute instances delete wiz-exercise-mongodb-vm \
  --zone us-central1-a \
  --quiet

# Delete storage buckets
gsutil -m rm -r gs://wiz-mongodb-backups-*/

# Delete VPC
gcloud compute networks delete wiz-exercise-vpc --quiet
```

---

## Cost Monitoring

### Check Current Costs
```bash
# View billing reports in GCP Console
open "https://console.cloud.google.com/billing"

# Set up budget alerts (recommended)
gcloud billing budgets create \
  --billing-account BILLING_ACCOUNT_ID \
  --display-name "Wiz Exercise Budget" \
  --budget-amount 200 \
  --threshold-rule percent=50 \
  --threshold-rule percent=90 \
  --threshold-rule percent=100
```

### Estimated Costs (2 weeks)
- GKE Cluster (1 e2-small node): ~$25
- MongoDB VM (e2-micro): ~$7
- Load Balancer: ~$18
- Storage (minimal): ~$1
- **Total**: ~$25-30 for 2 weeks

---

## Support

If you encounter issues:
1. Check the documentation in `/docs`
2. Review GitHub Actions logs
3. Check GCP Logs Explorer
4. Contact your Wiz hiring manager

---

## Pre-Presentation Checklist

- [ ] Infrastructure deployed successfully
- [ ] Application accessible via browser
- [ ] Can create and view todos
- [ ] wizexercise.txt verified in container
- [ ] Can SSH to MongoDB VM
- [ ] Can query MongoDB database
- [ ] Backups exist in GCS
- [ ] GCS bucket is publicly accessible
- [ ] kubectl commands work
- [ ] Wiz platform shows findings
- [ ] All screenshots taken
- [ ] Presentation slides prepared
- [ ] Demo script practiced

Good luck with your presentation!
