#Set your public SSH key here
variable "ssh_key" {
    default = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDN8YaSwJ1sRq7PET32LKZiorq4B49GUT+7PU0+s7tTz7+/y1SqFK383A0JhtrFOCTI2stBCSQD6D/l5fckINUUb/kS5Ok4dVHYmxI3ucx/OkJnU5Sw1BG+Lz5PXI0UpRbIwUH6edk1HOpT4zvfI+1Oej/1NcCWZ0roSQFV4BWunMoc8bgyh0otH/1iZ5eAVNTRFp+0xOmCfd4111BvHzHaayijKI6RULqCvXUjEy4I66SYgybaES1rkhM+OIfhDJS7ZihEj62Hf2marJes+hriC/xs4HyafAz93mwlwMWfZTg30CIgt+aFdBJvKRkZ9tYQQ8EYz4ekeYj53iksyu3IqWhwUpwJ6TPWPAmTJEKGHmqTjzKhgpSTDbi2l1KZjGfUPr1JylD+iosFStLbwWDUaV93zrL/Xwhf+pYHcff2mRJh4or/FpHw/Bj0Xn5llp7guOeMDTfuma9ENZQFOBNSsiqwVVHdCJtmWbwZVZiR55qHFTFOh8KlnuwhaM6KtSU= aschwartz@pop-os"
}
variable "ssh_key_ansible" {
    default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAWG5Jf2DgORED64Ar0ThRX0nSDliwQdTIjq2dQkpv2F ansible@pop-os"
}
variable "password" {
    default = "password"
}
variable "ansible_password" {
    default = "password"
}
#Establish which Proxmox host you'd like to spin a VM up on
variable "proxmox_host" {
    default = "proxmox"
}
#Specify which template name you'd like to use
# create a template: https://tcude.net/creating-a-vm-template-in-proxmox/
variable "template_name" {
    default = "ubuntu2204template"
}
#Establish which nic you would like to utilize
variable "nic_name" {
    default = "vmbr1"
}
#Establish the VLAN you'd like to use
variable "vlan_num" {
    default = "1"
}
#Provide the url of the host you would like the API to communicate on.
#It is safe to default to setting this as the URL for what you used
#as your `proxmox_host`, although they can be different
variable "api_url" {
    default = "https://192.168.10.8:8006/api2/json"
}

