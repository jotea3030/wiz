# ============================================
# Cloud Storage Configuration
# ============================================

# Random suffix for bucket name
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# GCS Bucket for MongoDB backups
resource "google_storage_bucket" "mongodb_backups" {
  name          = "${var.environment}-mongodb-backups-${random_id.bucket_suffix.hex}"
  location      = var.region
  force_destroy = true
  
  uniform_bucket_level_access = true
  
  versioning {
    enabled = true
  }
  
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  lifecycle_rule {
    condition {
      age                   = 7
      num_newer_versions    = 3
    }
    action {
      type = "Delete"
    }
  }
  
  labels = {
    environment = var.environment
    purpose     = "mongodb-backups"
    managed_by  = "terraform"
  }
}

# CONDITIONAL: Public Read Access (VULNERABLE if enabled)
resource "google_storage_bucket_iam_member" "public_read" {
  count  = var.enable_public_gcs_bucket ? 1 : 0
  bucket = google_storage_bucket.mongodb_backups.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

resource "google_storage_bucket_iam_member" "public_list" {
  count  = var.enable_public_gcs_bucket ? 1 : 0
  bucket = google_storage_bucket.mongodb_backups.name
  role   = "roles/storage.legacyBucketReader"
  member = "allUsers"
}

# SECURE: Service account access (always enabled)
resource "google_storage_bucket_iam_member" "vm_backup_access" {
  bucket = google_storage_bucket.mongodb_backups.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.mongodb_vm.email}"
}

# Artifact Registry for Docker images
resource "google_artifact_registry_repository" "docker_repo" {
  location      = var.region
  repository_id = "${var.environment}-docker-repo"
  description   = "Docker repository for ${var.environment} environment"
  format        = "DOCKER"
  
  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}
