terraform {
  required_providers {
    # https://github.com/hashicorp/terraform-provider-external
    external = {
      source  = "hashicorp/external"
      version = "2.3.3"
    }

    # https://registry.terraform.io/providers/Telmate/proxmox/latest
    proxmox = {
      source = "telmate/proxmox"
      version = "3.0.1-rc4"
    }
  }
}

data "external" "vault" {
  program = [
    "./bin/ansible-vault-proxy.sh",
    "terraform-vault2.json"
  ]
}

output "test1" {
    sensitive = false
    # https://support.hashicorp.com/hc/en-us/articles/5175257151891-How-to-output-sensitive-data-with-Terraform
    # value = nonsensitive(data.external.vault.result.terraform_token_id)
    value = nonsensitive(data.external.vault.result.ssh_key)
}

provider "proxmox" {
  pm_api_url = data.external.vault.result.api_url
  pm_api_token_id = data.external.vault.result.terraform_token_id
  pm_api_token_secret = data.external.vault.result.terraform_token_secret
  pm_tls_insecure = true

  pm_log_enable = true
  pm_log_file = "terraform-plugin-proxmox.log"
  pm_debug = true
  pm_log_levels = {
    _default = "debug"
    _capturelog = ""
 }
}

# Creates a proxmox_vm_qemu entity
# https://registry.terraform.io/providers/Telmate/proxmox/latest/docs/resources/vm_qemu
resource "proxmox_vm_qemu" "homelabvm" {
  name = "homelabvm${count.index + 1}" # count.index starts at 0
  count = 4 # Establishes how many instances will be created
  target_node = data.external.vault.result.proxmox_host

  # References our vars.tf file to plug in our template name
  clone = data.external.vault.result.template_name
  # Creates a full clone, rather than linked clone
  # https://pve.proxmox.com/wiki/VM_Templates_and_Clones
  full_clone  = "true"

  # VM Settings. `agent = 1` enables qemu-guest-agent
  agent = 1
  os_type = "cloud-init"
  ipconfig0 = "ip=dhcp"
  # ipconfig0 = "ip=<x.y.z>.${count.index + 30}/24,gw=<gateway_ip_address>"
  # nameserver = "<w.x.y.z>"
  searchdomain = data.external.vault.result.resource_searchdomain
  cores = 4
  sockets = 2
  cpu = "host"
  memory = 16384 # bytes
  scsihw = "virtio-scsi-pci"
  bootdisk = "scsi0"
  bios = "ovmf"

  disks {
    scsi {
        scsi0{
            disk {
                # Enables thin-provisioning
                discard = true

                # Enables SSD emulation
                emulatessd = true

                # Name of the storage that is local to the host where the VM is being created.
                storage = data.external.vault.result.storage
                # "local-btrfs"

                size = "150G"
            }
        }
    }

    # slot = 0
    # size = "150G"
    # type = "scsi"
    # # Name of the storage that is local to the host where the VM is being created.
    # storage = "local-btrfs"
    # # Enables SSD emulation
    # ssd = 1
    # # Enables thin-provisioning
    # discard = "on"
  }

  network {
    model = "virtio"
    bridge = data.external.vault.result.nic_name
    # omit this tag if VLANs are not being utilized.
    #tag = var.vlan_num
  }

  # https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle
  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      network,
    ]
  }

  connection {
      host        = self.default_ipv4_address
      type        = "ssh"
      user        = data.external.vault.result.connection_user
      password    = data.external.vault.result.password
  }

  provisioner "remote-exec" {
    inline = [
      # add ansible user
      "echo ${data.external.vault.result.ansible_password} | sudo -S useradd -m ansible;",
      # load SSH key for ansible user on command machine (where Terraform commands are launched from)
      "sudo bash -c 'mkdir /home/ansible/.ssh/ && echo ${data.external.vault.result.ssh_key_ansible} >> /home/ansible/.ssh/authorized_keys';",
      # add ansible to sudoers file for passwordless operations
      # https://www.ibm.com/docs/en/storage-ceph/5?topic=installation-creating-ansible-user-sudo-access
      "sudo bash -c \"cat << EOF >/etc/sudoers.d/ansible\nansible ALL = (root) NOPASSWD:ALL\nEOF\";",
      "sudo chmod 0440 /etc/sudoers.d/ansible;",
      # establish Longhorn directory (774 -> owner r/w/x, group r/w/x, public r)
      # need 'x' permissions for user and group (https://askubuntu.com/questions/1393823/cannot-cd-into-directory-even-though-group-has-permissions)
      "sudo mkdir -p -m 774 /var/lib/longhorn;",
      "sudo chown ansible:ansible /var/lib/longhorn;",
      "echo Done!;"
    ]
  }

  # provisioner "local-exec" {
  #   command = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -u root -i '${self.ipv4_address},' --private-key ${var.pvt_key} -e 'pub_key=${var.pub_key}' apache-install.yml"
  # }
}
