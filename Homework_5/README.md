# Terraform VPC App

Bo bai nop nay su dung Terraform de tao mot ha tang AWS gom:

- 1 VPC
- 2 public subnets
- 2 private subnets
- 1 Internet Gateway
- 1 NAT Gateway
- 1 Application Load Balancer
- 2 EC2 backend trong private subnets
- 1 S3 Gateway VPC Endpoint

## Cac file chinh

- `main.tf`: dinh nghia tai nguyen AWS
- `variables.tf`: khai bao bien dau vao
- `provider.tf`: cau hinh AWS provider
- `versions.tf`: rang buoc version Terraform va provider
- `output.tf`: outputs sau khi deploy
- `terraform.tfvars.example`: vi du gia tri bien
- `.terraform.lock.hcl`: lock provider version

## Cac buoc chay co ban

```bash
terraform init
terraform validate
terraform plan -var-file=terraform.tfvars.example
terraform apply -var-file=terraform.tfvars.example
```

