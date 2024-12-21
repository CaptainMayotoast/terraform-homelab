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
    "./bin/ansible-vault-proxy.sh",
    "terraform-vault.json"
  ]
}

# https://www.trfore.com/posts/using-terraform-to-create-proxmox-templates/

provider "proxmox" {
  endpoint  = data.external.vault.result.api_url
  api_token = data.external.vault.result.api_token
  #   username  = data.external.vault.result.connection_user
  #   password  = data.external.vault.result.connection_user_password
  insecure = true
  ssh {
    agent    = true
    username = data.external.vault.result.connection_user
    # password    = data.external.vault.result.connection_user_password
    private_key = data.external.vault.result.connection_user_private_key
  }
}

# Download a cloud image using BPG provider
resource "proxmox_virtual_environment_download_file" "image" {
  node_name    = data.external.vault.result.proxmox_host
  content_type = "iso"
  datastore_id = data.external.vault.result.storage
  # file_name          = "noble-server-cloudimg-amd64.img"
  url                = "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
  checksum           = "b63f266fa4bdf146dea5b0938fceac694cb3393688fb12a048ba2fc72e7bfe1b"
  checksum_algorithm = "sha256"
  overwrite          = false

  lifecycle {
    prevent_destroy = true
  }
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

  lifecycle {
    prevent_destroy = true
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
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 8192
    floating  = 8192
  }

  # # create an EFI disk when the bios is set to ovmf
  # dynamic "efi_disk" {
  #   for_each = (bios == "ovmf" ? [1] : [])
  #   content {
  #     datastore_id      = data.external.vault.result.storage
  #     file_format       = "raw"
  #     type              = "4m"
  #     pre_enrolled_keys = true
  #   }
  # }

  disk {
    file_id      = proxmox_virtual_environment_download_file.image.id
    datastore_id = "local-zfs"
    interface    = "scsi0"
    size         = 8
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

# # Create Multiple VMs
# module "vm_multiple_config" {
#   source = "github.com/CaptainMayotoast/terraform-bpg-proxmox//modules/vm-clone"

#   for_each = tomap({
#     "vm-example-01" = {
#       id           = 101
#       template     = 1212
#       datastore_id = "local-zfs"
#       vnic_bridge  = "vmbr0"
#       ci_password = "password1"
#     },
#     "vm-example-02" = {
#       id           = 102
#       template     = 1212
#       datastore_id = "local-zfs"
#       vnic_bridge  = "vmbr0"
#       ci_password = "password1"
#     },
#   })

#   node        = data.external.vault.result.proxmox_host # required
#   vm_id       = each.value.id                           # required
#   vm_name     = each.key                                # optional
#   template_id = each.value.template                     # required
#   #   bios        = "seabios"
#   #   machine     = "q35"
#   ci_user     = "aschwartz"
#   ci_ssh_key  = "~/.ssh/id_ed25519.pub" # optional, add SSH key to "default" user
#   #   efi_disk_storage = "local-zfs"'

#   #   disks {
#   #     disk_storage = "local-zfs"
#   #   }
# }

# output "id_multiple_vms" {
#   value = { for k, v in module.vm_multiple_config : k => v.id }
# }

# output "public_ipv4_multiple_vms" {
#   value = { for k, v in module.vm_multiple_config : k => flatten(v.public_ipv4) }
# }

# resource "proxmox_vm_qemu" "cloudinit-test" {
#     # https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle
#     lifecycle {
#         create_before_destroy = true
#         ignore_changes = [
#         network,
#         ]
#     }

#     connection {
#         host        = self.default_ipv4_address
#         type        = "ssh"
#         user        = data.external.vault.result.connection_user
#         password    = data.external.vault.result.connection_user_password
#     }

#     provisioner "remote-exec" {
#         inline = [
#         # add ansible user
#         "echo ${data.external.vault.result.ansible_user_password} | sudo -S useradd -m ${data.external.vault.result.ansible_user};",
#         # load SSH key for ansible user on command machine (where Terraform commands are launched from)
#         "sudo bash -c 'mkdir /home/ansible/.ssh/ && echo ${data.external.vault.result.ssh_key_ansible} >> /home/ansible/.ssh/authorized_keys';",
#         # add ansible to sudoers file for passwordless operations
#         # https://www.ibm.com/docs/en/storage-ceph/5?topic=installation-creating-ansible-user-sudo-access
#         "sudo bash -c \"cat << EOF >/etc/sudoers.d/ansible\nansible ALL = (root) NOPASSWD:ALL\nEOF\";",
#         "sudo chmod 0440 /etc/sudoers.d/ansible;",
#         # establish Longhorn directory (774 -> owner r/w/x, group r/w/x, public r)
#         # need 'x' permissions for user and group (https://askubuntu.com/questions/1393823/cannot-cd-into-directory-even-though-group-has-permissions)
#         "sudo mkdir -p -m 774 /var/lib/longhorn;",
#         "sudo chown ansible:ansible /var/lib/longhorn;",
#         "echo Done!;"
#         ]
#     }
# }
