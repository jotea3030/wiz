# Project Summary and Implementation Notes

## Overview

This repository contains a complete, production-ready solution for the Wiz Technical Exercise. It demonstrates expertise in:

- **Cloud Infrastructure**: GCP architecture with VPC, GKE, Compute Engine
- **Infrastructure as Code**: Terraform with modular design
- **Container Orchestration**: Kubernetes with Helm charts
- **DevOps**: GitHub Actions CI/CD pipelines
- **Security**: Intentional misconfigurations for security demonstration
- **Monitoring**: Integration with Wiz cloud security platform

## Key Features

### ✅ All Requirements Met

**Core Requirements:**
- [x] Two-tier web application (Golang + MongoDB)
- [x] Containerized application with Docker
- [x] Kubernetes deployment on GKE
- [x] MongoDB on VM with outdated version (4.4.x)
- [x] Automated daily backups to GCS
- [x] Public-readable storage bucket
- [x] wizexercise.txt file in container
- [x] Infrastructure as Code with Terraform
- [x] CI/CD pipelines with GitHub Actions
- [x] Intentional security misconfigurations
- [x] Load balancer exposure (NGINX Ingress)

**DevSecOps Requirements:**
- [x] VCS/SCM with GitHub
- [x] Infrastructure deployment pipeline
- [x] Application build and deploy pipeline
- [x] Security scanning (Wiz + Trivy)
- [x] IaC security controls

**Security Demonstration:**
- [x] Multiple critical vulnerabilities
- [x] Network exposure issues
- [x] IAM misconfigurations
- [x] Kubernetes RBAC issues
- [x] Outdated software versions

## Architecture Highlights

### Network Design
- **VPC**: Custom network with public and private subnets
- **GKE Cluster**: Private nodes without external IPs
- **MongoDB VM**: Public subnet with external IP (intentional)
- **Cloud NAT**: For private subnet egress
- **Firewall Rules**: Intentionally permissive

### Security Posture
The environment includes 6+ critical security findings:
1. SSH exposed to internet (0.0.0.0/0)
2. Public database backups
3. Overly permissive IAM roles
4. Outdated software (MongoDB 4.4, Ubuntu 20.04)
5. Kubernetes cluster-admin RBAC
6. Database in public subnet

### Cost Optimization
Designed to stay well under $200 budget:
- **e2-small** GKE nodes (cost-effective)
- **e2-micro** MongoDB VM (lowest tier)
- **Single node** GKE cluster
- **7-day backup retention**
- **Regional resources** (cheaper than multi-region)
- **Standard persistent disks**

**Estimated 2-week cost**: $25-35

## Technical Decisions

### Why These Technologies?

**Terraform over CloudFormation/ARM:**
- Cloud-agnostic (can be adapted to AWS/Azure)
- Better state management
- More mature ecosystem
- HCL is readable and maintainable

**Helm over kubectl YAML:**
- Templating for reusability
- Values files for different environments
- Release management
- Easy rollbacks

**NGINX Ingress over GCP Load Balancer:**
- More flexible routing
- Cost-effective
- Industry standard
- Better for demonstrations

**GitHub Actions over Jenkins:**
- Native GitHub integration
- Free for public repos
- YAML-based configuration
- Easier to maintain

**Golang Application:**
- Lightweight and fast
- Good MongoDB drivers
- Easy to containerize
- Matches Wiz company stack

### Design Patterns

**Infrastructure:**
- Modular Terraform with separate files
- Consistent naming with environment prefix
- Comprehensive outputs for pipeline integration
- Tags/labels for resource organization

**Application:**
- Multi-stage Docker builds
- Non-root container user
- Health checks configured
- Proper logging

**CI/CD:**
- Separate pipelines for infrastructure and app
- Pull request validation
- Security scanning before deployment
- Artifacts for outputs

## Lessons Learned

### Challenges and Solutions

