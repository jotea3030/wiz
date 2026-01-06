# Security Findings and Analysis

## Executive Summary

This document details the intentional security misconfigurations implemented in the Wiz technical exercise environment. These configurations demonstrate real-world security issues that cloud security platforms like Wiz are designed to detect and remediate.

---

## Critical Findings

### 1. SSH Exposed to Internet (0.0.0.0/0)

**Severity**: CRITICAL  
**Category**: Network Security  
**Resource**: `wiz-exercise-mongodb-vm`

#### Description
The MongoDB VM has an SSH firewall rule allowing access from any IP address on the internet (0.0.0.0/0).

#### Evidence
```hcl
# terraform/network.tf
resource "google_compute_firewall" "allow_ssh_public" {
  name    = "${var.environment}-allow-ssh-public"
  network = google_compute_network.vpc.name
  
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  
  source_ranges = ["0.0.0.0/0"]  # VULNERABLE
  target_tags   = ["mongodb-server"]
}
```

#### Business Impact
- **Immediate Risk**: Exposes VM to brute force attacks from anywhere in the world
- **Data at Risk**: Entire database and backup system
- **Compliance**: Violates PCI-DSS 1.2.1, CIS Benchmark 3.9
- **Financial Impact**: Potential data breach could cost $millions

#### Attack Scenarios
1. **Brute Force**: Automated tools attempt common passwords
2. **Credential Stuffing**: Using leaked credentials from other breaches
3. **Zero-Day Exploits**: Targeting SSH vulnerabilities
4. **Lateral Movement**: Once compromised, attacker can pivot to GKE

#### Remediation
**Priority**: IMMEDIATE

**Recommended Actions**:
1. Restrict SSH to specific IP ranges (corporate VPN, jump hosts)
```hcl
source_ranges = ["10.0.0.0/8", "YOUR_OFFICE_IP/32"]
```

2. Use IAP (Identity-Aware Proxy) for SSH access:
```bash
gcloud compute ssh INSTANCE_NAME --tunnel-through-iap
```

3. Implement MFA for SSH authentication
4. Use certificate-based authentication instead of passwords
5. Enable OS Login for centralized authentication

**Wiz Detection**: Firewall rule analysis, network exposure detection

---

### 2. Publicly Accessible Database Backups

**Severity**: CRITICAL  
**Category**: Data Exposure  
**Resource**: `wiz-mongodb-backups-*` GCS bucket

#### Description
The GCS bucket containing MongoDB backups is configured with public read access, allowing anyone on the internet to list and download database backups.

#### Evidence
```hcl
# terraform/storage.tf
resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.mongodb_backups.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"  # CRITICAL VULNERABILITY
}
```

#### Business Impact
- **Data Exfiltration**: Complete database contents exposed
- **PII Exposure**: User data, passwords (even if hashed)
- **Compliance Violations**: GDPR, HIPAA, SOC 2 failures
- **Reputational Damage**: Loss of customer trust
- **Legal Liability**: Class action lawsuits, regulatory fines

#### Attack Scenarios
1. **Direct Download**: Anyone can download backups without authentication
```bash
curl https://storage.googleapis.com/wiz-mongodb-backups-xxxx/backup-20250105.gz
```

2. **Automated Scanning**: Tools like GrayhatWarfare scan for public buckets
3. **Competitive Intelligence**: Competitors accessing customer data
4. **Ransomware**: Download data, delete original, demand ransom

#### Real-World Example
Similar to the Capital One breach (2019) where publicly accessible S3 buckets exposed 100M customer records.

#### Remediation
**Priority**: IMMEDIATE

**Recommended Actions**:
1. Remove public access immediately:
```bash
gsutil iam ch -d allUsers:objectViewer gs://BUCKET_NAME
```

2. Implement authenticated access:
- Use service account with minimal permissions
- Generate signed URLs for temporary access
- Implement Workload Identity for GKE access

3. Enable bucket access logging
4. Implement Object Lifecycle Management
5. Enable Customer-Managed Encryption Keys (CMEK)
6. Use VPC Service Controls to prevent data exfiltration

**Wiz Detection**: Storage bucket policy analysis, public access detection

---

### 3. Overly Permissive IAM Role (Compute Admin)

**Severity**: CRITICAL  
**Category**: Identity and Access Management  
**Resource**: MongoDB VM service account

#### Description
The MongoDB VM service account has the `compute.admin` role, granting it the ability to create, modify, and delete any compute resources in the project.

#### Evidence
```hcl
# terraform/vm.tf
resource "google_project_iam_member" "mongodb_vm_compute_admin" {
  project = var.project_id
  role    = "roles/compute.admin"  # OVERLY PERMISSIVE
  member  = "serviceAccount:${google_service_account.mongodb_vm.email}"
}
```

#### Business Impact
- **Privilege Escalation**: VM compromise leads to full project control
- **Lateral Movement**: Can create VMs in other networks
- **Resource Manipulation**: Can delete critical infrastructure
- **Cost Abuse**: Can spin up expensive compute instances
- **Audit Trail Tampering**: Can delete or modify logs

