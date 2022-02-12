#creating instance with custom network and attaching persistent disk and also desired state to start or stop the instance
resource "google_compute_instance" "instance1" {
  count=3
  name         = "instance-${count.index+1}"
  zone         = "us-central1-a"
  machine_type = "n1-standard-1"
  boot_disk {
    initialize_params {
     image ="debian-cloud/debian-9"
    }
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
  attached_disk {
    source=google_compute_disk.persistent.self_link
  }
  #installing apache server
  metadata_startup_script = "sudo apt-get update && sudo apt-get install apache2 -y && echo '<!doctype html><html><body><h1>Apache is running</h1></body></html>' | sudo tee /var/www/html/index.html"

    #Apply the firewall rule to allow external IPs to access this instance
    tags = ["http-server"]
}
/*
#creating custom image with source as a disk
resource "google_compute_image" "custom-image" {
  name = "customimage"
  source_disk="https://www.googleapis.com/compute/v1projects/projectvpcpoc-2/zones/us-central1-a/disks/instance1"
}*/