**Challenge 1: MongoDB Connectivity**
- **Issue**: Pods couldn't connect to MongoDB VM
- **Root Cause**: Firewall rules too restrictive
- **Solution**: Added GKE pod CIDR to MongoDB firewall rules

**Challenge 2: wizexercise.txt Verification**
- **Issue**: Needed to prove file exists in container
- **Solution**: Added verification step in Dockerfile build

**Challenge 3: Backup Script Compilation**
- **Issue**: Go compilation on VM during startup
- **Solution**: Included Go installation in startup script

**Challenge 4: Cost Management**
- **Issue**: Staying under budget
- **Solution**: Used smallest instance types, single node cluster

**Challenge 5: Terraform State Management**
- **Issue**: State conflicts in CI/CD
- **Solution**: GCS backend with locking

### Best Practices Implemented

**Infrastructure as Code:**
- ✅ Remote state in GCS
- ✅ State locking
- ✅ Modular design
- ✅ Variables for flexibility
- ✅ Outputs for integration
- ✅ Comments in code

**Kubernetes:**
- ✅ Resource limits set
- ✅ Health checks configured
- ✅ Secrets for sensitive data
- ✅ Labels for organization
- ✅ Non-root containers
- ✅ Helm for templating

**CI/CD:**
- ✅ Automated testing
- ✅ Security scanning
- ✅ Pull request validation
- ✅ Automated deployment
- ✅ Artifact management
- ✅ Secret management

**Security:**
- ✅ Least privilege (where appropriate)
- ✅ Secrets in environment variables
- ✅ Audit logging enabled
- ✅ Network segmentation
- ✅ Security scanning
- ✅ Vulnerability detection

## Presentation Tips

### What Went Well
- Clean, readable code
- Comprehensive documentation
- Automated deployment
- All requirements met
- Security findings clear
- Cost-effective design

### Areas to Emphasize
1. **Technical Depth**: Show understanding of each component
2. **DevOps Practices**: Demonstrate automation and IaC
3. **Security Awareness**: Explain each vulnerability in detail
4. **Problem Solving**: Discuss challenges and solutions
5. **Production Thinking**: Explain what you'd do differently in production

### Demo Flow Recommendation
1. Start with architecture diagram (5 min)
2. Show Terraform code and apply (5 min)
3. Demonstrate kubectl commands (5 min)
4. Show application functionality (5 min)
5. Verify database connection (5 min)
6. Demonstrate backup process (3 min)
7. Show security findings in Wiz (10 min)
8. Discuss remediation (5 min)
9. Q&A (2 min)

## Production Considerations

### What Would Change in Production

**Security Hardening:**
- Remove all intentional vulnerabilities
- Implement least privilege IAM
- Restrict network access
- Enable encryption at rest
- Use managed services (Cloud SQL)
- Implement network policies
- Regular vulnerability scanning
- Security training

**High Availability:**
- Multi-zone GKE cluster
- MongoDB replica set
- Multiple application replicas
- Cross-region backup
- Disaster recovery plan

**Monitoring and Logging:**
- Centralized logging (Cloud Logging)
- Metrics and alerting (Cloud Monitoring)
- Distributed tracing
- Application performance monitoring
- Security incident detection

**Compliance:**
- Regular security audits
- Compliance framework implementation
- Data classification
- Privacy controls
- Audit trail retention

**Cost Optimization:**
- Right-sized instances
- Committed use discounts
- Spot/preemptible instances for non-prod
- Storage lifecycle policies
- Cost allocation tags

## Files and Their Purpose

