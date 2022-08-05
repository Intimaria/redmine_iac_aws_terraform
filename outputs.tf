
output "az" {
  value = data.aws_availability_zones.available.names
}

output "eip" {
    value = aws_eip.eip.public_ip 
}

