# ============================================
# Terraform Outputs
# ============================================

output "project_id" {
  description = "GCP Project ID"
  value       = var.project_id
}

output "region" {
  description = "GCP Region"
  value       = var.region
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

# ============================================
# Network Outputs
# ============================================

output "vpc_network_name" {
  description = "VPC network name"
  value       = google_compute_network.vpc.name
}

output "public_subnet_name" {
  description = "Public subnet name"
  value       = google_compute_subnetwork.public_subnet.name
}

output "private_subnet_name" {
  description = "Private subnet name"
  value       = google_compute_subnetwork.private_subnet.name
}

# ============================================
# GKE Outputs
# ============================================

output "gke_cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.primary.name
}

output "gke_cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region ${var.region} --project ${var.project_id}"
}

# ============================================
# MongoDB VM Outputs
# ============================================

output "mongodb_vm_name" {
  description = "MongoDB VM instance name"
  value       = google_compute_instance.mongodb.name
}

output "mongodb_vm_internal_ip" {
  description = "MongoDB VM internal IP address"
  value       = google_compute_instance.mongodb.network_interface[0].network_ip
}

output "mongodb_vm_external_ip" {
  description = "MongoDB VM external IP address (if in public subnet)"
  value       = var.mongodb_in_public_subnet ? google_compute_address.mongodb_static_ip[0].address : "N/A - MongoDB in private subnet"
}

output "mongodb_connection_string" {
  description = "MongoDB connection string for application"
  value       = "mongodb://${var.mongodb_username}:${var.mongodb_password}@${google_compute_instance.mongodb.network_interface[0].network_ip}:27017/${var.mongodb_database}"
  sensitive   = true
}

output "ssh_command" {
  description = "SSH command to connect to MongoDB VM"
  value       = "gcloud compute ssh ${google_compute_instance.mongodb.name} --zone ${var.zone} --project ${var.project_id}"
}

# ============================================
# Storage Outputs
# ============================================

output "backup_bucket_name" {
  description = "GCS bucket name for MongoDB backups"
  value       = google_storage_bucket.mongodb_backups.name
}

output "backup_bucket_url" {
  description = "GCS bucket URL for MongoDB backups"
  value       = "https://storage.googleapis.com/${google_storage_bucket.mongodb_backups.name}/"
}

output "docker_repository" {
  description = "Artifact Registry Docker repository"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker_repo.repository_id}"
}

# ============================================
# Security Configuration Outputs
# ============================================

output "security_configuration" {
  description = "Current security configuration"
  value = {
    environment                 = var.environment
    ssh_from_internet           = var.enable_ssh_from_internet
    public_gcs_bucket           = var.enable_public_gcs_bucket
    vm_overpermissive_iam       = var.vm_iam_role_overpermissive
    outdated_mongodb            = var.use_outdated_mongodb
    k8s_cluster_admin           = var.enable_k8s_cluster_admin
    mongodb_in_public_subnet    = var.mongodb_in_public_subnet
    ssh_allowed_ranges          = var.ssh_allowed_cidr_ranges
  }
}

output "security_findings_summary" {
  description = "Summary of security findings based on configuration"
  value = {
    critical_findings = concat(
      var.enable_ssh_from_internet ? ["SSH exposed to 0.0.0.0/0 on MongoDB VM"] : [],
      var.enable_public_gcs_bucket ? ["GCS bucket publicly readable (database backups exposed)"] : [],
      var.vm_iam_role_overpermissive ? ["MongoDB VM has compute.admin IAM role (overly permissive)"] : [],
      var.use_outdated_mongodb ? ["Outdated MongoDB 4.4 on Ubuntu 22.04"] : [],
      var.mongodb_in_public_subnet ? ["Database VM in public subnet with external IP"] : []
    )
    high_findings = concat(
      var.enable_k8s_cluster_admin ? ["Kubernetes pods assigned cluster-admin role"] : [],
      ["No network policies configured"],
      var.enable_ssh_from_internet ? ["Broad firewall rules"] : []
    )
    recommendations = concat(
      var.enable_ssh_from_internet ? ["Restrict SSH access to specific IP ranges"] : [],
      var.enable_public_gcs_bucket ? ["Remove public access from GCS bucket"] : [],
      var.vm_iam_role_overpermissive ? ["Apply principle of least privilege for IAM roles"] : [],
      var.use_outdated_mongodb ? ["Upgrade to latest MongoDB and Ubuntu LTS versions"] : [],
      var.mongodb_in_public_subnet ? ["Move database to private subnet without external IP"] : [],
      var.enable_k8s_cluster_admin ? ["Implement Kubernetes RBAC with minimal permissions"] : [],
      ["Enable and configure network policies"],
      ["Implement least privilege firewall rules"]
    )
  }
}
