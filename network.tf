
resource "aws_vpc" "redmine_vpc" {
  cidr_block       = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "Redmine VPC"
  }
}

resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.redmine_vpc.id
  cidr_block = "10.0.0.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = "true" 
  tags = {
    Name = "Public Subnet"
  }
}

resource "aws_subnet" "private1" {
  vpc_id     = aws_vpc.redmine_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = "false" 
  tags = {
    Name = "Private Subnet 1"
  }
}

resource "aws_subnet" "private2" {
  vpc_id     = aws_vpc.redmine_vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = "false" 
  tags = {
    Name = "Private Subnet 2"
  }
}

resource "aws_db_subnet_group" "database_group" {
  subnet_ids  = [aws_subnet.private1.id, aws_subnet.private2.id]
}

resource "aws_internet_gateway" "redmine_vpc_igw" {
  vpc_id = aws_vpc.redmine_vpc.id

  tags = {
    Name = "Redmine VPC - Internet Gateway"
  }
}

resource "aws_route_table" "public_access" {
    vpc_id = aws_vpc.redmine_vpc.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.redmine_vpc_igw.id
    }

    tags = {
        Name = "Public Subnet Route Table."
    }
}

resource "aws_route_table_association" "public_access" {
    subnet_id = aws_subnet.public.id
    route_table_id = aws_route_table.public_access.id
}

resource "aws_security_group" "internet" {
  vpc_id =  aws_vpc.redmine_vpc.id

  ingress {
    from_port  = 443
    to_port    = 443
    protocol   = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port  = 80
    to_port    = 80
    protocol   = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port  = 22
    to_port    = 22
    protocol   = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port  = 0
    to_port    = 0
    protocol   = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_security_group" "database" {
  vpc_id =  aws_vpc.redmine_vpc.id

  ingress {
    from_port  = 3306
    to_port    = 3306
    protocol   = "tcp"
    security_groups = [aws_security_group.internet.id]
  }

  egress {
    from_port  = 0
    to_port    = 0
    protocol   = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_eip" "eip" {
  vpc = true
}
resource "aws_eip_association" "eip_association" {
  instance_id   = module.main.id
  allocation_id = aws_eip.eip.id
  depends_on    = [aws_internet_gateway.redmine_vpc_igw]
}