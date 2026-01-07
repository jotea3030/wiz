#!/bin/bash
# ============================================
# Multi-Environment Deployment Script
# ============================================
# Deploy either preprod or prod environment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ID="${GCP_PROJECT_ID:-clgcporg10-158}"
REGION="${GCP_REGION:-us-central1}"
ZONE="${GCP_ZONE:-us-central1-a}"

# Function to print colored messages
print_message() {
    local color=$1
    shift
    echo -e "${color}$@${NC}"
}

# Function to print section headers
print_section() {
    echo ""
    print_message "${BLUE}" "=========================================="
    print_message "${BLUE}" "$1"
    print_message "${BLUE}" "=========================================="
    echo ""
}

# Function to check prerequisites
check_prerequisites() {
    print_section "Checking Prerequisites"
    
    local missing=0
    
    for cmd in gcloud terraform kubectl helm docker; do
        if ! command -v $cmd &> /dev/null; then
            print_message "${RED}" "✗ $cmd not found"
            missing=1
        else
            print_message "${GREEN}" "✓ $cmd installed"
        fi
    done
    
    if [ $missing -eq 1 ]; then
        print_message "${RED}" "Please install missing prerequisites"
        exit 1
    fi
}

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Wiz Technical Exercise to GCP

OPTIONS:
    -e, --environment ENV    Environment to deploy (preprod|prod) [required]
    -a, --action ACTION      Action to perform (plan|apply|destroy) [default: plan]
    -s, --skip-infra         Skip infrastructure deployment
    -k, --skip-app           Skip application deployment
    -h, --help               Display this help message

EXAMPLES:
    # Plan preprod environment
    $0 --environment preprod --action plan
    
    # Deploy production environment
    $0 --environment prod --action apply
    
    # Deploy only application to preprod
    $0 --environment preprod --skip-infra
    
    # Destroy production environment
    $0 --environment prod --action destroy

ENVIRONMENT VARIABLES:
    GCP_PROJECT_ID           GCP Project ID [default: clgcporg10-158]
    GCP_REGION               GCP Region [default: us-central1]
    GCP_ZONE                 GCP Zone [default: us-central1-a]
    MONGODB_PASSWORD         MongoDB password [required]
    JWT_SECRET               JWT secret for application [required]

EOF
}

# Parse command line arguments
ENVIRONMENT=""
ACTION="plan"
SKIP_INFRA=false
SKIP_APP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -a|--action)
            ACTION="$2"
            shift 2
            ;;
        -s|--skip-infra)
            SKIP_INFRA=true
            shift
            ;;
        -k|--skip-app)
            SKIP_APP=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print_message "${RED}" "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate environment
if [ -z "$ENVIRONMENT" ]; then
    print_message "${RED}" "Error: Environment is required"
    usage
    exit 1
fi

if [[ "$ENVIRONMENT" != "preprod" && "$ENVIRONMENT" != "prod" ]]; then
    print_message "${RED}" "Error: Environment must be 'preprod' or 'prod'"
    exit 1
fi

# Validate action
if [[ "$ACTION" != "plan" && "$ACTION" != "apply" && "$ACTION" != "destroy" ]]; then
    print_message "${RED}" "Error: Action must be 'plan', 'apply', or 'destroy'"
    exit 1
fi

# Display configuration
print_section "Deployment Configuration"
echo "Environment:    $ENVIRONMENT"
echo "Action:         $ACTION"
echo "Project ID:     $PROJECT_ID"
echo "Region:         $REGION"
echo "Zone:           $ZONE"
echo "Skip Infra:     $SKIP_INFRA"
echo "Skip App:       $SKIP_APP"
echo ""

