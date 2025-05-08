variable "project_id" {
  description = "Project id."
  type        = string
}

variable "region" {
  description = "GCP region."
  type        = string
}

variable "zone" {
  description = "GCP zone."
  type        = string
}

resource "google_compute_network" "default" {
  name   = "default"
  project = var.project_id
}

resource "google_compute_firewall" "default" {
  name    = "ssh-firewall-rule"
  network = google_compute_network.default.name
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags = ["ssh"]
}

resource "google_compute_address" "default" {
  name   = "my-test-static-ip-address"
  region = var.region
  project = var.project_id
}

resource "google_compute_instance" "default" {
  name         = "sftp-server"
  machine_type = "n2-standard-2"
  zone         = var.zone
  project      = var.project_id

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size = "100"
    }
  }

  network_interface {
    network = resource.google_compute_network.default.name

    access_config {
      nat_ip = google_compute_address.default.address
    }
  }

  tags = ["ssh"]

  metadata = {
    startup-script-url = "https://raw.githubusercontent.com/tyayers/sftp-api-integration-demo/main/scripts/debian_sftp_install.sh"
  }
}

output "ip" {
  value = google_compute_instance.default.network_interface.0.access_config.0.nat_ip
}