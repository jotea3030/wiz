# ============================================
# MongoDB VM Configuration
# ============================================

# Service account for MongoDB VM
resource "google_service_account" "mongodb_vm" {
  account_id   = "${var.environment}-mongodb-vm"
  display_name = "Service Account for MongoDB VM (${var.environment})"
}

# CONDITIONAL IAM Role: Overpermissive (vulnerable) vs Least Privilege (secure)
resource "google_project_iam_member" "mongodb_vm_role" {
  project = var.project_id
  role    = var.vm_iam_role_overpermissive ? "roles/compute.admin" : "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.mongodb_vm.email}"
}

# Storage access for backups (always needed)
resource "google_project_iam_member" "mongodb_vm_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.mongodb_vm.email}"
}

# Monitoring access (secure environments)
resource "google_project_iam_member" "mongodb_vm_monitoring" {
  count   = var.vm_iam_role_overpermissive ? 0 : 1
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.mongodb_vm.email}"
}

# Static external IP - only if MongoDB in public subnet
resource "google_compute_address" "mongodb_static_ip" {
  count  = var.mongodb_in_public_subnet ? 1 : 0
  name   = "${var.environment}-mongodb-ip"
  region = var.region
}

# MongoDB VM instance
resource "google_compute_instance" "mongodb" {
  name         = "${var.environment}-mongodb-vm"
  machine_type = var.mongodb_vm_machine_type
  zone         = var.zone
  
  # CONDITIONAL: Boot disk image based on MongoDB version
  boot_disk {
    initialize_params {
      # Vulnerable: Ubuntu 22.04 (outdated)
      # Secure: Ubuntu 24.04 LTS (current)
      image = var.use_outdated_mongodb ? "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts" : "projects/ubuntu-os-cloud/global/images/family/ubuntu-2404-lts-amd64"
      size  = 20
      type  = "pd-standard"
    }
  }
  
  # CONDITIONAL: Network configuration based on subnet placement
  network_interface {
    network    = google_compute_network.vpc.name
    subnetwork = var.mongodb_in_public_subnet ? google_compute_subnetwork.public_subnet.name : google_compute_subnetwork.private_subnet.name
    
    # External IP only if in public subnet
    dynamic "access_config" {
      for_each = var.mongodb_in_public_subnet ? [1] : []
      content {
        nat_ip = google_compute_address.mongodb_static_ip[0].address
      }
    }
  }
  
  service_account {
    email  = google_service_account.mongodb_vm.email
    scopes = ["cloud-platform"]
  }
  
  tags = ["mongodb-server", "${var.environment}-mongodb"]
  
  # CONDITIONAL: Startup script based on MongoDB version
  metadata = {
    enable-oslogin = "FALSE"
    startup-script = var.use_outdated_mongodb ? local.mongodb_startup_script_outdated : local.mongodb_startup_script_current
  }
  
  labels = {
    environment = var.environment
    role        = "database"
    managed_by  = "terraform"
  }
  
  allow_stopping_for_update = true
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket.mongodb_backups
  ]
}

# ============================================
# Startup Scripts (as locals)
# ============================================

