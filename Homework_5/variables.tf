variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name prefix."
  type        = string
  default     = "demo-vpc-app"
}

variable "vpc_cidr" {
  description = "CIDR cho VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "2 CIDR cho public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "Cần đúng 2 public subnet CIDRs."
  }
}

variable "private_subnet_cidrs" {
  description = "2 CIDR cho private subnets"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) == 2
    error_message = "Cần đúng 2 private subnet CIDRs."
  }
}

variable "allowed_ingress_cidrs" {
  description = "CIDR được phép vào ALB HTTP/80"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "instance_type" {
  description = "EC2 instance type cho app"
  type        = string
  default     = "t3.micro"
}

variable "app_port" {
  description = "Port ứng dụng backend"
  type        = number
  default     = 80
}

variable "tags" {
  description = "Extra tags"
  type        = map(string)
  default     = {}
}