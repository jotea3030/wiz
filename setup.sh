#!/bin/bash
set -e

# Wiz Technical Exercise - Automated Setup Script
# This script automates the deployment of the entire environment

echo "=========================================="
echo "Wiz Technical Exercise - Setup Script"
echo "=========================================="
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ID="${GCP_PROJECT_ID:-clgcporg10-158}"
REGION="${GCP_REGION:-us-central1}"
ZONE="${GCP_ZONE:-us-central1-a}"
CLUSTER_NAME="wiz-exercise-gke-cluster"

# Check prerequisites
echo "Checking prerequisites..."

command -v gcloud >/dev/null 2>&1 || { echo -e "${RED}Error: gcloud CLI is not installed${NC}"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}Error: kubectl is not installed${NC}"; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo -e "${RED}Error: terraform is not installed${NC}"; exit 1; }
command -v helm >/dev/null 2>&1 || { echo -e "${RED}Error: helm is not installed${NC}"; exit 1; }
command -v docker >/dev/null 2>&1 || { echo -e "${RED}Error: docker is not installed${NC}"; exit 1; }

echo -e "${GREEN}✓ All prerequisites installed${NC}"
echo ""

# Check for required environment variables
if [ -z "$MONGODB_PASSWORD" ]; then
    echo -e "${YELLOW}Warning: MONGODB_PASSWORD not set. Generating random password...${NC}"
    export MONGODB_PASSWORD=$(openssl rand -base64 32)
    echo "MongoDB Password: $MONGODB_PASSWORD"
    echo "Save this password!"
    echo ""
fi

if [ -z "$JWT_SECRET" ]; then
    echo -e "${YELLOW}Warning: JWT_SECRET not set. Generating random secret...${NC}"
    export JWT_SECRET=$(openssl rand -base64 64)
    echo "JWT Secret: $JWT_SECRET"
    echo "Save this secret!"
    echo ""
fi

# Authenticate with GCP
echo "Authenticating with GCP..."
gcloud config set project $PROJECT_ID
gcloud config set compute/region $REGION
gcloud config set compute/zone $ZONE
echo -e "${GREEN}✓ GCP configuration set${NC}"
echo ""

# Create Terraform state bucket
echo "Creating Terraform state bucket..."
TERRAFORM_STATE_BUCKET="wiz-terraform-state-${PROJECT_ID}"
if ! gsutil ls gs://${TERRAFORM_STATE_BUCKET} >/dev/null 2>&1; then
    gsutil mb -p $PROJECT_ID -l $REGION gs://${TERRAFORM_STATE_BUCKET}
    gsutil versioning set on gs://${TERRAFORM_STATE_BUCKET}
    echo -e "${GREEN}✓ Terraform state bucket created${NC}"
else
    echo -e "${YELLOW}Terraform state bucket already exists${NC}"
fi
echo "Using bucket: ${TERRAFORM_STATE_BUCKET}"

# Deploy infrastructure
echo "=========================================="
echo "Step 1: Deploying Infrastructure"
echo "=========================================="
cd terraform

# Create tfvars file
cat > terraform.tfvars <<EOF
project_id              = "$PROJECT_ID"
region                  = "$REGION"
zone                    = "$ZONE"
mongodb_password        = "$MONGODB_PASSWORD"
environment            = "wiz-exercise"
gke_node_count         = 1
gke_machine_type       = "e2-small"
mongodb_vm_machine_type = "e2-micro"
EOF

echo "Initializing Terraform..."
terraform init \
  -backend-config="bucket=${TERRAFORM_STATE_BUCKET}" \
  -backend-config="prefix=terraform/state"

echo "Planning Terraform deployment..."
terraform plan -out=tfplan

echo "Applying Terraform configuration..."
terraform apply -auto-approve tfplan

echo "Saving Terraform outputs..."
terraform output -json > ../terraform-outputs.json

MONGODB_IP=$(terraform output -raw mongodb_vm_internal_ip)
DOCKER_REPO=$(terraform output -raw docker_repository)

echo -e "${GREEN}✓ Infrastructure deployed successfully${NC}"
echo "MongoDB Internal IP: $MONGODB_IP"
echo "Docker Repository: $DOCKER_REPO"
echo ""

