# Service account for MongoDB VM (OVERLY PERMISSIVE - INTENTIONAL VULNERABILITY)
resource "google_service_account" "mongodb_vm" {
  account_id   = "${var.environment}-mongodb-vm"
  display_name = "Service Account for MongoDB VM"
}

# VULNERABLE: Grant compute admin role (overly permissive)
resource "google_project_iam_member" "mongodb_vm_compute_admin" {
  project = var.project_id
  role    = "roles/compute.admin"
  member  = "serviceAccount:${google_service_account.mongodb_vm.email}"
}

# Allow storage access for backups
resource "google_project_iam_member" "mongodb_vm_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.mongodb_vm.email}"
}

# Allow logging
resource "google_project_iam_member" "mongodb_vm_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.mongodb_vm.email}"
}

# MongoDB VM instance
resource "google_compute_instance" "mongodb" {
  name         = "${var.environment}-mongodb-vm"
  machine_type = var.mongodb_vm_machine_type
  zone         = var.zone
  
# Use outdated Ubuntu (INTENTIONAL VULNERABILITY)
boot_disk {
  initialize_params {
    # Ubuntu 22.04 LTS (released April 2022, 2+ years old - meets requirement)
    image = "ubuntu-os-cloud/ubuntu-2204-lts"
    size  = 20
    type  = "pd-standard"
  }
}
  
network_interface {
    network    = google_compute_network.vpc.name
    subnetwork = google_compute_subnetwork.public_subnet.name
    
    # Assign external IP (VULNERABLE: Database in public subnet)
    access_config {
      nat_ip = google_compute_address.mongodb_static_ip.address
    }
  }
  
  # Service account with overly permissive roles
  service_account {
    email  = google_service_account.mongodb_vm.email
    scopes = ["cloud-platform"]
  }
  
  # Network tags for firewall rules
  tags = ["mongodb-server", "${var.environment}-mongodb"]
  
  # Metadata for startup script
  metadata = {
    enable-oslogin = "FALSE"
    startup-script = <<-EOT
#!/bin/bash
set -e

# Update system packages
export DEBIAN_FRONTEND=noninteractive
apt-get update

# Install MongoDB 4.4 (INTENTIONALLY OUTDATED - released July 2020)
wget -qO - https://www.mongodb.org/static/pgp/server-4.4.asc | apt-key add -
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/4.4 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-4.4.list
apt-get update
apt-get install -y mongodb-org=4.4.29 mongodb-org-server=4.4.29 mongodb-org-shell=4.4.29 mongodb-org-mongos=4.4.29 mongodb-org-tools=4.4.29

# Hold MongoDB package to prevent accidental upgrades
echo "mongodb-org hold" | dpkg --set-selections
echo "mongodb-org-server hold" | dpkg --set-selections

# Configure MongoDB to listen on all interfaces
cat > /etc/mongod.conf <<'MONGOEOF'
storage:
  dbPath: /var/lib/mongodb
  journal:
    enabled: true

systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log

net:
  port: 27017
  bindIp: 0.0.0.0

security:
  authorization: enabled

processManagement:
  timeZoneInfo: /usr/share/zoneinfo
MONGOEOF

# Start MongoDB
systemctl enable mongod
systemctl start mongod
sleep 5

# Create admin user
mongo <<ADMINEOF
use admin
db.createUser({
  user: "admin",
  pwd: "${var.mongodb_password}",
  roles: [
    { role: "userAdminAnyDatabase", db: "admin" },
    { role: "readWriteAnyDatabase", db: "admin" },
    { role: "dbAdminAnyDatabase", db: "admin" },
    { role: "clusterAdmin", db: "admin" }
  ]
})
ADMINEOF

# Create application database and user
mongo -u admin -p '${var.mongodb_password}' --authenticationDatabase admin <<APPEOF
use go-mongodb
db.createUser({
  user: "todoapp",
  pwd: "${var.mongodb_password}",
  roles: [
    { role: "readWrite", db: "go-mongodb" }
  ]
})
APPEOF

# Install backup script dependencies
apt-get install -y wget curl

# Create backup script
cat > /usr/local/bin/backup-mongodb.sh <<'BACKUPEOF'
#!/bin/bash
TIMESTAMP=$$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="/tmp/mongodb-backup-$$TIMESTAMP.gz"
BUCKET_NAME="${google_storage_bucket.mongodb_backups.name}"

# Run mongodump
mongodump \
  --host localhost \
  --port 27017 \
  --username admin \
  --password '${var.mongodb_password}' \
  --authenticationDatabase admin \
  --archive=$$BACKUP_FILE \
  --gzip

# Upload to GCS
gsutil cp $$BACKUP_FILE gs://$$BUCKET_NAME/backup-$$TIMESTAMP.gz

# Clean up
rm -f $$BACKUP_FILE

echo "Backup completed: backup-$$TIMESTAMP.gz"
BACKUPEOF

chmod +x /usr/local/bin/backup-mongodb.sh

# Schedule daily backup at 2 AM
(crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/backup-mongodb.sh >> /var/log/mongodb-backup.log 2>&1") | crontab -

# Run initial backup
/usr/local/bin/backup-mongodb.sh >> /var/log/mongodb-backup.log 2>&1 &

echo "MongoDB setup complete!"
EOT
  }
  
  # Labels
  labels = {
    environment = var.environment
    role        = "database"
    managed_by  = "terraform"
  }
  
  # Enable deletion protection in production
  allow_stopping_for_update = true
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket.mongodb_backups
  ]
}

# Static external IP for MongoDB VM
resource "google_compute_address" "mongodb_static_ip" {
  name   = "${var.environment}-mongodb-ip"
  region = var.region
}
