#!/bin/bash
# ============================================
# Multi-Environment Cleanup Script
# ============================================
# Clean up preprod or prod environment

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ID="${GCP_PROJECT_ID:-clgcporg10-158}"
REGION="${GCP_REGION:-us-central1}"
ZONE="${GCP_ZONE:-us-central1-a}"

print_message() {
    local color=$1
    shift
    echo -e "${color}$@${NC}"
}

print_section() {
    echo ""
    print_message "${BLUE}" "=========================================="
    print_message "${BLUE}" "$1"
    print_message "${BLUE}" "=========================================="
    echo ""
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up Wiz Technical Exercise environments

OPTIONS:
    -e, --environment ENV    Environment to clean up (preprod|prod|all) [required]
    -f, --force              Skip confirmation prompts
    -h, --help               Display this help message

EXAMPLES:
    # Clean up preprod environment
    $0 --environment preprod
    
    # Clean up production with no prompts
    $0 --environment prod --force
    
    # Clean up both environments
    $0 --environment all

EOF
}

# Parse arguments
ENVIRONMENT=""
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
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

if [ -z "$ENVIRONMENT" ]; then
    print_message "${RED}" "Error: Environment is required"
    usage
    exit 1
fi

if [[ "$ENVIRONMENT" != "preprod" && "$ENVIRONMENT" != "prod" && "$ENVIRONMENT" != "all" ]]; then
    print_message "${RED}" "Error: Environment must be 'preprod', 'prod', or 'all'"
    exit 1
fi

# Function to clean up a single environment
cleanup_environment() {
    local env=$1
    
    print_section "Cleaning Up: $env"
    
    if [ "$FORCE" != true ]; then
        print_message "${RED}" "⚠️  WARNING: This will DELETE all resources in $env environment"
        read -p "Type '$env' to confirm: " confirm
        if [ "$confirm" != "$env" ]; then
            print_message "${YELLOW}" "Cleanup cancelled for $env"
            return 0
        fi
    fi
    
    # Configure GCP
    gcloud config set project $PROJECT_ID
    gcloud config set compute/region $REGION
    gcloud config set compute/zone $ZONE
    
    # Get GKE credentials (if cluster exists)
    print_message "${BLUE}" "Getting GKE credentials..."
    if gcloud container clusters describe wiz-${env}-gke-cluster --region ${REGION} &>/dev/null; then
        gcloud container clusters get-credentials \
            wiz-${env}-gke-cluster \
            --region ${REGION} \
            --project ${PROJECT_ID} || true
        
        # Delete Helm releases
        print_message "${BLUE}" "Uninstalling Helm releases..."
        helm uninstall todo-app -n default 2>/dev/null || true
        helm uninstall ingress-nginx -n ingress-nginx 2>/dev/null || true
        
        # Wait for LoadBalancers to be deleted
        print_message "${BLUE}" "Waiting for LoadBalancers to be cleaned up..."
        sleep 30
        
        # Delete remaining resources
        kubectl delete all --all -n default 2>/dev/null || true
        kubectl delete pvc --all -n default 2>/dev/null || true
        kubectl delete ingress --all -n default 2>/dev/null || true
    fi
    
    # Destroy infrastructure with Terraform
    print_message "${BLUE}" "Running Terraform destroy..."
    cd "${SCRIPT_DIR}/terraform"
    
    # Check if MONGODB_PASSWORD is set
    if [ -z "$MONGODB_PASSWORD" ]; then
        print_message "${YELLOW}" "MONGODB_PASSWORD not set, using dummy value for destroy"
        MONGODB_PASSWORD="dummy-password-for-destroy"
    fi
    
    terraform init \
        -backend-config="bucket=wiz-terraform-state-${PROJECT_ID}" \
        -backend-config="prefix=terraform/${env}/state" || true
    
    terraform workspace select ${env} || true
    
    terraform destroy \
        -var-file="${env}.tfvars" \
        -var="mongodb_password=${MONGODB_PASSWORD}" \
        -auto-approve || true
    
    cd "${SCRIPT_DIR}"
    
    # Manual cleanup of any remaining resources
    print_message "${BLUE}" "Checking for remaining resources..."
    
    # Clean up forwarding rules
    for rule in $(gcloud compute forwarding-rules list --filter="name~wiz-${env}" --format="value(name)" --regions=${REGION} 2>/dev/null); do
        print_message "${YELLOW}" "Deleting forwarding rule: $rule"
        gcloud compute forwarding-rules delete $rule --region=${REGION} --quiet || true
    done
    
    # Clean up target pools
    for pool in $(gcloud compute target-pools list --filter="name~wiz-${env}" --format="value(name)" --regions=${REGION} 2>/dev/null); do
        print_message "${YELLOW}" "Deleting target pool: $pool"
        gcloud compute target-pools delete $pool --region=${REGION} --quiet || true
    done
    
    # Clean up firewall rules
    for rule in $(gcloud compute firewall-rules list --filter="name~wiz-${env}" --format="value(name)" 2>/dev/null); do
        print_message "${YELLOW}" "Deleting firewall rule: $rule"
        gcloud compute firewall-rules delete $rule --quiet || true
    done
    
    # Clean up static IPs
    for ip in $(gcloud compute addresses list --filter="name~wiz-${env}" --format="value(name)" --regions=${REGION} 2>/dev/null); do
        print_message "${YELLOW}" "Deleting static IP: $ip"
        gcloud compute addresses delete $ip --region=${REGION} --quiet || true
    done
    
    # Clean up GCS buckets
    for bucket in $(gsutil ls | grep "wiz-${env}" 2>/dev/null); do
        print_message "${YELLOW}" "Deleting bucket: $bucket"
        gsutil -m rm -r $bucket || true
    done
    
    # Clean up Artifact Registry repositories
    for repo in $(gcloud artifacts repositories list --location=${REGION} --filter="name~wiz-${env}" --format="value(name)" 2>/dev/null); do
        print_message "${YELLOW}" "Deleting Artifact Registry repo: $repo"
        gcloud artifacts repositories delete $repo --location=${REGION} --quiet || true
    done
    
    # Clean up service accounts
    for sa in $(gcloud iam service-accounts list --filter="email~wiz-${env}" --format="value(email)" 2>/dev/null); do
        print_message "${YELLOW}" "Deleting service account: $sa"
        gcloud iam service-accounts delete $sa --quiet || true
    done
    
    print_message "${GREEN}" "✓ Cleanup complete for $env environment"
}

# Main execution
print_section "Wiz Exercise Cleanup"
echo "Environment(s): $ENVIRONMENT"
echo "Force mode:     $FORCE"
echo ""

if [ "$ENVIRONMENT" == "all" ]; then
    cleanup_environment "preprod"
    cleanup_environment "prod"
else
    cleanup_environment "$ENVIRONMENT"
fi

print_section "Cleanup Summary"
print_message "${GREEN}" "✓ All done!"
print_message "${YELLOW}" "Note: Terraform state files are preserved in gs://wiz-terraform-state-${PROJECT_ID}"
print_message "${YELLOW}" "To delete state files manually:"
echo "  gsutil -m rm -r gs://wiz-terraform-state-${PROJECT_ID}/terraform/${ENVIRONMENT}/"
