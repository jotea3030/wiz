# VPC Network
resource "google_compute_network" "vpc" {
  name                    = "${var.environment}-vpc"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.required_apis]
}

# Public subnet for MongoDB VM (intentional misconfiguration)
resource "google_compute_subnetwork" "public_subnet" {
  name          = "${var.environment}-public-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
  
  # Enable flow logs for monitoring
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Private subnet for GKE cluster
resource "google_compute_subnetwork" "private_subnet" {
  name          = "${var.environment}-private-subnet"
  ip_cidr_range = "10.0.2.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
  
  # Secondary range for GKE pods
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.1.0.0/16"
  }
  
  # Secondary range for GKE services
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.2.0.0/16"
  }
  
  private_ip_google_access = true
  
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Cloud Router for NAT
resource "google_compute_router" "router" {
  name    = "${var.environment}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

# Cloud NAT for private subnet egress
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

# Firewall rule - Allow SSH from anywhere (INTENTIONAL VULNERABILITY)
resource "google_compute_firewall" "allow_ssh_public" {
  name    = "${var.environment}-allow-ssh-public"
  network = google_compute_network.vpc.name
  
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  
  # VULNERABLE: Open to entire internet
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["mongodb-server"]
  
  priority = 1000
}

# Firewall rule - Allow MongoDB from GKE subnet only
resource "google_compute_firewall" "allow_mongodb_from_gke" {
  name    = "${var.environment}-allow-mongodb-gke"
  network = google_compute_network.vpc.name
  
  allow {
    protocol = "tcp"
    ports    = ["27017"]
  }
  
  source_ranges = [
    google_compute_subnetwork.private_subnet.ip_cidr_range,
    google_compute_subnetwork.private_subnet.secondary_ip_range[0].ip_cidr_range
  ]
  target_tags = ["mongodb-server"]
}

# Firewall rule - Allow internal communication
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.environment}-allow-internal"
  network = google_compute_network.vpc.name
  
  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  
  allow {
    protocol = "icmp"
  }
  
  source_ranges = [
    google_compute_subnetwork.public_subnet.ip_cidr_range,
    google_compute_subnetwork.private_subnet.ip_cidr_range,
  ]
}

# Firewall rule - Allow health checks
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
  
  target_tags = ["gke-node"]
}
