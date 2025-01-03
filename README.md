# Terraform VM creation

For extensive debugging: `export TF_LOG=TRACE`

Typical workflow:

1. `terraform init`
2. `terraform plan -out <plan_name>.txt`
3. `terraform apply "<plan_name>.txt"`
4. `terraform destroy` (when needed)

## Proxmox configuration

1. Create a `terraform` user in Proxmox: `pveum user add terraform@pve`.
2. Add a Terraform role: `pveum role add terraform-role -privs "VM.Allocate VM.Clone VM.Config.CDROM VM.Config.CPU VM.Config.Cloudinit VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Monitor VM.Audit VM.PowerMgmt Datastore.AllocateSpace Datastore.Audit SDN.Use User.Modify Sys.Audit Sys.Console Sys.Modify Pool.Allocate VM.Migrate"`
3. Modify `terraform` user with the above custom role: `pveum aclmod / -user terraform@pve -role terraform-role`.
4. Add an API token with `@pve` authentication, for the `terraform` user.  Specify the `token id` as `terraform-token` or something similar: `pveum user token add terraform@pve terraform-token --privsep=0`.
5. Copy credentials provided into the `terraform-vault` file under `terraform_token_secret` (i.e. `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`) and `terraform_token_id` (i.e. `terraform@pve!terraform-token`).

## Ansible vault integration

1. Create a Python virtual environment: `python3 -m venv terraform-python-venv`

2. Activate the virtual environment: `source .terraform-python-venv/bin/activate`

3. `pipx install ansible-core`

4. `ansible-vault create terraform-vault`
> Enter a password

5. Add entries.

6. `ansible-vault encrypt terraform-vault --vault-password-file ./password-file`

7. Proceed to run `terraform plan -out <plan_name>.txt`.

8. Run `terraform apply <plan_name>.txt`

## terraform-vault.json fields

Decrypt the vault with the password file: `ansible-vault decrypt terraform-vault.json --vault-password-file <path to password file>`

Encrypt with: `ansible-vault encrypt terraform-vault.json --vault-password-file <path to password file>`

- `ansible_user`
- `ansible_user_password`
- `api_token`, the full token, i.e. `<username>@pam!token=XXXXXXXX-XXXXX-XXXX-XXXX-XXXXXXXXXXXX`
- `api_url`, the PVE API URL, i.e. `https:://...`
- `connection_user`, used to make the connection to Proxmox over SSH (i.e. `terraform`)
- `connection_user_private_key`, path to the private key for connecting to Proxmox, i.e. `~/.ssh/terraform_id_ed25519` 
- `nic_name`, the name of the target NIC (i.e. `vmbr<n>`, where `n` >= `0`)
- `proxmox_host`, the name of the PVE node (aka its hostname) 
- `resource_searchdomain`, the search domain (probably determined by a router)
- `ssh_key`, connection user SSH public key
- `ssh_key_ansible`, ansible user SSH key
- `storage`, the name of the storage id to use for VMs
- `template_name`, the template name that exists on the PVE
- `vlan_num`, not currently used
- `vm_user`
- `vm_user_password`

## Helpful articles

- Proxmox/Terraform provider permissions https://github.com/Telmate/terraform-provider-proxmox/issues/784
- Proxmox/Terraform general setup https://tcude.net/using-terraform-with-proxmox/
- Create Proxmox [templates](https://www.trfore.com/posts/using-terraform-to-create-proxmox-templates/)
- Create Proxmox [VMs](https://www.trfore.com/posts/provisioning-proxmox-8-vms-with-terraform-and-bpg/)
