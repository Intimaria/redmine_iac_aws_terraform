

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.22.0"
    }
  }
}

data "aws_availability_zones" "available" {
    state = "available"
}

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

resource "aws_db_instance" "redmine" {

  lifecycle {
    ignore_changes = [
      password,
      snapshot_identifier
    ]
  }
  # snapshot_identifier   = "rds:terraform-20220802161247324000000004-2022-08-03-03-07"
  skip_final_snapshot   = true
  allocated_storage     = 10
  max_allocated_storage = 50
  engine                = var.engine
  engine_version        = var.engine_version
  instance_class        = var.instance_class
  db_name               = var.db_name
  username              = var.username
  password              = var.password
  port                  = var.port
  parameter_group_name  = var.parameter_group_name
  backup_retention_period = 5
  db_subnet_group_name   = aws_db_subnet_group.database_group.id
  vpc_security_group_ids = [aws_security_group.database.id]
  maintenance_window     = "Mon:00:00-Mon:03:00"
  backup_window          = "03:00-06:00"
  deletion_protection    = true

  tags = {
    Name = "redmine"
  }
}

resource "local_file" "db_host" {
    content  = "host: ${aws_db_instance.redmine.address}"
    filename = "provisioning/roles/redmine_download/vars/db_host.yml"
}

resource "aws_key_pair" "redmine" {
  key_name   = "redmine"
  public_key = var.public_key
  }

resource "aws_ebs_volume" "ebs"{

  snapshot_id       =  var.snapshot_id
  availability_zone =  data.aws_availability_zones.available.names[0]
  size              = 30
  type              = "gp2"
  tags = {
    Name = "redmine"
  }
}

resource "aws_volume_attachment" "ebs_attach" {
  device_name = "/dev/sdg"
  volume_id   = aws_ebs_volume.ebs.id
  instance_id = module.main.id
  #stop_instance_before_detaching = true
}

resource "null_resource" "configure_ebs" {
    depends_on = [aws_volume_attachment.ebs_attach, module.main, null_resource.provision_ec2]
      triggers = {
     on_ebs = aws_ebs_volume.ebs.id
   }

     provisioner "local-exec" {
      interpreter = ["/bin/bash" ,"-c"]
      command = <<EOT
                sleep 120; ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
                -u ubuntu --private-key ${var.private_key_path} \
                -i '${module.main.public_ip},' ebs_configure/disk.yml -e detach=${var.detach_ebs} \
                --skip-tags ${var.snapshot_id != "" ? "format" : ""}
                EOT   
    }
}

module "main" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 3.0"

  name = "main"
  
  ami                    = var.ami 
  instance_type          = var.class
  key_name               = aws_key_pair.redmine.key_name 
  vpc_security_group_ids = [aws_security_group.internet.id]
  subnet_id              = aws_subnet.public.id

  root_block_device = [{
    kms_key_id      = null
  }]
}

resource null_resource "provision_ec2" {
  depends_on = [aws_db_instance.redmine, module.main ]
  provisioner "local-exec" {
      interpreter = ["/bin/bash" ,"-c"]
      command = <<EOT 
                  sleep 120; ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \ 
                  -u ubuntu --private-key ${var.private_key_path} \ 
                  -i '${module.main.public_ip},' provisioning/redmine.yml"
                  EOT
    }
}


resource "aws_iam_role" "dlm_lifecycle_role" {
  name = "dlm-lifecycle-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "dlm.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "dlm_lifecycle" {
  name = "dlm-lifecycle-policy"
  role = aws_iam_role.dlm_lifecycle_role.id

  policy = <<EOF
{
   "Version": "2012-10-17",
   "Statement": [
      {
         "Effect": "Allow",
         "Action": [
            "ec2:CreateSnapshot",
            "ec2:CreateSnapshots",
            "ec2:DeleteSnapshot",
            "ec2:DescribeInstances",
            "ec2:DescribeVolumes",
            "ec2:DescribeSnapshots"
         ],
         "Resource": "*"
      },
      {
         "Effect": "Allow",
         "Action": [
            "ec2:CreateTags"
         ],
         "Resource": "arn:aws:ec2:*::snapshot/*"
      }
   ]
}
EOF
}

resource "aws_dlm_lifecycle_policy" "example" {
  description        = "example DLM lifecycle policy"
  execution_role_arn = aws_iam_role.dlm_lifecycle_role.arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]

    schedule {
      name = "10 of 3 hourly snapshots"

      create_rule {
        interval      = 3
        interval_unit = "HOURS"
        times         = ["00:30"]
      }

      retain_rule {
        count = 10
      }

      tags_to_add = {
        SnapshotCreator = "DLM"
      }

      copy_tags = false
    }

    target_tags = {
      Snapshot = "true"
      Name     = "redmine"
      Backup   = "redmine"
    }
  }
}