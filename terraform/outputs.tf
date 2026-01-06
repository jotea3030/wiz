output "project_id" {
  description = "GCP Project ID"
  value       = var.project_id
}

output "region" {
  description = "GCP region"
  value       = var.region
}

output "gke_cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.primary.name
}

output "gke_cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "mongodb_vm_name" {
  description = "MongoDB VM instance name"
  value       = google_compute_instance.mongodb.name
}

output "mongodb_vm_external_ip" {
  description = "MongoDB VM external IP address"
  value       = google_compute_address.mongodb_static_ip.address
}

output "mongodb_vm_internal_ip" {
  description = "MongoDB VM internal IP address"
  value       = google_compute_instance.mongodb.network_interface[0].network_ip
}

output "mongodb_connection_string" {
  description = "MongoDB connection string (use internal IP from GKE)"
  value       = "mongodb://todoapp:${var.mongodb_password}@${google_compute_instance.mongodb.network_interface[0].network_ip}:27017/go-mongodb"
  sensitive   = true
}

output "backup_bucket_name" {
  description = "GCS bucket name for MongoDB backups"
  value       = google_storage_bucket.mongodb_backups.name
}

output "backup_bucket_url" {
  description = "GCS bucket URL (publicly accessible)"
  value       = "https://storage.googleapis.com/${google_storage_bucket.mongodb_backups.name}/"
}

output "docker_repository" {
  description = "Artifact Registry Docker repository"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker_repo.repository_id}"
}

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

output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region ${var.region} --project ${var.project_id}"
}

output "ssh_command" {
  description = "SSH command to connect to MongoDB VM"
  value       = "gcloud compute ssh ${google_compute_instance.mongodb.name} --zone ${var.zone} --project ${var.project_id}"
}

# Security Findings Summary
output "security_findings_summary" {
  description = "Summary of intentional security misconfigurations"
  value = {
    critical_findings = [
      "SSH exposed to 0.0.0.0/0 on MongoDB VM",
      "GCS bucket publicly readable (database backups exposed)",
      "MongoDB VM has compute.admin IAM role (overly permissive)",
      "Outdated Ubuntu 20.04 LTS on VM",
      "Outdated MongoDB 4.4.x (released 2020)",
      "Database VM in public subnet with external IP",
    ]
    high_findings = [
      "Kubernetes pods will be assigned cluster-admin role",
      "No network policies configured",
      "Broad firewall rules",
    ]
    recommendations = [
      "Restrict SSH access to specific IP ranges",
      "Remove public access from GCS bucket",
      "Apply principle of least privilege for IAM roles",
      "Upgrade to latest Ubuntu LTS and MongoDB versions",
      "Move database to private subnet without external IP",
      "Implement Kubernetes RBAC with minimal permissions",
      "Enable and configure network policies",
      "Implement least privilege firewall rules",
    ]
  }
}