locals {
  # Startup script for OUTDATED MongoDB 4.4 on Ubuntu 22.04 (VULNERABLE)
  mongodb_startup_script_outdated = <<-EOT
#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive
apt-get update

# Install libssl1.1 (required for MongoDB 4.4 on Ubuntu 22.04)
wget http://archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2_amd64.deb
dpkg -i libssl1.1_1.1.1f-1ubuntu2_amd64.deb

# Install MongoDB 4.4 (OUTDATED - intentional vulnerability)
wget -qO - https://www.mongodb.org/static/pgp/server-4.4.asc | apt-key add -
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/4.4 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-4.4.list
apt-get update
apt-get install -y mongodb-org=4.4.29 mongodb-org-server=4.4.29 mongodb-org-shell=4.4.29 mongodb-org-mongos=4.4.29 mongodb-org-tools=4.4.29

echo "mongodb-org hold" | dpkg --set-selections
echo "mongodb-org-server hold" | dpkg --set-selections

# Configure MongoDB
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

# Create application user
mongo -u admin -p '${var.mongodb_password}' --authenticationDatabase admin <<APPEOF
use ${var.mongodb_database}
db.createUser({
  user: "${var.mongodb_username}",
  pwd: "${var.mongodb_password}",
  roles: [
    { role: "readWrite", db: "${var.mongodb_database}" }
  ]
})
APPEOF

# Install backup dependencies
apt-get install -y wget curl

# Create backup script
cat > /usr/local/bin/backup-mongodb.sh <<'BACKUPEOF'
#!/bin/bash
TIMESTAMP=$$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="/tmp/mongodb-backup-$$TIMESTAMP.gz"
BUCKET_NAME="${google_storage_bucket.mongodb_backups.name}"

mongodump \
  --host localhost \
  --port 27017 \
  --username admin \
  --password '${var.mongodb_password}' \
  --authenticationDatabase admin \
  --archive=$$BACKUP_FILE \
  --gzip

gsutil cp $$BACKUP_FILE gs://$$BUCKET_NAME/backup-$$TIMESTAMP.gz
rm -f $$BACKUP_FILE

echo "Backup completed: backup-$$TIMESTAMP.gz"
BACKUPEOF

chmod +x /usr/local/bin/backup-mongodb.sh
(crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/backup-mongodb.sh >> /var/log/mongodb-backup.log 2>&1") | crontab -
/usr/local/bin/backup-mongodb.sh >> /var/log/mongodb-backup.log 2>&1 &

echo "MongoDB 4.4 setup complete (OUTDATED VERSION)"
EOT

  # Startup script for CURRENT MongoDB 7.0 on Ubuntu 24.04 (SECURE)
  mongodb_startup_script_current = <<-EOT
#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive
apt-get update

# Install MongoDB 7.0 (CURRENT VERSION)
curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu noble/mongodb-org/7.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-7.0.list
apt-get update
apt-get install -y mongodb-org

# Configure MongoDB with enhanced security
cat > /etc/mongod.conf <<'MONGOEOF'
storage:
  dbPath: /var/lib/mongodb
  journal:
    enabled: true
  wiredTiger:
    engineConfig:
      cacheSizeGB: 0.5

systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log
  logRotate: reopen

net:
  port: 27017
  bindIp: 0.0.0.0
  maxIncomingConnections: 100

security:
  authorization: enabled

processManagement:
  timeZoneInfo: /usr/share/zoneinfo

setParameter:
  enableLocalhostAuthBypass: false
MONGOEOF

systemctl enable mongod
systemctl start mongod
sleep 5

# Create admin user
mongosh <<ADMINEOF
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

# Create application user
mongosh -u admin -p '${var.mongodb_password}' --authenticationDatabase admin <<APPEOF
use ${var.mongodb_database}
db.createUser({
  user: "${var.mongodb_username}",
  pwd: "${var.mongodb_password}",
  roles: [
    { role: "readWrite", db: "${var.mongodb_database}" }
  ]
})
APPEOF

# Install backup dependencies
apt-get install -y wget curl

# Create backup script
cat > /usr/local/bin/backup-mongodb.sh <<'BACKUPEOF'
#!/bin/bash
TIMESTAMP=$$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="/tmp/mongodb-backup-$$TIMESTAMP.gz"
BUCKET_NAME="${google_storage_bucket.mongodb_backups.name}"

mongodump \
  --host localhost \
  --port 27017 \
  --username admin \
  --password '${var.mongodb_password}' \
  --authenticationDatabase admin \
  --archive=$$BACKUP_FILE \
  --gzip

gsutil cp $$BACKUP_FILE gs://$$BUCKET_NAME/backup-$$TIMESTAMP.gz
rm -f $$BACKUP_FILE

echo "Backup completed: backup-$$TIMESTAMP.gz"
BACKUPEOF

chmod +x /usr/local/bin/backup-mongodb.sh
(crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/backup-mongodb.sh >> /var/log/mongodb-backup.log 2>&1") | crontab -
/usr/local/bin/backup-mongodb.sh >> /var/log/mongodb-backup.log 2>&1 &

echo "MongoDB 7.0 setup complete (CURRENT VERSION)"
EOT
}
