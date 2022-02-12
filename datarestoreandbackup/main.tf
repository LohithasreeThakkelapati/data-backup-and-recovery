#Creating  VPC network
resource "google_compute_network" "vpc_network" {
  name                    = "vpc-network"
  project                 = "projectvpcpoc-2"
  provider                = google
  auto_create_subnetworks = false
}
#creating backend subnet
resource "google_compute_subnetwork" "subnet1" {
  name          = "backend-subnet1"
  ip_cidr_range = "10.0.1.0/24"
  region        = "us-central1"
  network       = google_compute_network.vpc_network.id
}
 # allow all access from IAP and health check ranges
resource "google_compute_firewall" "fw-iap" {
  name          = "fw-allow-iap-hc"
  direction     = "INGRESS"
  network       = google_compute_network.vpc_network.id
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16", "35.235.240.0/20"]
  #target_tags = ["load-balanced-backend"]
  allow {
    protocol = "tcp"
  }
}
#to allow ssh 
resource "google_compute_firewall" "allow-ssh" {
  name          = "fw-allow-ssh"
  direction     = "INGRESS"
  network       = google_compute_network.vpc_network.id
  source_ranges = ["0.0.0.0/0"]
  #target= "apply to all"
  allow {
    protocol = "tcp"
  }
}
# allow http from proxy subnet to backends
resource "google_compute_firewall" "allow-http" {
  name          = "fw-allow-http"
  direction     = "INGRESS"
  network       = google_compute_network.vpc_network.id
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server"]
  allow {
    protocol = "tcp"
    ports    = ["80","22"]
  }
}
#creating disk
resource "google_compute_disk" "persistent" {
  name  = "test-disk"
  type  = "pd-ssd"
  zone  = "us-central1-a"
  size = 10

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
#adding scheduling policy to persistent disk
resource "google_compute_disk_resource_policy_attachment" "attachment" {
  name = google_compute_resource_policy.scheduled-policy.name
  disk = google_compute_disk.persistent.name
  zone = "us-central1-a"
}
#creating snapshot
resource "google_compute_snapshot" "snapshot" {
  name        = "my-snapshot"
  source_disk = google_compute_disk.persistent.id
  zone        = "us-central1-a"
  storage_locations = ["us-central1"]
}
/*
data "google_compute_instance" "instance1" {
  name = google_compute_instance.instance1.id
  desired_status="TERMINATED"
  depends_on = [
    google_compute_instance.instance1
  ]
  
}*/
# proxy-only subnet
resource "google_compute_subnetwork" "subnet2" {
  name          = "proxy-subnet1"
  ip_cidr_range = "10.0.0.0/24"
  region        = "us-central1"
  purpose       = "INTERNAL_HTTPS_LOAD_BALANCER"
  role          = "ACTIVE"
  network       = google_compute_network.vpc_network.id
}
# instance template --done
resource "google_compute_instance_template" "instance_template" {
  count = 1
  name         = "instance-template"
  machine_type = "n1-standard-1"
  tags         = ["http-server","allow-ssh"]
  can_ip_forward = "false"
 
    scheduling {
        automatic_restart = true
        on_host_maintenance = "MIGRATE"
    }
  network_interface {
    network    = google_compute_network.vpc_network.id
    subnetwork = google_compute_subnetwork.subnet1.id
    access_config {
      # add external ip to fetch packages
    }
  }
  disk {
    source_image = "debian-cloud/debian-9"
    auto_delete  = true
    boot         = true
    resource_policies = [google_compute_resource_policy.scheduled-policy.id]
  }
  disk {
    source       = google_compute_disk.persistent.name
    auto_delete  = false
    boot         = false
    resource_policies = [google_compute_resource_policy.scheduled-policy.id]
  }
  metadata = {
        foo = "bar"
    }
  metadata_startup_script = "sudo apt-get update && sudo apt-get install apache2 -y && echo '<!doctype html><html><body><h1>Apache is running</h1></body></html>' | sudo tee /var/www/html/index.html"
  lifecycle {
    create_before_destroy = false
  }
}
#health-check
/*
resource "google_compute_region_health_check" "default" {
  name     = "lb-hc"
  region   = "us-central1"
  http_health_check {
    port_specification = "USE_FIXED_PORT"
  }
}*/
# MIG
resource "google_compute_region_instance_group_manager" "mig" {
  target_size = 1
  name     = "mig1"
  region   = "us-central1"
  distribution_policy_zones = ["us-central1-a"]
  version{
  instance_template = "${google_compute_instance_template.instance_template[0].self_link}"
  }
  base_instance_name = "instance1"

  
  auto_healing_policies {
    health_check      = google_compute_health_check.health.id
    initial_delay_sec = 0
  }
}

# Auto Scale Policy < -- How many instances 
resource "google_compute_region_autoscaler" "autoscaler" {
    count = 1 
    name = "autoscaler"
    project = "projectvpcpoc-2"
    region = "us-central1"
    target = "${google_compute_region_instance_group_manager.mig.self_link}"
 
    autoscaling_policy  {
        max_replicas = 3
        min_replicas = 1
        cooldown_period = 60
        cpu_utilization {
            target = "0.6"
        }
    } 
}
# Health Check <-- Auto Scaling Policy (when to scale )
resource "google_compute_health_check" "health" {
    name  = "autohealing"
    
    check_interval_sec = 5
    timeout_sec = 5
    healthy_threshold = 2
    unhealthy_threshold = 2
 
    http_health_check {
        request_path = "/"
        port =  "80"
    }
}
 # backend service
resource "google_compute_region_backend_service" "default" {
  name                  = "ilb-backend-service"
  region                = "us-central1"
  protocol              = "HTTP"
  load_balancing_scheme = "INTERNAL_MANAGED"
  timeout_sec           = 10
  health_checks         = [google_compute_health_check.health.id]
  backend {
    group           = google_compute_region_instance_group_manager.mig.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}
# URL map
resource "google_compute_region_url_map" "default" {
  name            = "regional-url-map"
  region          = "us-central1"
  default_service = google_compute_region_backend_service.default.id
}
 
# HTTP target proxy
resource "google_compute_region_target_http_proxy" "default" {
  name     = "target-http-proxy"
  region   = "us-central1"
  url_map  = google_compute_region_url_map.default.id
}
# forwarding rule
resource "google_compute_forwarding_rule" "google_compute_forwarding_rule" {
  name                  = "forwarding-rule"
  region                = "us-central1"
  depends_on            = [google_compute_subnetwork.subnet2]
  ip_protocol           = "TCP"
  load_balancing_scheme = "INTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_region_target_http_proxy.default.id
  network               = google_compute_network.vpc_network.id
  subnetwork            = google_compute_subnetwork.subnet1.id
  network_tier          = "PREMIUM"
}