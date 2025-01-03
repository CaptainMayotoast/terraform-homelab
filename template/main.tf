terraform {
  required_providers {
    # used for leveraging Ansible vaults to store field values
    # https://github.com/hashicorp/terraform-provider-external
    external = {
      source  = "hashicorp/external"
      version = "2.3.3"
    }

    # https://registry.terraform.io/providers/bpg/proxmox/latest/docs
    proxmox = {
      source  = "bpg/proxmox"
      version = ">=0.69.0"
    }
  }
}

data "external" "vault" {
  program = [
    "../bin/ansible-vault-proxy.sh",
    "../terraform-vault.json"
  ]
}

# https://www.trfore.com/posts/using-terraform-to-create-proxmox-templates/

provider "proxmox" {
  endpoint  = data.external.vault.result.api_url
  api_token = data.external.vault.result.api_token
  insecure  = true

  # requires first "ssh-copy-id terraform@<pve-server>"
  ssh {
    agent       = true
    username    = data.external.vault.result.connection_user
    private_key = file(data.external.vault.result.connection_user_private_key)
  }
}

# Download a cloud image using BPG provider
resource "proxmox_virtual_environment_download_file" "image" {
  node_name    = data.external.vault.result.proxmox_host
  content_type = "iso"
  datastore_id = data.external.vault.result.storage
  # used for non-Ubuntu images
  # file_name          = ""
  url                = "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
  checksum           = "b63f266fa4bdf146dea5b0938fceac694cb3393688fb12a048ba2fc72e7bfe1b"
  checksum_algorithm = "sha256"
  overwrite          = false
}

# Create a custom cloud-init config using BPG provider
resource "proxmox_virtual_environment_file" "vendor_data" {
  node_name    = data.external.vault.result.proxmox_host
  datastore_id = data.external.vault.result.storage
  content_type = "snippets"

  source_raw {
    file_name = "vendor-data.yaml"
    data      = <<-EOF
      #cloud-config
      packages:
        - qemu-guest-agent
      package_update: true
      power_state:
        mode: reboot
        timeout: 30
      EOF
  }
}

# Create a VM template
resource "proxmox_virtual_environment_vm" "vm_template" {
  depends_on = [proxmox_virtual_environment_download_file.image]

  node_name = data.external.vault.result.proxmox_host
  vm_id     = "1212"
  name      = "ubuntu24"
  bios      = "seabios"
  machine   = "q35"
  started   = false # Don't boot the VM
  template  = true  # Turn the VM into a template

  agent {
    enabled = true
  }

  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 16384
    floating  = 16384
  }

  disk {
    file_id      = proxmox_virtual_environment_download_file.image.id
    datastore_id = "local-zfs"
    interface    = "scsi0"
    size         = 200
    file_format  = "raw"
    cache        = "writeback"
    iothread     = false
    ssd          = true
    discard      = "on"
  }

  network_device {
    # network device that the Proxmox server is accessible on
    # https://registry.terraform.io/providers/bpg/proxmox/latest/docs#node-ip-address-used-for-ssh-connection
    # it seems that whatever interface has a gateway set will be selected
    bridge = "vmbr0"
  }

  # cloud-init config
  initialization {
    interface           = "ide2"
    type                = "nocloud"
    vendor_data_file_id = "local:snippets/vendor-data.yaml"
    datastore_id        = "local-zfs"

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }
}
