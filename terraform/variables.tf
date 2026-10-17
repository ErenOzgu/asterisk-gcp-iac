variable "project_id" {
  description = "ID of the GCP project that hosts the PBX."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid GCP project ID (6-30 characters, lower case letters, digits and hyphens)."
  }
}

variable "region" {
  description = "Region for the subnet, the static IP and the snapshot schedule."
  type        = string
  default     = "europe-west3"
}

variable "zone" {
  description = "Zone for the VM. Must be inside var.region."
  type        = string
  default     = "europe-west3-b"

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", var.zone))
    error_message = "zone must look like europe-west3-b."
  }
}

variable "name" {
  description = "Name prefix for every resource."
  type        = string
  default     = "asterisk"

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,28}[a-z0-9])?$", var.name))
    error_message = "name must start with a letter, use lower case letters, digits and hyphens, and be at most 30 characters."
  }
}

variable "machine_type" {
  description = "Machine type. An e2-small handles a few dozen concurrent G.711 calls without transcoding."
  type        = string
  default     = "e2-small"
}

variable "boot_disk_size_gb" {
  description = "Size of the boot disk in GB."
  type        = number
  default     = 20

  validation {
    condition     = var.boot_disk_size_gb >= 10
    error_message = "boot_disk_size_gb must be at least 10."
  }
}

variable "image" {
  description = "Boot image. The Ansible roles target Ubuntu 22.04 and 24.04."
  type        = string
  default     = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
}

variable "subnet_cidr" {
  description = "Primary range of the PBX subnet."
  type        = string
  default     = "10.10.0.0/24"

  validation {
    condition     = can(cidrnetmask(var.subnet_cidr))
    error_message = "subnet_cidr must be a valid IPv4 CIDR range."
  }
}

variable "sip_source_ranges" {
  description = "Who may reach SIP (udp/5060): your trunk provider's signalling addresses and your office or VPN. There is deliberately no default."
  type        = list(string)

  validation {
    condition     = length(var.sip_source_ranges) > 0 && alltrue([for c in var.sip_source_ranges : can(cidrnetmask(c))])
    error_message = "sip_source_ranges needs at least one valid IPv4 CIDR range."
  }
}

variable "rtp_source_ranges" {
  description = "Who may send RTP media (udp/10000-20000). Empty means the same ranges as SIP, which is right for most trunks; set it when your provider's media servers live elsewhere."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.rtp_source_ranges : can(cidrnetmask(c))])
    error_message = "rtp_source_ranges must contain valid IPv4 CIDR ranges."
  }
}

variable "allow_open_sip" {
  description = "Acknowledge that 0.0.0.0/0 in the SIP or RTP ranges exposes the PBX to the whole internet. Plans with such a range fail unless this is true."
  type        = bool
  default     = false
}

variable "ssh_source_ranges" {
  description = "Who may reach SSH. The default is Google's IAP range, so the VM is only reachable through an authenticated IAP tunnel."
  type        = list(string)
  default     = ["35.235.240.0/20"]

  validation {
    condition     = alltrue([for c in var.ssh_source_ranges : can(cidrnetmask(c))])
    error_message = "ssh_source_ranges must contain valid IPv4 CIDR ranges."
  }
}

variable "monitoring_source_ranges" {
  description = "Prometheus servers that may scrape node_exporter (9100) and asterisk-exporter (9650). Empty means the metrics ports stay closed."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.monitoring_source_ranges : can(cidrnetmask(c))])
    error_message = "monitoring_source_ranges must contain valid IPv4 CIDR ranges."
  }
}

variable "admin_members" {
  description = "IAM members (user:, group: or serviceAccount:) who may SSH in as administrators through IAP and OS Login."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for m in var.admin_members : can(regex("^(user|group|serviceAccount):", m))])
    error_message = "Every admin member must start with user:, group: or serviceAccount:."
  }
}

variable "snapshot_retention_days" {
  description = "How long the daily boot disk snapshots are kept."
  type        = number
  default     = 7

  validation {
    condition     = var.snapshot_retention_days >= 1
    error_message = "snapshot_retention_days must be at least 1."
  }
}

variable "deletion_protection" {
  description = "Refuse to delete the VM. Set to false before terraform destroy."
  type        = bool
  default     = true
}

variable "labels" {
  description = "Extra labels for the VM, the disk and the address."
  type        = map(string)
  default     = {}
}
