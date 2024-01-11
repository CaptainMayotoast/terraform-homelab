terraform {
  required_providers {
    proxmox = {
      source = "telmate/proxmox"
      version = "2.9.11"
    }
  }
}

provider "proxmox" {
  # References our vars.tf file to plug in the api_url 
  pm_api_url = var.api_url
  # References our secrets.tfvars file to plug in our token_id
  pm_api_token_id = var.token_id
  # References our secrets.tfvars to plug in our token_secret 
  pm_api_token_secret = var.token_secret
  # Default to `true` unless you have TLS working within your pve setup 
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
resource "proxmox_vm_qemu" "kubernetesvm" {
  name = "kubernetesvm${count.index + 1}" # count.index starts at 0
  count = 4 # Establishes how many instances will be created 
  target_node = var.proxmox_host

  # References our vars.tf file to plug in our template name
  clone = var.template_name
  # Creates a full clone, rather than linked clone 
  # https://pve.proxmox.com/wiki/VM_Templates_and_Clones
  full_clone  = "true"

  # VM Settings. `agent = 1` enables qemu-guest-agent
  agent = 1
  os_type = "cloud-init"
  # ipconfig0 = "ip=192.168.20.${count.index + 30}/24,gw=192.168.20.1"
  # nameserver = "192.168.20.1"
  searchdomain = "andromeda"
  cores = 3
  sockets = 2
  cpu = "host"
  memory = 10240 # bytes
  scsihw = "virtio-scsi-pci"
  bootdisk = "scsi0"

  disk {
    slot = 0
    size = "150G"
    type = "scsi"
    storage = "local-btrfs" # Name of storage local to the host you are spinning the VM up on
    # Enables SSD emulation
    ssd = 1
    # Enables thin-provisioning
    discard = "on"
  }

  network {
    model = "virtio"
    bridge = var.nic_name
    #tag = var.vlan_num # This tag can be left off if you are not taking advantage of VLANs
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
      user        = "aschwartz" # default user
      password    = var.password
  }

  provisioner "remote-exec" {
    inline = [
      # add ansible user
      "echo ${var.password} | sudo -S useradd -m ansible;", 
      # load SSH key for ansible user on command machine (where Terraform commands are launched from)
      "sudo bash -c 'mkdir /home/ansible/.ssh/ && echo ${var.ssh_key_ansible} >> /home/ansible/.ssh/authorized_keys';",
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
