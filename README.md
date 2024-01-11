# Terraform VM creation

For extensive debugging: `export TF_LOG=TRACE`

`terraform init`
`terraform plan -out first_plan.txt`
`terraform apply "first_plan.txt"`
`terraform destroy`

