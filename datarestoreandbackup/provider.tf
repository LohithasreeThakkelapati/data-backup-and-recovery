provider "google" {
  credentials="${file("${var.path}/projectvpcpoc-2-46d57d3d5e65.json")}"
  project     = "projectvpcpoc-2"
  region      = "us-central1"
}