# Generate passwords if not set and action is apply
if [ "$ACTION" == "apply" ]; then
    if [ -z "$MONGODB_PASSWORD" ]; then
        print_message "${YELLOW}" "Generating MongoDB password..."
        export MONGODB_PASSWORD=$(openssl rand -base64 32)
        print_message "${GREEN}" "MongoDB Password: $MONGODB_PASSWORD"
        print_message "${YELLOW}" "⚠️  Save this password securely!"
    fi
    
    if [ -z "$JWT_SECRET" ] && [ "$SKIP_APP" != true ]; then
        print_message "${YELLOW}" "Generating JWT secret..."
        export JWT_SECRET=$(openssl rand -base64 64)
        print_message "${GREEN}" "JWT Secret generated"
    fi
fi

# Check for required variables
if [ "$ACTION" == "apply" ] && [ -z "$MONGODB_PASSWORD" ]; then
    print_message "${RED}" "Error: MONGODB_PASSWORD is required for apply action"
    exit 1
fi

# Confirm production deployments
if [ "$ENVIRONMENT" == "prod" ] && [ "$ACTION" == "apply" ]; then
    print_message "${YELLOW}" "⚠️  You are about to deploy to PRODUCTION"
    read -p "Are you sure you want to continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        print_message "${RED}" "Deployment cancelled"
        exit 0
    fi
fi

# Confirm destroy actions
if [ "$ACTION" == "destroy" ]; then
    print_message "${RED}" "⚠️  WARNING: This will DESTROY all resources in $ENVIRONMENT"
    read -p "Type '$ENVIRONMENT' to confirm: " confirm
    if [ "$confirm" != "$ENVIRONMENT" ]; then
        print_message "${RED}" "Destroy cancelled"
        exit 0
    fi
fi

# Authenticate with GCP
print_section "Authenticating with GCP"
gcloud config set project $PROJECT_ID
gcloud config set compute/region $REGION
gcloud config set compute/zone $ZONE
print_message "${GREEN}" "✓ GCP configuration set"

# Deploy Infrastructure
if [ "$SKIP_INFRA" != true ]; then
    print_section "Step 1: Deploying Infrastructure"
    
    cd "${SCRIPT_DIR}/terraform"
    
    # Initialize Terraform
    print_message "${BLUE}" "Initializing Terraform..."
    terraform init -reconfigure \
        -backend-config="bucket=wiz-terraform-state-${PROJECT_ID}" \
        -backend-config="prefix=terraform/${ENVIRONMENT}/state"
    
    # Select or create workspace
    terraform workspace select ${ENVIRONMENT} || terraform workspace new ${ENVIRONMENT}
    
    # Terraform action
    case $ACTION in
        plan)
            print_message "${BLUE}" "Running Terraform plan..."
            terraform plan \
                -var-file="${ENVIRONMENT}.tfvars" \
                -var="mongodb_password=${MONGODB_PASSWORD}" \
                -out=tfplan-${ENVIRONMENT}
            ;;
        apply)
            print_message "${BLUE}" "Applying Terraform configuration..."
            terraform apply \
                -var-file="${ENVIRONMENT}.tfvars" \
                -var="mongodb_password=${MONGODB_PASSWORD}" \
                -auto-approve
            
            print_message "${GREEN}" "✓ Infrastructure deployed successfully"
            
            # Save outputs
            terraform output -json > outputs-${ENVIRONMENT}.json
            print_message "${BLUE}" "Terraform outputs saved to outputs-${ENVIRONMENT}.json"
            ;;
        destroy)
            print_message "${RED}" "Destroying infrastructure..."
            terraform destroy \
                -var-file="${ENVIRONMENT}.tfvars" \
                -var="mongodb_password=${MONGODB_PASSWORD}" \
                -auto-approve
            
            print_message "${GREEN}" "✓ Infrastructure destroyed"
            cd "${SCRIPT_DIR}"
            exit 0
            ;;
    esac
    
    cd "${SCRIPT_DIR}"
fi