#### Permissions Granted
The `compute.admin` role includes 500+ permissions, including:
- `compute.instances.create`
- `compute.instances.delete`
- `compute.disks.create`
- `compute.networks.create`
- `compute.firewalls.create`
- `compute.securityPolicies.create`

#### Required Permissions
The VM only needs:
- `storage.objects.create` (for backups)
- `storage.objects.get` (for backup verification)
- `logging.logEntries.create` (for logging)

#### Attack Scenarios
1. **Resource Creation**: Spin up mining VMs
2. **Backdoor Creation**: Create new VMs for persistence
3. **Network Manipulation**: Modify firewall rules
4. **Data Destruction**: Delete production resources

#### Remediation
**Priority**: HIGH

**Recommended Actions**:
1. Remove compute.admin role
2. Create custom role with minimal permissions:
```hcl
resource "google_project_iam_custom_role" "mongodb_backup" {
  role_id     = "mongodb_backup_role"
  title       = "MongoDB Backup Role"
  permissions = [
    "storage.objects.create",
    "storage.objects.get",
    "logging.logEntries.create"
  ]
}
```

3. Implement IAM Conditions for additional restrictions
4. Regular IAM access reviews
5. Enable audit logging for IAM changes

**Wiz Detection**: IAM policy analysis, privilege escalation detection

---

### 4. Outdated Software Versions

**Severity**: HIGH  
**Category**: Vulnerability Management  
**Resources**: MongoDB 4.4.29, Ubuntu 20.04 LTS

#### Description
The infrastructure uses software versions that are over 1 year old, containing known vulnerabilities (CVEs).

#### Evidence
**MongoDB 4.4.29**:
- Released: July 2020 (4+ years old)
- Current version: MongoDB 7.0.x
- Known CVEs: 15+ vulnerabilities

**Ubuntu 20.04 LTS**:
- Released: April 2020 (4+ years old)
- Current LTS: Ubuntu 24.04
- End of Standard Support: April 2025

#### Known Vulnerabilities
**MongoDB 4.4.x CVEs**:
- CVE-2023-1410: Privilege escalation
- CVE-2022-3564: Denial of service
- Multiple others with CVSS scores 7.0+

#### Business Impact
- **Exploitable Vulnerabilities**: Attackers have public exploits
- **Zero-Day Risk**: Vendors focus security updates on current versions
- **Compliance**: Fails security audits (SOC 2, ISO 27001)
- **Support**: No vendor support for critical issues

#### Remediation
**Priority**: HIGH

**Recommended Actions**:
1. Upgrade MongoDB to 7.0.x:
```bash
# Backup first
mongodump --out /backup

# Upgrade MongoDB
apt-get update
apt-get install -y mongodb-org=7.0.x
```

2. Upgrade Ubuntu to 24.04 LTS:
```bash
do-release-upgrade
```

3. Implement patch management:
- Automated security updates
- Regular vulnerability scanning
- Patch testing environment
- Change management process

4. Consider managed services:
- MongoDB Atlas
- Cloud SQL
- Fully managed, auto-patched

**Wiz Detection**: Vulnerability scanning, version detection

---

### 5. Excessive Kubernetes RBAC Permissions

**Severity**: HIGH  
**Category**: Kubernetes Security  
**Resource**: todo-app ClusterRoleBinding

#### Description
Application pods are assigned the `cluster-admin` ClusterRole, granting full administrative access to the entire Kubernetes cluster.

#### Evidence
```yaml
# helm/todo-app/templates/clusterrolebinding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: todo-app-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin  # OVERLY PERMISSIVE
subjects:
- kind: ServiceAccount
  name: todo-app-sa
  namespace: default
```

#### Permissions Granted
The `cluster-admin` role grants:
- Create/delete/modify any resource in any namespace
- Read secrets across all namespaces
- Create new service accounts
- Modify RBAC policies
- Access to control plane

#### Business Impact
- **Container Breakout**: Compromised container = compromised cluster
- **Multi-Tenant Risk**: Can access other applications' data
- **Crypto Mining**: Can deploy mining workloads
- **Data Exfiltration**: Access to all secrets
- **Persistent Access**: Can create backdoor accounts

#### Attack Scenarios
1. **Application Vulnerability**: SQLi or RCE in todo app
2. **Privilege Abuse**: Use kubectl from within container
3. **Secret Theft**: Read all Kubernetes secrets
4. **Workload Deployment**: Deploy malicious containers
5. **RBAC Manipulation**: Create new admin accounts

#### Example Attack
```bash
# From within compromised pod
kubectl get secrets --all-namespaces
kubectl create sa backdoor
kubectl create clusterrolebinding backdoor --clusterrole=cluster-admin --serviceaccount=default:backdoor
```

#### Required Permissions
The todo app only needs:
- Read own ConfigMap
- Read own Secret
- No cross-namespace access

#### Remediation
**Priority**: HIGH

**Recommended Actions**:
1. Remove cluster-admin binding
2. Create minimal Role:
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: todo-app-role
  namespace: default
