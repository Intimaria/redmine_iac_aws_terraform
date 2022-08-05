terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.22.0"
    }
  }
}

resource "aws_key_pair" "redmine" {
  key_name   = "redmine"
  public_key = var.public_key
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
                  -i '${module.main.public_ip},' provisioning/redmine.yml
                  EOT 
    }
}