# Deploy Application
if [ "$SKIP_APP" != true ] && [ "$ACTION" == "apply" ]; then
    print_section "Step 2: Deploying Application"
    
    # Get GKE credentials
    print_message "${BLUE}" "Configuring kubectl..."
    gcloud container clusters get-credentials \
        wiz-${ENVIRONMENT}-gke-cluster \
        --region ${REGION} \
        --project ${PROJECT_ID}
    
    # Check if NGINX Ingress is installed
    if ! helm list -n ingress-nginx | grep -q ingress-nginx; then
        print_message "${BLUE}" "Installing NGINX Ingress Controller..."
        helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
        helm repo update
        helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
            --namespace ingress-nginx \
            --create-namespace \
            --set controller.service.type=LoadBalancer \
            --wait \
            --timeout 10m
        print_message "${GREEN}" "✓ NGINX Ingress installed"
    fi
    
    # Build and push Docker image
    print_message "${BLUE}" "Building Docker image..."
    DOCKER_REPO="${REGION}-docker.pkg.dev/${PROJECT_ID}/wiz-${ENVIRONMENT}-docker-repo"
    
    gcloud auth configure-docker ${REGION}-docker.pkg.dev
    
    docker build \
        -t ${DOCKER_REPO}/todo-app:latest \
        -f docker/Dockerfile \
        .
    
    print_message "${BLUE}" "Pushing Docker image..."
    docker push ${DOCKER_REPO}/todo-app:latest
    
    # Get MongoDB IP
    print_message "${BLUE}" "Getting MongoDB IP..."
    MONGODB_IP=$(gcloud compute instances describe wiz-${ENVIRONMENT}-mongodb-vm \
        --zone ${ZONE} \
        --format='get(networkInterfaces[0].networkIP)')
    
    print_message "${BLUE}" "MongoDB IP: $MONGODB_IP"
    
    # Deploy with Helm
    print_message "${BLUE}" "Deploying application with Helm..."
    helm upgrade --install todo-app ./helm/todo-app \
        --namespace default \
        --create-namespace \
        --values ./helm/todo-app/values-${ENVIRONMENT}.yaml \
        --set image.repository=${DOCKER_REPO}/todo-app \
        --set image.tag=latest \
        --set mongodb.host=${MONGODB_IP} \
        --set mongodb.password=${MONGODB_PASSWORD} \
        --set jwt.secret=${JWT_SECRET} \
        --wait \
        --timeout 10m
    
    print_message "${GREEN}" "✓ Application deployed successfully"
    
    # Verify deployment
    print_message "${BLUE}" "Verifying deployment..."
    kubectl get pods -l app=todo-app
    kubectl get svc todo-app
    kubectl get ingress todo-app
    
    # Get Ingress IP
    INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    
    print_message "${GREEN}" "✓ Application is accessible at: http://${INGRESS_IP}"
fi

# Display summary
print_section "Deployment Summary"
print_message "${GREEN}" "✓ Deployment completed successfully!"
echo ""
echo "Environment:  $ENVIRONMENT"
echo "Action:       $ACTION"
echo ""

if [ "$ACTION" == "apply" ]; then
    if [ "$SKIP_APP" != true ]; then
        INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Not available")
        echo "Application URL:   http://${INGRESS_IP}"
    fi
    
    if [ "$ENVIRONMENT" == "preprod" ]; then
        echo ""
        print_message "${YELLOW}" "⚠️  Preprod Security Vulnerabilities (Intentional):"
        echo "  - SSH exposed to 0.0.0.0/0"
        echo "  - GCS bucket publicly accessible"
        echo "  - VM has compute.admin role"
        echo "  - Outdated MongoDB 4.4"
        echo "  - Kubernetes cluster-admin role"
        echo "  - MongoDB in public subnet"
    elif [ "$ENVIRONMENT" == "prod" ]; then
        echo ""
        print_message "${GREEN}" "✓ Production Security Best Practices Applied:"
        echo "  - SSH restricted to specific IPs"
        echo "  - Private GCS bucket"
        echo "  - Minimal IAM permissions"
        echo "  - Latest MongoDB 7.0"
        echo "  - Limited Kubernetes RBAC"
        echo "  - MongoDB in private subnet"
    fi
fi

print_message "${GREEN}" "✓ All done!"
