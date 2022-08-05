
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