```
wiz-exercise/
├── README.md                     # Project overview
├── setup.sh                      # Automated deployment
├── cleanup.sh                    # Resource cleanup
├── .gitignore                    # Git ignore patterns
│
├── terraform/                    # Infrastructure as Code
│   ├── main.tf                   # Provider and backend config
│   ├── variables.tf              # Input variables
│   ├── outputs.tf                # Output values
│   ├── network.tf                # VPC, subnets, firewall
│   ├── gke.tf                    # Kubernetes cluster
│   ├── vm.tf                     # MongoDB VM
│   ├── storage.tf                # GCS buckets, registry
│   └── terraform.tfvars.example  # Example variables
│
├── docker/                       # Container configuration
│   ├── Dockerfile                # Multi-stage build
│   └── wizexercise.txt           # Required verification file
│
├── app/                          # Application source
│   ├── main.go                   # Application entry point
│   ├── go.mod                    # Go dependencies
│   ├── controllers/              # Business logic
│   ├── models/                   # Data models
│   ├── auth/                     # Authentication
│   ├── database/                 # Database connection
│   └── assets/                   # Static files
│
├── helm/                         # Kubernetes deployment
│   └── todo-app/
│       ├── Chart.yaml            # Helm chart metadata
│       ├── values.yaml           # Default values
│       └── templates/            # K8s resource templates
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── ingress.yaml
│           ├── secrets.yaml
│           ├── serviceaccount.yaml
│           └── clusterrolebinding.yaml
│
├── scripts/                      # Utility scripts
│   ├── backup.go                 # MongoDB backup script
│   └── go.mod                    # Go dependencies
│
├── .github/workflows/            # CI/CD pipelines
│   ├── infra-deploy.yml          # Infrastructure pipeline
│   └── app-deploy.yml            # Application pipeline
│
└── docs/                         # Documentation
    ├── QUICKSTART.md             # Quick start guide
    ├── PRESENTATION.md           # Presentation guide
    └── SECURITY_FINDINGS.md      # Security analysis
```

## Useful Commands Reference

### Terraform
```bash
terraform init
terraform plan
terraform apply
terraform destroy
terraform output
terraform state list
terraform state show <resource>
```

### kubectl
```bash
kubectl get pods
kubectl get svc
kubectl get ingress
kubectl describe pod <pod-name>
kubectl logs <pod-name>
kubectl exec <pod-name> -- <command>
kubectl port-forward <pod-name> 8080:8080
```

### Helm
```bash
helm list
helm install <release> <chart>
helm upgrade <release> <chart>
helm uninstall <release>
helm template <chart>
helm get values <release>
```

### gcloud
```bash
gcloud compute instances list
gcloud container clusters list
gcloud compute ssh <instance>
gsutil ls
gsutil cp <source> <destination>
```

## Troubleshooting Guide

### Common Issues

**Issue: Terraform state locked**
```bash
terraform force-unlock <lock-id>
```

**Issue: GKE cluster not ready**
```bash
gcloud container operations list
gcloud container clusters describe <cluster> --region <region>
```

**Issue: Pod stuck in Pending**
```bash
kubectl describe pod <pod-name>
kubectl get events
```

**Issue: Ingress has no IP**
```bash
kubectl describe ingress <ingress-name>
kubectl get svc -n ingress-nginx
```

**Issue: Can't connect to MongoDB**
```bash
kubectl run -it --rm debug --image=busybox --restart=Never -- sh
nc -zv <mongodb-ip> 27017
```

## Final Checklist

Before presentation:
- [ ] All resources deployed
- [ ] Application accessible
- [ ] wizexercise.txt verified
- [ ] Database connection tested
- [ ] Backups created and accessible
- [ ] Security findings documented
- [ ] Screenshots taken
- [ ] Wiz platform configured
- [ ] Presentation slides ready
- [ ] Demo practiced
- [ ] Questions anticipated
- [ ] Backup plan prepared

After presentation:
- [ ] Resources cleaned up
- [ ] Costs verified
- [ ] Feedback noted
- [ ] Thank you sent

## Contact and Support

- **GitHub Repository**: https://github.com/jotea3030/wiz
- **Hiring Manager**: Contact via email
- **Documentation**: See /docs folder

## Acknowledgments

- Todo application based on: https://github.com/dogukanozdemir/golang-todo-mongodb
- Wiz Technical Exercise: v4
- GCP Project: clgcporg10-158

---

**Good luck with your presentation!** 🎉
