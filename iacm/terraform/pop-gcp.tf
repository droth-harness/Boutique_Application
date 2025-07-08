// Providers
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

}

provider "google" {
  project = var.project_id
  region  = var.region
  # Add a set of required labels to all resources created by this provider
  default_labels = {
    # Required values for Harness SEs
    env     = var.cluster_name
    purpose = var.purpose
    owner   = var.owner
  }
}

// Resources
// VPC
resource "google_compute_network" "vpc" {
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = "false"
}

// Subnet
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.cluster_name}-subnet"
  region        = var.region
  network       = google_compute_network.vpc.name
  ip_cidr_range = "10.10.0.0/24"
}

// GCE Linux VM
resource "google_compute_instance" "hce_linux" {
  name         = "hce-linux"
  machine_type = var.gce_machine_type
  zone         = "${var.region}-c"

  boot_disk {
    auto_delete = true
    device_name = "hce-linux"

    initialize_params {
      image = "projects/debian-cloud/global/images/debian-12-bookworm-v20241009"
      size  = 10
      type  = "pd-balanced"
    }

    mode = "READ_WRITE"
  }

  metadata = {
    enable-oslogin = "true"
  }

  network_interface {
    stack_type = "IPV4_ONLY"
    subnetwork = google_compute_subnetwork.subnet.name

    access_config {
      network_tier = "STANDARD"
    }
  }

  tags = ["http-server", "https-server"]

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    preemptible         = false
    provisioning_model  = "STANDARD"
  }

  service_account {
    email  = "980596850008-compute@developer.gserviceaccount.com"
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  labels = {
    env     = "hce-linux"
    purpose = var.purpose
    owner   = var.owner
  }
}

// GCE Windows VM
resource "google_compute_instance" "hce_windows" {
  name         = "hce-windows"
  machine_type = var.gce_machine_type
  zone         = "${var.region}-c"

  boot_disk {
    auto_delete = true
    device_name = "hce-windows"

    initialize_params {
      image = "projects/windows-cloud/global/images/windows-server-2022-dc-core-v20241010"
      size  = 40
      type  = "pd-balanced"
    }

    mode = "READ_WRITE"
  }

  metadata = {
    enable-oslogin = "true"
  }

  network_interface {
    stack_type = "IPV4_ONLY"
    subnetwork = google_compute_subnetwork.subnet.name

    access_config {
      network_tier = "STANDARD"
    }
  }

  tags = ["se-demo-rdp-access"]

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    preemptible         = false
    provisioning_model  = "STANDARD"
  }

  service_account {
    email  = "980596850008-compute@developer.gserviceaccount.com"
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  labels = {
    env     = "hce-windows"
    purpose = var.purpose
    owner   = var.owner
  }
}

// GKE Cluster
resource "google_container_cluster" "primary" {
  name     = "${var.cluster_name}-gke"
  location = var.region

  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name

  resource_labels = {
    env     = var.cluster_name
    purpose = var.purpose
    owner   = var.owner
  }

  addons_config {
    gcp_filestore_csi_driver_config {
      enabled = true
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }
  deletion_protection = false
}

// GKE Node Pool
resource "google_container_node_pool" "primary_nodes" {
  name     = google_container_cluster.primary.name
  cluster  = google_container_cluster.primary.name

  node_count = var.gke_num_nodes

  node_config {
    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]

    labels = {
      env     = var.cluster_name
      purpose = var.purpose
    }

    resource_labels = {
      env     = var.cluster_name
      purpose = var.purpose
      owner   = var.owner
    }

    machine_type = var.vm_machine_type
    tags         = ["gke-node", "${var.cluster_name}-gke"]

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  management {
    auto_upgrade = true
  }
}

// Variables
variable "gke_num_nodes" {
  default     = 2
  description = "Number of nodes for the GKE cluster"
}

variable "project_id" {
  description = "Google Cloud Platform Project ID"
}

variable "region" {
  description = "Google Cloud Region"
}

variable "cluster_name" {
  description = "Intended Name for the GKE cluster"
}

variable "vm_machine_type" {
  description = "GKE node machine type"
}

variable "gce_machine_type" {
  description = "GCE VM machine type"
}

variable "purpose" {
  description = "purpose of the cluster, e.g. pov, sandbox, smp, demo"
  validation {
    # purpose can't contain periods
    condition     = var.purpose != null && can(regex("^[^\\.]+$", var.purpose))
    error_message = "owner cannot contain periods"
  }
}

variable "owner" {
  description = "Sales or Implementation Engineer who owns this cluster e.g. nicacton"
  validation {
    # owner can't contain periods
    condition     = var.owner != null && can(regex("^[^\\.]+$", var.owner))
    error_message = "owner cannot contain periods"
  }
}

// Outputs
output "region" {
  value       = var.region
  description = "GCloud Region"
}

output "project_id" {
  value       = var.project_id
  description = "GCloud Project ID"
}

output "kubernetes_cluster_name" {
  value       = google_container_cluster.primary.name
  description = "GKE Cluster Name"
}

output "kubernetes_cluster_host" {
  value       = google_container_cluster.primary.endpoint
  description = "GKE Cluster Host"
}

output "gcloud_kubeconfig_command" {
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region ${google_container_cluster.primary.location} --project ${var.project_id}"
  description = "Command to create kubeconfig and connect to the GKE cluster"
}
