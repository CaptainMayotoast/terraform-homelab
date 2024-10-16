terraform {
  required_providers {
    # used for leveraging Ansible vaults to store field values
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

    # work around for https://github.com/Telmate/terraform-provider-proxmox/issues/1000
    # https://registry.terraform.io/providers/ivoronin/macaddress/latest/docs/resources/macaddress
    macaddress = {
      source = "ivoronin/macaddress"
      version = "0.3.2"
    }
  }
}

resource "macaddress" "mac_address_analyse" {
	count = 2
}

data "external" "vault" {
  program = [
    "./bin/ansible-vault-proxy.sh",
    "terraform-vault.json"
  ]
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

resource "proxmox_vm_qemu" "cloudinit-test" {
    name = "homelabvm${count.index + 1}" # count.index starts at 0
    count = 2 # Establishes how many instances will be created
    desc = "A test for using terraform and cloudinit"

    ciuser = data.external.vault.result.connection_user
    cipassword = data.external.vault.result.connection_user_password
    searchdomain = data.external.vault.result.resource_searchdomain

    # Node name has to be the same name as within the cluster
    # this might not include the FQDN
    target_node = data.external.vault.result.proxmox_host

    # The template name to clone this vm from
    clone = data.external.vault.result.template_name

    # Activate QEMU agent for this VM
    agent = 1

    balloon = "1024" # MB
    bios    = "ovmf"
    cores   = "4"
    cpu     = "host"
    memory  = "1024" # MB
    os_type = "cloud-init"
    scsihw = "virtio-scsi-pci"
    tablet  = "true"
    qemu_os = "l26"
    vcpus   = "0"

    # tags    = var.virtual_machine_tags

    # Setup the disks
    disks {
        scsi {
            scsi0 {
                disk {
                  backup     = true
                  cache      = "writethrough"
                  discard    = true
                  emulatessd = true
                  iothread   = true
                  replicate  = true
                  size       = "200G"
                  storage    = data.external.vault.result.storage
                }
            }
            scsi1 {
                cloudinit {
                  storage = data.external.vault.result.storage
                }
            }
        }
    }

    # setup the network interface and assign a vlan tag: 50
    network {
        model = "virtio"
        bridge = data.external.vault.result.nic_name
        # tag = 50
        macaddr = upper(macaddress.mac_address_analyse[count.index].address)
    }

    # setup the ip address using cloud-init.
    boot = "order=scsi0"

    # dhcp does not seem to work properly for this version of Telmate Proxmox, set an IP in the static range of the router
    ipconfig0 = "ip=192.168.20.20${count.index + 1}/24,gw=192.168.20.1"

    sshkeys = data.external.vault.result.ssh_key

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
        password    = data.external.vault.result.connection_user_password
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
