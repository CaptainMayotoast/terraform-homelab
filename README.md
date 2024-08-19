# Terraform VM creation

For extensive debugging: `export TF_LOG=TRACE`

Typical workflow:

1. `terraform init`
2. `terraform plan -out <plan_name>.txt`
3. `terraform apply "<plan_name>.txt"`
4. `terraform destroy`

## Proxmox configuration

1. Create a `terraform` user in Proxmox.
2. Add a Terraform role: `pveum role add terraform-role -privs "VM.Allocate VM.Clone VM.Config.CDROM VM.Config.CPU VM.Config.Cloudinit VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Monitor VM.Audit VM.PowerMgmt Datastore.AllocateSpace Datastore.Audit"`
3. Modify `terraform` user with the above custom role: `pveum aclmod / -user terraform@pve -role terraform-role`
4. Add an API token with `@pve` authentication, for the `terraform` user.  Specify the `token id` as `terraform-token` or something similar.
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

8. Run `terraform apply "<plan_name>.txt"`

## Helpful articles

- Proxmox/Terraform provider permissions https://github.com/Telmate/terraform-provider-proxmox/issues/784
- Proxmox/Terraform general setup https://tcude.net/using-terraform-with-proxmox/
- Create Proxmox templates https://tcude.net/creating-a-vm-template-in-proxmox/

