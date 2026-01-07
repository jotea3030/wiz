# ============================================
# Terraform Variables
# ============================================

# Core Configuration
variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP Zone"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Environment name (e.g., wiz-preprod, wiz-prod)"
  type        = string
}

# ============================================
# Security Configuration Variables
# ============================================

variable "enable_ssh_from_internet" {
  description = "Allow SSH from 0.0.0.0/0 (VULNERABLE if true)"
  type        = bool
  default     = false
}

variable "enable_public_gcs_bucket" {
  description = "Make GCS bucket publicly readable (VULNERABLE if true)"
  type        = bool
  default     = false
}

variable "vm_iam_role_overpermissive" {
  description = "Grant compute.admin to VM (VULNERABLE if true, minimal permissions if false)"
  type        = bool
  default     = false
}

variable "use_outdated_mongodb" {
  description = "Use MongoDB 4.4 on Ubuntu 22.04 (VULNERABLE if true, use 7.0+ on Ubuntu 24.04 if false)"
  type        = bool
  default     = false
}

variable "enable_k8s_cluster_admin" {
  description = "Grant cluster-admin to pods (VULNERABLE if true, limited RBAC if false)"
  type        = bool
  default     = false
}

variable "mongodb_in_public_subnet" {
  description = "Deploy MongoDB in public subnet with external IP (VULNERABLE if true)"
  type        = bool
  default     = false
}

variable "ssh_allowed_cidr_ranges" {
  description = "CIDR ranges allowed for SSH access (use 0.0.0.0/0 for vulnerable setup)"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

# ============================================
# Resource Configuration
# ============================================

variable "gke_node_count" {
  description = "Number of nodes in GKE cluster"
  type        = number
  default     = 1
}

variable "gke_machine_type" {
  description = "Machine type for GKE nodes"
  type        = string
  default     = "e2-small"
}

variable "mongodb_vm_machine_type" {
  description = "Machine type for MongoDB VM"
  type        = string
  default     = "e2-micro"
}

# ============================================
# MongoDB Configuration
# ============================================

variable "mongodb_password" {
  description = "Password for MongoDB users"
  type        = string
  sensitive   = true
}

variable "mongodb_database" {
  description = "MongoDB database name"
  type        = string
  default     = "go-mongodb"
}

variable "mongodb_username" {
  description = "MongoDB application username"
  type        = string
  default     = "todoapp"
}

# ============================================
# Network Configuration
# ============================================

variable "vpc_cidr_public" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "vpc_cidr_private" {
  description = "CIDR block for private subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "pod_cidr" {
  description = "CIDR block for GKE pods"
  type        = string
  default     = "10.1.0.0/16"
}

variable "service_cidr" {
  description = "CIDR block for GKE services"
  type        = string
  default     = "10.2.0.0/16"
}
