# Provider
provider "google" {
  project = var.project
  region  = "us-west1"
  zone    = "us-west1-a"
}

locals {
  instance_type = "n2-standard-4"
}

data "google_compute_image" "debian_image" {
  project = "debian-cloud"
  family  = "debian-10"
}

resource "google_compute_network" "autogpt_vpc" {
  name                    = "autogpt-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "autogpt_public_subnet" {
  name          = "autogpt-public-subnet"
  network       = google_compute_network.autogpt_vpc.self_link
  ip_cidr_range = "10.0.1.0/24"
  region        = "us-west1"
}

resource "google_compute_firewall" "ssh_access" {
  name    = "ssh-access"
  network = google_compute_network.autogpt_vpc.self_link

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["${var.my_ip}/32"]
}

resource "tls_private_key" "key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "ssh_key" {
  filename = "linux-key-pair"
  content  = tls_private_key.key.private_key_pem
}

resource "google_compute_instance" "autogpt_server" {
  name         = "autogpt-server"
  machine_type = local.instance_type
  zone         = "us-west1-a"

  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian_image.self_link
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.autogpt_public_subnet.self_link

    access_config {
      // Ephemeral IP
    }
  }

  metadata = {
    ssh-keys = "autogpt-server:${tls_private_key.key.public_key_openssh}"
  }

  service_account {
    scopes = ["https://www.googleapis.com/auth/compute.readonly"]
  }

  tags = ["autogpt-server"]

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      host        = self.network_interface[0].access_config[0].nat_ip
      user        = "autogpt-server"
      private_key = file(local_file.ssh_key.filename)
    }

    inline = [
      "sudo apt-get update",
      "sudo apt-get upgrade -y",
      "sudo apt-get install -y docker.io git screen",
      "sudo systemctl start docker",
      "sudo systemctl enable docker",
      "sudo usermod -aG docker $(whoami)"
    ]
  }

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      host        = self.network_interface[0].access_config[0].nat_ip
      user        = "autogpt-server"
      private_key = file(local_file.ssh_key.filename)
    }

    inline = [
      "git clone -b stable https://github.com/Significant-Gravitas/Auto-GPT.git",
      "cd Auto-GPT/",
      "cp .env.template .env",
      "sed -i 's/OPENAI_API_KEY=your-openai-api-key/OPENAI_API_KEY=${var.openai_key}/g' .env",
      "docker build -t autogpt .",
      "echo alias start=\\\"docker run -it --env-file=.env -v $PWD/auto_gpt_workspace:/home/root/auto_gpt_workspace autogpt --continuous\\\" >> ~/.bash_profile"
    ]
  }
}

output "ssh_command" {
  value = "ssh -i ${local_file.ssh_key.filename} autogpt-server@${google_compute_instance.autogpt_server.network_interface.0.access_config.0.nat_ip}"
}