rules:
- apiGroups: [""]
  resources: ["configmaps", "secrets"]
  resourceNames: ["todo-app-secrets"]
  verbs: ["get"]
```

3. Implement Pod Security Standards
4. Use Network Policies to limit pod-to-pod communication
5. Enable Kubernetes audit logging
6. Regular RBAC reviews

**Wiz Detection**: K8s RBAC analysis, excessive permissions detection

---

### 6. Database in Public Subnet

**Severity**: HIGH  
**Category**: Network Architecture  
**Resource**: MongoDB VM

#### Description
The MongoDB VM is deployed in a public subnet with an external IP address, unnecessarily exposing it to the internet.

#### Evidence
```hcl
# terraform/vm.tf
network_interface {
  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.public_subnet.name
  
  access_config {
    nat_ip = google_compute_address.mongodb_static_ip.address
  }
}
```

#### Business Impact
- **Increased Attack Surface**: Direct internet exposure
- **DDoS Risk**: Can be targeted by distributed attacks
- **Scanning Exposure**: Visible to Shodan, Censys
- **Compliance**: Violates defense-in-depth principles

#### Remediation
**Priority**: MEDIUM

**Recommended Actions**:
1. Move to private subnet
2. Remove external IP
3. Use Cloud SQL (fully managed)
4. Implement Private Service Connect
5. Use Cloud VPN or Cloud Interconnect for remote access

**Wiz Detection**: Network topology analysis, internet-facing resources

---

## Additional Findings

### Medium Severity

#### 7. No Network Policies
- **Issue**: Kubernetes cluster has no NetworkPolicies
- **Impact**: Unrestricted pod-to-pod communication
- **Remediation**: Implement default-deny policies

#### 8. Unencrypted Backups
- **Issue**: Backups not encrypted at rest
- **Impact**: Data exposure if physical media compromised
- **Remediation**: Enable CMEK, client-side encryption

#### 9. No Secrets Management
- **Issue**: Credentials in environment variables
- **Impact**: Exposed in process listings, logs
- **Remediation**: Use Secret Manager, Sealed Secrets

#### 10. Missing Audit Logging
- **Issue**: Incomplete audit trail
- **Impact**: Cannot detect/investigate incidents
- **Remediation**: Enable all audit logs, centralize in SIEM

---

## Compliance Impact

### PCI-DSS Violations
- 1.2.1: Firewall rules too permissive
- 2.2.1: Insecure configurations
- 6.2: Vulnerable software versions

### GDPR Violations
- Article 32: Inadequate security measures
- Article 25: Privacy by design failures

### SOC 2 Control Failures
- CC6.1: Logical access controls
- CC6.7: Infrastructure security

### CIS Benchmark Failures
- Multiple Level 1 and Level 2 controls

---

## Detection Methods

### How Wiz Detects These Issues

1. **Agentless Scanning**: Analyzes cloud configurations without agents
2. **Cloud Security Graph**: Maps relationships between resources
3. **Policy Engine**: Applies security policies and compliance frameworks
4. **Vulnerability Database**: CVE matching for outdated software
5. **Runtime Detection**: Identifies live threats
6. **Kubernetes Security**: K8s-specific security analysis

### Wiz Unique Capabilities

- **Toxic Combinations**: Identifies issues that become critical when combined
- **Attack Path Analysis**: Shows how attacker could chain vulnerabilities
- **Context-Aware Prioritization**: Considers actual risk, not just severity
- **Remediation Guidance**: Provides specific fix instructions

---

## Remediation Roadmap

### Immediate (Day 1)
1. Restrict SSH to corporate IP ranges
2. Remove public access from GCS bucket
3. Rotate all credentials
4. Review audit logs for suspicious activity

### Short-term (Week 1)
1. Remove compute.admin IAM role
2. Replace cluster-admin with minimal RBAC
3. Enable all audit logging
4. Implement monitoring alerts

### Medium-term (Month 1)
1. Upgrade MongoDB to 7.0.x
2. Upgrade Ubuntu to 24.04
3. Move database to private subnet
4. Implement Network Policies
5. Set up automated vulnerability scanning

### Long-term (Quarter 1)
1. Migrate to Cloud SQL
2. Implement zero-trust architecture
3. Full compliance audit (SOC 2, ISO 27001)
4. Security training for development team
5. Implement security-as-code practices

---

## Conclusion

This exercise demonstrates how seemingly small misconfigurations can create significant security risks. While these issues were intentionally introduced for educational purposes, they represent real vulnerabilities found in production environments every day.

A cloud security platform like Wiz provides:
- **Visibility**: Complete inventory of cloud resources
- **Detection**: Automated identification of misconfigurations
- **Prioritization**: Focus on issues that matter most
- **Remediation**: Actionable guidance for fixing issues
- **Prevention**: Integration into CI/CD to prevent new issues

The key takeaway is that cloud security requires:
1. Defense in depth
2. Principle of least privilege
3. Continuous monitoring
4. Regular patching
5. Security automation
6. Comprehensive visibility

Would you like me to expand on any particular finding or add additional analysis?
