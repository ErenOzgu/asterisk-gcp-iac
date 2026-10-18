locals {
  tag        = "${var.name}-pbx"
  rtp_ranges = length(var.rtp_source_ranges) > 0 ? var.rtp_source_ranges : var.sip_source_ranges
  labels     = merge({ app = "asterisk", managed-by = "terraform" }, var.labels)
}

# ---------------------------------------------------------------- identity

# The VM gets its own service account with no roles at all: nothing running on
# it can call a Google API. (The default compute account is a project Editor.)
resource "google_service_account" "vm" {
  account_id   = "${var.name}-vm"
  display_name = "Asterisk VM (${var.name})"
}

# ---------------------------------------------------------------- network

resource "google_compute_network" "vpc" {
  name                    = "${var.name}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "pbx" {
  name                     = "${var.name}-subnet"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_address" "pbx" {
  name         = "${var.name}-ip"
  region       = var.region
  address_type = "EXTERNAL"
  labels       = local.labels
}

# ---------------------------------------------------------------- firewall
# Ingress is denied unless a rule below allows it. Every rule is scoped to the
# PBX's network tag and logs, so refused and accepted traffic is visible.

resource "google_compute_firewall" "sip" {
  name          = "${var.name}-allow-sip"
  description   = "SIP signalling (udp/5060) from the listed provider and office ranges only."
  network       = google_compute_network.vpc.name
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = var.sip_source_ranges
  target_tags   = [local.tag]

  allow {
    protocol = "udp"
    ports    = ["5060"]
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }

  lifecycle {
    precondition {
      condition     = var.allow_open_sip || !contains(var.sip_source_ranges, "0.0.0.0/0")
      error_message = "sip_source_ranges contains 0.0.0.0/0, which exposes SIP to the whole internet. List your provider's addresses instead, or set allow_open_sip = true if you really mean it."
    }
  }
}

resource "google_compute_firewall" "rtp" {
  name          = "${var.name}-allow-rtp"
  description   = "RTP media (udp/10000-20000) from the listed media ranges only."
  network       = google_compute_network.vpc.name
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = local.rtp_ranges
  target_tags   = [local.tag]

  allow {
    protocol = "udp"
    ports    = ["10000-20000"]
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }

  lifecycle {
    precondition {
      condition     = var.allow_open_sip || !contains(local.rtp_ranges, "0.0.0.0/0")
      error_message = "The RTP ranges contain 0.0.0.0/0, which exposes the media ports to the whole internet. List your provider's media addresses in rtp_source_ranges, or set allow_open_sip = true."
    }
  }
}

resource "google_compute_firewall" "ssh" {
  name          = "${var.name}-allow-ssh"
  description   = "SSH from the IAP range only. Logins are OS Login, not key files."
  network       = google_compute_network.vpc.name
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = var.ssh_source_ranges
  target_tags   = [local.tag]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }

  lifecycle {
    precondition {
      condition     = !contains(var.ssh_source_ranges, "0.0.0.0/0")
      error_message = "ssh_source_ranges contains 0.0.0.0/0. SSH is meant to be reached through IAP (35.235.240.0/20) or a fixed VPN range only."
    }
  }
}

resource "google_compute_firewall" "monitoring" {
  count = length(var.monitoring_source_ranges) > 0 ? 1 : 0

  name          = "${var.name}-allow-metrics"
  description   = "Prometheus scrape ports (node_exporter 9100, asterisk-exporter 9650) from the monitoring ranges only."
  network       = google_compute_network.vpc.name
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = var.monitoring_source_ranges
  target_tags   = [local.tag]

  allow {
    protocol = "tcp"
    ports    = ["9100", "9650"]
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# The implied deny rule does not log. This explicit one does.
resource "google_compute_firewall" "deny_all_ingress" {
  name          = "${var.name}-deny-all-ingress"
  description   = "Explicit deny-all that logs, because the implied deny rule does not."
  network       = google_compute_network.vpc.name
  direction     = "INGRESS"
  priority      = 65000
  source_ranges = ["0.0.0.0/0"]

  deny {
    protocol = "all"
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# ---------------------------------------------------------------- disk and VM

resource "google_compute_resource_policy" "snapshots" {
  name   = "${var.name}-daily-snapshots"
  region = var.region

  snapshot_schedule_policy {
    schedule {
      daily_schedule {
        days_in_cycle = 1
        start_time    = "03:00"
      }
    }

    retention_policy {
      max_retention_days    = var.snapshot_retention_days
      on_source_disk_delete = "KEEP_AUTO_SNAPSHOTS"
    }

    snapshot_properties {
      labels = local.labels
    }
  }
}

resource "google_compute_disk" "boot" {
  #checkov:skip=CKV_GCP_37:Google-managed encryption at rest is on by default. Customer-supplied keys would have to be typed in at every start and put the PBX's availability in the hands of the key custodian.
  name   = "${var.name}-boot"
  zone   = var.zone
  type   = "pd-balanced"
  size   = var.boot_disk_size_gb
  image  = var.image
  labels = local.labels
}

resource "google_compute_disk_resource_policy_attachment" "boot_snapshots" {
  name = google_compute_resource_policy.snapshots.name
  disk = google_compute_disk.boot.name
  zone = var.zone
}

resource "google_compute_instance" "pbx" {
  #checkov:skip=CKV_GCP_38:Same reasoning as the boot disk: Google-managed encryption at rest, no customer-supplied key.
  #checkov:skip=CKV_GCP_40:A SIP trunk needs a stable public address; the firewall only lets the configured provider ranges reach it.
  name                      = var.name
  zone                      = var.zone
  machine_type              = var.machine_type
  tags                      = [local.tag]
  labels                    = local.labels
  can_ip_forward            = false
  deletion_protection       = var.deletion_protection
  allow_stopping_for_update = true

  boot_disk {
    source      = google_compute_disk.boot.id
    auto_delete = false
  }

  network_interface {
    subnetwork = google_compute_subnetwork.pbx.id

    access_config {
      nat_ip = google_compute_address.pbx.address
    }
  }

  service_account {
    email  = google_service_account.vm.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }

  metadata = {
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "TRUE"
    serial-port-enable     = "FALSE"
  }
}

# ---------------------------------------------------------------- admin access
# SSH goes through IAP and OS Login: access is an IAM grant, not a key file on
# the VM. Reaching a VM that has a service account also needs serviceAccountUser.

resource "google_compute_instance_iam_member" "os_admin_login" {
  for_each = toset(var.admin_members)

  project       = var.project_id
  zone          = var.zone
  instance_name = google_compute_instance.pbx.name
  role          = "roles/compute.osAdminLogin"
  member        = each.value
}

resource "google_iap_tunnel_instance_iam_member" "tunnel" {
  for_each = toset(var.admin_members)

  project  = var.project_id
  zone     = var.zone
  instance = google_compute_instance.pbx.name
  role     = "roles/iap.tunnelResourceAccessor"
  member   = each.value
}

resource "google_service_account_iam_member" "act_as_vm" {
  for_each = toset(var.admin_members)

  service_account_id = google_service_account.vm.name
  role               = "roles/iam.serviceAccountUser"
  member             = each.value
}
