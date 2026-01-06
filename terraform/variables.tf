variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "clgcporg10-158"
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone for resources"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "wiz-exercise"
}

variable "mongodb_password" {
  description = "MongoDB admin password"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
  default     = ""
}

variable "gke_node_count" {
  description = "Number of GKE nodes"
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
