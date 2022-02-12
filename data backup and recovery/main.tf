provider "google" {
  credentials="${file("${var.path}/projectvpcpoc-2-46d57d3d5e65.json")}"
  project     = "projectvpcpoc-2"
  region      = "us-central1"
}
variable "path" {
    default="C:/Users/THLOHITH/Desktop/terraformdemo/demo1/analysis"
}
#Creating  VPC network
resource "google_compute_network" "vpc_network" {
  name                    = "vpc-network12"
  project                 = "projectvpcpoc-2"
  #provider                = google
  auto_create_subnetworks = false
}
#creating backend subnet
resource "google_compute_subnetwork" "subnet1" {
  name          = "backend-subnet145"
  ip_cidr_range = "10.0.1.0/24"
  region        = "us-central1"
  network       = google_compute_network.vpc_network.id
}
#to allow ssh 
resource "google_compute_firewall" "allow-ssh" {
  name          = "fw-allow-ssh"
  direction     = "INGRESS"
  network       = google_compute_network.vpc_network.id
  target_tags = ["http-server"]
  source_ranges = ["0.0.0.0/0"]
  #target= "apply to all"
  allow {
    protocol = "tcp"
    ports = ["22",80]
  }
}
resource "google_compute_instance" "instance1" {
  #count=3
  name         = "instance-runtime"
  zone         = "us-central1-a"
  machine_type = "n1-standard-1"
  boot_disk {
    initialize_params {
     image ="debian-cloud/debian-9"
     
    }
    auto_delete=false
  }
  scheduling {
        preemptible = false
        automatic_restart = false
    }
  network_interface {
    network = google_compute_network.vpc_network.id
    subnetwork = google_compute_subnetwork.subnet1.id
    access_config {
      # Allocate a one-to-one NAT IP to the instance
    }
  }
  #installing apache server
  metadata_startup_script = "sudo apt-get update && sudo apt-get install apache2 -y && echo '<!doctype html><html><body><h1>Apache is running</h1></body></html>' | sudo tee /var/www/html/index.html"

    #Apply the firewall rule to allow external IPs to access this instance
    tags = ["http-server"]
}

#snapshot scheduling
resource "google_compute_resource_policy" "scheduled-policy" {
  name   = "snapshot-schedule-policy"
  region = "us-central1"
  snapshot_schedule_policy {
    schedule {
      daily_schedule {
        days_in_cycle = 1
        start_time    = "04:00"
      }
    }
  retention_policy {
      max_retention_days    = 1
      on_source_disk_delete = "APPLY_RETENTION_POLICY"
    }
}
}
resource "google_compute_disk" "persistent" {
  name  = "test-disk"
  type  = "pd-ssd"
  zone  = "europe-west1-b"
  image="debian-cloud/debian-9"
  #snapshot = google_compute_image.custom_image.name
  size = 10
}
#adding scheduling policy to persistent disk
#adding scheduling policy to persistent disk
resource "google_compute_disk_resource_policy_attachment" "attachment" {
  name = google_compute_resource_policy.scheduled-policy.name
  disk = "instance-runtime"
  zone = "us-central1-a"
}
#creating snapshot
resource "google_compute_snapshot" "snapshot" {
  name        = "my-snapshot"
  source_disk = "https://www.googleapis.com/compute/v1projects/projectvpcpoc-2/zones/us-central1-a/disks/instance-runtime"
  zone        = "us-central1-a"
  storage_locations = ["us-central1"]
  depends_on = [
    google_compute_instance.instance1
  ]
}
