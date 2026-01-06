#!/bin/bash
set -e

# Wiz Technical Exercise - Cleanup Script
# This script removes all deployed resources

echo "=========================================="
echo "Wiz Technical Exercise - Cleanup Script"
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
CLUSTER_NAME="wiz-exercise-gke-cluster"

echo -e "${YELLOW}WARNING: This will delete ALL resources created for the Wiz exercise!${NC}"
echo "Resources to be deleted:"
echo "  - GKE Cluster: $CLUSTER_NAME"
echo "  - MongoDB VM: wiz-exercise-mongodb-vm"
echo "  - VPC Network: wiz-exercise-vpc"
echo "  - Storage Buckets: wiz-mongodb-backups-*"
echo "  - All associated resources (IPs, disks, etc.)"
echo ""
read -p "Are you sure you want to continue? (type 'yes' to confirm): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo "Starting cleanup process..."
echo ""

# Set project
gcloud config set project $PROJECT_ID

# Delete Helm releases
echo "Step 1: Deleting Helm releases..."
if helm list -q | grep -q "todo-app"; then
    helm uninstall todo-app --namespace default || true
    echo -e "${GREEN}✓ Helm release deleted${NC}"
else
    echo -e "${YELLOW}No Helm releases found${NC}"
fi

if helm list -n ingress-nginx -q | grep -q "ingress-nginx"; then
    helm uninstall ingress-nginx --namespace ingress-nginx || true
    echo -e "${GREEN}✓ NGINX Ingress deleted${NC}"
else
    echo -e "${YELLOW}NGINX Ingress not found${NC}"
fi

echo ""
sleep 5

# Delete Kubernetes resources manually if helm failed
echo "Step 2: Cleaning up Kubernetes resources..."
kubectl delete all --all -n default --grace-period=0 --force || true
kubectl delete ingress --all -n default || true
kubectl delete all --all -n ingress-nginx --grace-period=0 --force || true
sleep 10
echo -e "${GREEN}✓ Kubernetes resources cleaned up${NC}"
echo ""

# Terraform destroy
echo "Step 3: Destroying infrastructure with Terraform..."
cd terraform

if [ -f "terraform.tfvars" ]; then
    echo "Found terraform.tfvars, proceeding with destroy..."
    terraform init \
      -backend-config="bucket=wiz-terraform-state" \
      -backend-config="prefix=terraform/state" || true
    
    terraform destroy -auto-approve || {
        echo -e "${RED}Terraform destroy failed. Continuing with manual cleanup...${NC}"
    }
else
    echo -e "${YELLOW}terraform.tfvars not found, skipping Terraform destroy${NC}"
fi

cd ..
echo ""

# Manual cleanup of resources
echo "Step 4: Manual cleanup of remaining resources..."

# Delete GKE cluster
echo "Deleting GKE cluster..."
gcloud container clusters delete $CLUSTER_NAME \
  --region $REGION \
  --quiet 2>/dev/null || echo -e "${YELLOW}GKE cluster not found or already deleted${NC}"

# Delete compute instances
echo "Deleting compute instances..."
gcloud compute instances delete wiz-exercise-mongodb-vm \
  --zone ${REGION}-a \
  --quiet 2>/dev/null || echo -e "${YELLOW}MongoDB VM not found or already deleted${NC}"

# Delete firewall rules
echo "Deleting firewall rules..."
for rule in $(gcloud compute firewall-rules list --filter="name~wiz-exercise" --format="value(name)"); do
    gcloud compute firewall-rules delete $rule --quiet 2>/dev/null || true
done

# Delete external IPs
echo "Deleting external IP addresses..."
for ip in $(gcloud compute addresses list --filter="name~wiz-exercise" --format="value(name)"); do
    gcloud compute addresses delete $ip --region $REGION --quiet 2>/dev/null || true
done

# Delete Cloud NAT
echo "Deleting Cloud NAT..."
gcloud compute routers nats delete wiz-exercise-nat \
  --router=wiz-exercise-router \
  --region=$REGION \
  --quiet 2>/dev/null || echo -e "${YELLOW}NAT not found${NC}"

# Delete Cloud Router
echo "Deleting Cloud Router..."
gcloud compute routers delete wiz-exercise-router \
  --region=$REGION \
  --quiet 2>/dev/null || echo -e "${YELLOW}Router not found${NC}"

# Delete subnets
echo "Deleting subnets..."
gcloud compute networks subnets delete wiz-exercise-private-subnet \
  --region=$REGION \
  --quiet 2>/dev/null || echo -e "${YELLOW}Private subnet not found${NC}"

gcloud compute networks subnets delete wiz-exercise-public-subnet \
  --region=$REGION \
  --quiet 2>/dev/null || echo -e "${YELLOW}Public subnet not found${NC}"

# Delete VPC
echo "Deleting VPC network..."
gcloud compute networks delete wiz-exercise-vpc \
  --quiet 2>/dev/null || echo -e "${YELLOW}VPC not found${NC}"

# Delete storage buckets
echo "Deleting storage buckets..."
for bucket in $(gsutil ls | grep wiz-mongodb-backups); do
    echo "Deleting bucket: $bucket"
    gsutil -m rm -r $bucket 2>/dev/null || true
done

# Delete Artifact Registry repositories
echo "Deleting Artifact Registry repositories..."
gcloud artifacts repositories delete wiz-exercise-docker-repo \
  --location=$REGION \
  --quiet 2>/dev/null || echo -e "${YELLOW}Docker repository not found${NC}"

# Delete service accounts
echo "Deleting service accounts..."
for sa in $(gcloud iam service-accounts list --filter="email~wiz-exercise" --format="value(email)"); do
    gcloud iam service-accounts delete $sa --quiet 2>/dev/null || true
done

# Clean up local files
echo ""
echo "Step 5: Cleaning up local files..."
if [ -f "terraform/terraform.tfvars" ]; then
    rm terraform/terraform.tfvars
    echo "  - Deleted terraform.tfvars"
fi

if [ -f "terraform/.terraform.lock.hcl" ]; then
    rm terraform/.terraform.lock.hcl
    echo "  - Deleted .terraform.lock.hcl"
fi

if [ -d "terraform/.terraform" ]; then
    rm -rf terraform/.terraform
    echo "  - Deleted .terraform directory"
fi

if [ -f "terraform-outputs.json" ]; then
    rm terraform-outputs.json
    echo "  - Deleted terraform-outputs.json"
fi

echo -e "${GREEN}✓ Local files cleaned up${NC}"
echo ""

# Summary
echo "=========================================="
echo "Cleanup Complete!"
echo "=========================================="
echo ""
echo -e "${GREEN}All resources have been cleaned up.${NC}"
echo ""
echo "Verification commands:"
echo "  gcloud compute instances list"
echo "  gcloud container clusters list"
echo "  gsutil ls"
echo "  gcloud compute networks list"
echo ""
echo "Note: It may take a few minutes for all resources to be fully deleted."
echo "You can verify in the GCP Console: https://console.cloud.google.com"
echo ""
echo "If you want to redeploy, run ./setup.sh"
echo ""
echo "=========================================="
