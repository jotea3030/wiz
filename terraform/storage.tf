# GCS bucket for MongoDB backups (INTENTIONALLY PUBLIC - VULNERABILITY)
resource "google_storage_bucket" "mongodb_backups" {
  name          = "wiz-mongodb-backups-${random_id.suffix.hex}"
  location      = var.region
  force_destroy = true
  
  # VULNERABLE: Public access enabled
  uniform_bucket_level_access = true
  
  # Lifecycle rules to manage costs
  lifecycle_rule {
    condition {
      age = 7
    }
    action {
      type = "Delete"
    }
  }
  
  # Versioning disabled to save costs
  versioning {
    enabled = false
  }
  
  # Labels
  labels = {
    environment = var.environment
    purpose     = "mongodb-backups"
    managed_by  = "terraform"
  }
  
  depends_on = [google_project_service.required_apis]
}

# VULNERABLE: Make bucket publicly readable
resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.mongodb_backups.name
  role   = "roles/storage.objectViewer"
  
  # CRITICAL VULNERABILITY: Public access to database backups
  member = "allUsers"
}

# Allow listing objects (VULNERABLE)
resource "google_storage_bucket_iam_member" "public_list" {
  bucket = google_storage_bucket.mongodb_backups.name
  role   = "roles/storage.legacyBucketReader"
  
  # CRITICAL VULNERABILITY: Public listing
  member = "allUsers"
}

# Container Registry for Docker images
resource "google_artifact_registry_repository" "docker_repo" {
  location      = var.region
  repository_id = "${var.environment}-docker-repo"
  description   = "Docker repository for todo application"
  format        = "DOCKER"
  
  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
  
  depends_on = [google_project_service.required_apis]
}
