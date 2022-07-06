# outputs.tf

output "alb_hostname" {
  value = aws_alb.main.dns_name
}

output "vpc_id" {
  value = aws_vpc.my_vpc.id
}

output "private_subnets" {
  value = aws_subnet.privatesubnet.*.id
}

output "public_subnets" {
  value = aws_subnet.publicsubnet.*.id
}