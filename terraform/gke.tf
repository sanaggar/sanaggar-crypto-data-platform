# GKE Cluster (Google Kubernetes Engine)
resource "google_container_cluster" "primary" {
  name     = "crypto-platform-cluster"
  location = var.zone

  # We use a separate node pool, so we remove the default one
  remove_default_node_pool = true
  initial_node_count       = 1

  # Network configuration
  network    = "default"
  subnetwork = "default"

  # Disable expensive features to save costs
  logging_service    = "none"
  monitoring_service = "none"

  # Allow Terraform to destroy cluster
  deletion_protection = false
}

# Node Pool (the machines that run the pods)
resource "google_container_node_pool" "primary_nodes" {
  name       = "primary-node-pool"
  location   = var.zone
  cluster    = google_container_cluster.primary.name
  node_count = 2

  node_config {
    # Medium machine for better performance
    machine_type = "e2-medium"
    disk_size_gb = 30

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      env = "dev"
    }
  }
}

# Output to retrieve cluster info
output "cluster_name" {
  value = google_container_cluster.primary.name
}

output "cluster_endpoint" {
  value     = google_container_cluster.primary.endpoint
  sensitive = true
}