cd ..

# Wait for GKE cluster
echo "Waiting for GKE cluster to be ready..."
sleep 30

# Configure kubectl
echo "=========================================="
echo "Step 2: Configuring kubectl"
echo "=========================================="
gcloud container clusters get-credentials $CLUSTER_NAME \
  --region $REGION \
  --project $PROJECT_ID

kubectl cluster-info
echo -e "${GREEN}✓ kubectl configured${NC}"
echo ""

# Install NGINX Ingress
echo "=========================================="
echo "Step 3: Installing NGINX Ingress Controller"
echo "=========================================="
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.metrics.enabled=true \
  --wait \
  --timeout 10m

echo -e "${GREEN}✓ NGINX Ingress installed${NC}"
echo ""

# Build and push Docker image
echo "=========================================="
echo "Step 4: Building Docker Image"
echo "=========================================="

# Configure Docker for GCP
gcloud auth configure-docker ${REGION}-docker.pkg.dev

cd docker
echo "Building Docker image..."
docker build -t ${DOCKER_REPO}/todo-app:latest -f Dockerfile ../app

echo "Verifying wizexercise.txt..."
docker run --rm ${DOCKER_REPO}/todo-app:latest cat /app/wizexercise.txt

echo "Pushing Docker image..."
docker push ${DOCKER_REPO}/todo-app:latest

echo -e "${GREEN}✓ Docker image built and pushed${NC}"
cd ..
echo ""

# Deploy application
echo "=========================================="
echo "Step 5: Deploying Application"
echo "=========================================="
cd helm

helm upgrade --install todo-app ./todo-app \
  --namespace default \
  --create-namespace \
  --set image.repository=${DOCKER_REPO}/todo-app \
  --set image.tag=latest \
  --set mongodb.host=${MONGODB_IP} \
  --set mongodb.password=${MONGODB_PASSWORD} \
  --set jwt.secret=${JWT_SECRET} \
  --wait \
  --timeout 10m

echo -e "${GREEN}✓ Application deployed${NC}"
echo ""

# Wait for deployment
echo "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app=todo-app --timeout=300s

# Verify wizexercise.txt
echo "Verifying wizexercise.txt in pod..."
POD_NAME=$(kubectl get pods -l app=todo-app -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD_NAME -- cat /app/wizexercise.txt

cd ..

# Get Ingress IP
echo ""
echo "Waiting for Ingress IP address..."
for i in {1..60}; do
  INGRESS_IP=$(kubectl get ingress todo-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  if [ ! -z "$INGRESS_IP" ]; then
    break
  fi
  echo -n "."
  sleep 5
done
echo ""

# Display summary
echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""
echo -e "${GREEN}All components deployed successfully!${NC}"
echo ""
echo "Infrastructure:"
echo "  - GKE Cluster: $CLUSTER_NAME"
echo "  - MongoDB VM: wiz-exercise-mongodb-vm"
echo "  - MongoDB Internal IP: $MONGODB_IP"
echo "  - Docker Repository: $DOCKER_REPO"
echo ""
echo "Application:"
if [ ! -z "$INGRESS_IP" ]; then
  echo "  - Application URL: http://${INGRESS_IP}"
  echo "  - Try opening: http://${INGRESS_IP}"
else
  echo "  - Ingress IP not yet assigned. Check with: kubectl get ingress todo-app"
fi
echo ""
echo "Credentials:"
echo "  - MongoDB Password: $MONGODB_PASSWORD"
echo "  - JWT Secret: $JWT_SECRET"
echo ""
echo "Verification Commands:"
echo "  kubectl get pods"
echo "  kubectl get svc"
echo "  kubectl get ingress"
echo "  kubectl exec $POD_NAME -- cat /app/wizexercise.txt"
echo ""
echo "Next Steps:"
echo "  1. Open application URL in browser"
echo "  2. Create an account and test functionality"
echo "  3. Verify database connection"
echo "  4. Check backups in GCS"
echo "  5. Review security findings in Wiz"
echo ""
echo "=========================================="
