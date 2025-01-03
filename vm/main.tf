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

# Create Multiple VMs
module "vm_multiple_config" {
  source = "github.com/CaptainMayotoast/terraform-bpg-proxmox//modules/vm-clone"

  for_each = tomap({
    "homelab-k8s-vm0" = {
      id           = 201
      template     = data.external.vault.result.template_id
      datastore_id = "local-zfs"
      vnic_bridge  = data.external.vault.result.nic_name
      ci_password  = data.external.vault.result.ci_password
    },
    "homelab-k8s-vm1" = {
      id           = 202
      template     = data.external.vault.result.template_id
      datastore_id = "local-zfs"
      vnic_bridge  = data.external.vault.result.nic_name
      ci_password  = data.external.vault.result.ci_password

    },
    "homelab-k8s-vm2" = {
      id           = 203
      template     = data.external.vault.result.template_id
      datastore_id = "local-zfs"
      vnic_bridge  = data.external.vault.result.nic_name
      ci_password  = data.external.vault.result.ci_password

    },
    "homelab-k8s-vm3" = {
      id           = 204
      template     = data.external.vault.result.template_id
      datastore_id = "local-zfs"                         # not sure if this is effectual - check
      vnic_bridge  = data.external.vault.result.nic_name # not sure if this is effectual - check
      ci_password  = data.external.vault.result.ci_password
    },
  })

  disks = [
    {
      disk_interface = "scsi0", # default cloud image boot drive
      disk_size      = 200
    }
  ]

  node         = data.external.vault.result.proxmox_host # required
  vm_id        = each.value.id                           # required
  vm_name      = each.key                                # optional
  template_id  = each.value.template                     # required
  vnic_bridge  = each.value.vnic_bridge
  datastore_id = each.value.datastore_id

  memory = 16384
  vcpu   = 4

  ci_password = each.value.ci_password
  ci_user     = data.external.vault.result.ci_user
  # this needs to be a path
  ci_ssh_key = data.external.vault.result.ci_ssh_key

  ci_ipv4_cidr    = "dhcp"
  ci_ipv4_gateway = ""
}

output "id_multiple_vms" {
  value = { for k, v in module.vm_multiple_config : k => v.id }
}

output "public_ipv4_multiple_vms" {
  value = { for k, v in module.vm_multiple_config : k => flatten(v.public_ipv4) }
}

resource "null_resource" "cluster_config" {
  for_each = { for k, v in module.vm_multiple_config : k => flatten(v.public_ipv4) }

  connection {
    host        = each.key
    type        = "ssh"
    user        = data.external.vault.result.vm_user
    password    = data.external.vault.result.vm_user_password
    private_key = file(data.external.vault.result.remote_exec_connection_private_key)
  }

  provisioner "remote-exec" {
    inline = [
      # add ansible user
      "echo ${data.external.vault.result.ansible_user_password} | sudo -S useradd -m ${data.external.vault.result.ansible_user};",
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
}
