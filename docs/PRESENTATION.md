# Wiz Technical Exercise Presentation Guide

## Presentation Structure (45 minutes)

### 1. Introduction (3 minutes)
- Brief self-introduction
- Overview of the exercise objectives
- High-level architecture summary

### 2. Architecture Deep Dive (10 minutes)

#### Components Overview
Present the architecture diagram and explain:

**Frontend Tier:**
- Golang Todo application
- Containerized with Docker
- Runs on GKE (Google Kubernetes Engine)
- 2 replicas for high availability
- Exposed via NGINX Ingress Controller

**Database Tier:**
- MongoDB 4.4.29 (intentionally outdated - July 2020 release)
- Runs on Ubuntu 20.04 LTS VM (intentionally outdated)
- Located in public subnet with external IP
- Automated daily backups at 2 AM

**Storage:**
- Google Cloud Storage bucket for backups
- Intentionally configured with public read access
- 7-day retention policy

**Networking:**
- VPC with public and private subnets
- GKE cluster in private subnet (nodes have no external IPs)
- MongoDB VM in public subnet (has external IP)
- Cloud NAT for private subnet egress

### 3. Live Demonstration (15 minutes)

#### A. Infrastructure Verification
```bash
# Show GCP resources
gcloud compute instances list
gcloud container clusters list
gsutil ls

# Show Terraform state
cd terraform
terraform show
```

#### B. Kubernetes Demonstration
```bash
# Configure kubectl
gcloud container clusters get-credentials wiz-exercise-gke-cluster \
  --region us-central1 \
  --project clgcporg10-158

# Show cluster info
kubectl cluster-info
kubectl get nodes
kubectl get namespaces

# Show application pods
kubectl get pods -o wide
kubectl describe pod <pod-name>

# Verify wizexercise.txt file (CRITICAL REQUIREMENT)
POD_NAME=$(kubectl get pods -l app=todo-app -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD_NAME -- cat /app/wizexercise.txt

# Show service and ingress
kubectl get svc
kubectl get ingress

# Show RBAC configuration (vulnerable - cluster-admin)
kubectl get clusterrolebinding | grep todo-app
kubectl describe clusterrolebinding todo-app-admin
```

#### C. Application Functionality
```bash
# Get application URL
INGRESS_IP=$(kubectl get ingress todo-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Application URL: http://$INGRESS_IP"

# Demo the application in browser:
# 1. Sign up for new account
# 2. Create todo items
# 3. Mark items complete
# 4. Delete items
```

#### D. Database Connection Verification
```bash
# SSH to MongoDB VM
gcloud compute ssh wiz-exercise-mongodb-vm --zone us-central1-a

# Connect to MongoDB
mongo -u admin -p <password>

# Show databases
show dbs

# Switch to app database
use go-mongodb

# Show collections
show collections

# Verify todo data
db.todos.find().pretty()
db.users.find().pretty()

# Exit
exit
exit
```

#### E. Backup Verification
```bash
# Check cron job on VM
gcloud compute ssh wiz-exercise-mongodb-vm --zone us-central1-a
crontab -l

# Check backup logs
tail -f /var/log/mongodb-backup.log

# List backups in GCS
gsutil ls gs://wiz-mongodb-backups-<suffix>/

# Verify public access (VULNERABILITY)
# Open in browser without authentication:
# https://storage.googleapis.com/wiz-mongodb-backups-<suffix>/

# Or test with curl:
curl -I https://storage.googleapis.com/wiz-mongodb-backups-<suffix>/backup-<timestamp>.gz
```

### 4. Implementation Approach (7 minutes)

#### Infrastructure as Code (Terraform)
- Modular design with separate files for network, compute, storage
- Used variables for flexibility
- Outputs for easy access to resource information
- State stored in GCS backend

#### DevOps Automation (GitHub Actions)
**Infrastructure Pipeline:**
- Terraform format checking
- Validation and planning
- Wiz IaC scanning
- Automated apply on merge to main

**Application Pipeline:**
- Docker image build
- wizexercise.txt verification during build
- Container vulnerability scanning (Trivy + Wiz)
- Push to Artifact Registry
- Helm deployment to GKE
- Post-deployment verification

#### Challenges Faced and Solutions
1. **Challenge**: MongoDB connectivity from GKE pods
   - **Solution**: Used internal IP address and proper network configuration
   
2. **Challenge**: wizexercise.txt file inclusion
   - **Solution**: Added to Dockerfile with verification step
   
