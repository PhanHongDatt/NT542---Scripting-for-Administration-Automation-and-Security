output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = [for s in values(aws_subnet.public) : s.id]
}

output "private_subnet_ids" {
  value = [for s in values(aws_subnet.private) : s.id]
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_arn" {
  value = aws_lb.this.arn
}

output "app_instance_ids" {
  value = [for i in values(aws_instance.app) : i.id]
}

output "s3_vpc_endpoint_id" {
  value = aws_vpc_endpoint.s3.id
}