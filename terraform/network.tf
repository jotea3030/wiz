# ============================================
# Network Configuration
# ============================================

# VPC Network
resource "google_compute_network" "vpc" {
  name                    = "${var.environment}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

# Public Subnet (for MongoDB if vulnerable config)
resource "google_compute_subnetwork" "public_subnet" {
  name          = "${var.environment}-public-subnet"
  ip_cidr_range = var.vpc_cidr_public
  region        = var.region
  network       = google_compute_network.vpc.id
  
  private_ip_google_access = true
  
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Private Subnet (for GKE and MongoDB if secure config)
resource "google_compute_subnetwork" "private_subnet" {
  name          = "${var.environment}-private-subnet"
  ip_cidr_range = var.vpc_cidr_private
  region        = var.region
  network       = google_compute_network.vpc.id
  
  # Secondary range for GKE pods
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pod_cidr
  }
  
  # Secondary range for GKE services
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.service_cidr
  }
  
  private_ip_google_access = true
  
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Cloud NAT for private subnet egress
resource "google_compute_router" "router" {
  name    = "${var.environment}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.environment}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  
  subnetwork {
    name                    = google_compute_subnetwork.private_subnet.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
  
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ============================================
# Firewall Rules
# ============================================

# SSH Access - CONDITIONAL: Vulnerable (0.0.0.0/0) or Secure (specific IPs)
resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.environment}-allow-ssh"
  network = google_compute_network.vpc.name
  
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  
  source_ranges = var.ssh_allowed_cidr_ranges
  target_tags   = ["mongodb-server"]
  
  priority = 1000
  
  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Internal SSH (always allowed for debugging)
resource "google_compute_firewall" "allow_ssh_internal" {
  name    = "${var.environment}-allow-ssh-internal"
  network = google_compute_network.vpc.name
  
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  
  source_ranges = [
    var.vpc_cidr_public,
    var.vpc_cidr_private,
    "35.235.240.0/20"  # IAP IP range for Cloud Console SSH
  ]
  
  priority = 900
}

# MongoDB Access - Only from GKE pods
resource "google_compute_firewall" "allow_mongodb" {
  name    = "${var.environment}-allow-mongodb"
  network = google_compute_network.vpc.name
  
  allow {
    protocol = "tcp"
    ports    = ["27017"]
  }
  
  source_ranges = [
    var.vpc_cidr_private,  # GKE nodes
    var.pod_cidr           # GKE pods
  ]
  target_tags = ["mongodb-server"]
  
  priority = 1000
}

# Health checks from GCP
resource "google_compute_firewall" "allow_health_checks" {
  name    = "${var.environment}-allow-health-checks"
  network = google_compute_network.vpc.name
  
  allow {
    protocol = "tcp"
  }
  
  source_ranges = [
    "35.191.0.0/16",
    "130.211.0.0/22"
  ]
  
  priority = 1000
}

# Internal communication
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.environment}-allow-internal"
  network = google_compute_network.vpc.name
  
  allow {
    protocol = "tcp"
  }
  
  allow {
    protocol = "udp"
  }
  
  allow {
    protocol = "icmp"
  }
  
  source_ranges = [
    var.vpc_cidr_public,
    var.vpc_cidr_private
  ]
  
  priority = 65534
}