3. **Challenge**: Backup script compilation on VM
   - **Solution**: Included Go installation in startup script
   
4. **Challenge**: Cost management
   - **Solution**: Used e2-small/e2-micro instances, minimal storage

### 5. Security Findings (10 minutes)

#### Critical Vulnerabilities

**1. SSH Exposed to Internet (0.0.0.0/0)**
- **Finding**: MongoDB VM allows SSH from any IP address
- **Impact**: Brute force attacks, unauthorized access
- **Detection**: Wiz will flag firewall rule
- **Remediation**: Restrict to specific IP ranges or use IAP tunneling

**2. Public Database Backups**
- **Finding**: GCS bucket has public read access
- **Impact**: Data exfiltration, compliance violations
- **Detection**: Wiz will flag public storage bucket
- **Remediation**: Remove public access, use signed URLs

**3. Overly Permissive IAM Roles**
- **Finding**: MongoDB VM has compute.admin role
- **Impact**: Can create/delete VMs, lateral movement
- **Detection**: Wiz will flag excessive permissions
- **Remediation**: Apply principle of least privilege

**4. Outdated Software Versions**
- **Finding**: MongoDB 4.4.x (3+ years old), Ubuntu 20.04
- **Impact**: Known CVEs, unpatched vulnerabilities
- **Detection**: Wiz vulnerability scanning
- **Remediation**: Upgrade to MongoDB 7.x and Ubuntu 24.04

**5. Cluster-Admin Kubernetes RBAC**
- **Finding**: Application pods have cluster-admin privileges
- **Impact**: Full cluster control, privilege escalation
- **Detection**: Wiz will flag excessive K8s permissions
- **Remediation**: Create limited service account with minimal permissions

**6. Database in Public Subnet**
- **Finding**: MongoDB VM has external IP address
- **Impact**: Increased attack surface
- **Detection**: Wiz will flag internet-facing database
- **Remediation**: Move to private subnet, use Cloud SQL

#### Demonstrate Wiz Platform
- Log into Wiz console
- Show detected vulnerabilities
- Demonstrate cloud security graph
- Show compliance violations
- Demonstrate remediation guidance
- Show risk prioritization

### 6. Q&A and Closing (5 minutes)
- Open floor for questions
- Discuss real-world applications
- Thank the panel

## Presentation Tips

### Do's:
✓ Use a mix of slides and live terminal/browser
✓ Have backup screenshots in case of technical issues
✓ Explain your thinking process and decision-making
✓ Be honest about challenges and how you overcame them
✓ Show enthusiasm for the technology
✓ Demonstrate depth of knowledge
✓ Connect findings to business impact

### Don'ts:
✗ Rush through demonstrations
✗ Apologize excessively for intentional vulnerabilities
✗ Skip the wizexercise.txt verification
✗ Forget to show the actual application working
✗ Go over time limit
✗ Be defensive about design choices

## Technical Checklist

Before presentation, verify:
- [ ] Infrastructure is deployed and running
- [ ] Application is accessible via load balancer
- [ ] Can create and view todos in the application
- [ ] wizexercise.txt file is in container
- [ ] Can SSH to MongoDB VM
- [ ] Can query MongoDB database
- [ ] Backups exist in GCS bucket
- [ ] GCS bucket is publicly accessible
- [ ] kubectl commands work
- [ ] Have all credentials ready
- [ ] Wiz platform is configured and showing findings

## Key Talking Points

### Technical Proficiency
- "I chose GKE for Kubernetes because..."
- "The network architecture uses private subnets for..."
- "I implemented automated backups using..."

### DevOps Practices
- "The CI/CD pipeline ensures..."
- "I used Terraform modules to..."
- "The Helm chart provides..."

### Security Awareness
- "While this configuration intentionally includes vulnerabilities..."
- "In production, we would never..."
- "Wiz detected these issues immediately..."
- "The business impact of this vulnerability is..."

### Problem Solving
- "When I encountered X, I debugged by..."
- "I researched several approaches and chose..."
- "The trade-off here was between..."

## Post-Presentation

After the presentation:
1. Ask for feedback
2. Take notes on suggested improvements
3. Follow up with thank you email
4. Clean up GCP resources to avoid charges

## Emergency Backup Plans

If live demo fails:
1. Have screenshots/video recordings ready
2. Walk through code in GitHub
3. Show Terraform plan output
4. Demonstrate locally if possible

If Wiz platform unavailable:
1. Have screenshots of Wiz findings
2. Discuss expected findings
3. Reference Wiz documentation
