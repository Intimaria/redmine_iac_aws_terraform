
# general 
variable  "ami" {}
variable  "class" {}
variable  "ssh_user" {}
variable  "key_name" {}
variable  "public_key" {}
variable  "private_key_path" {}
variable  "region" {}
variable  "availability_zones" {}
# db
variable "engine" {}
variable "engine_version" {}     
variable "instance_class" {}
variable "db_name"  {}       
variable "username" {}  
variable "password" {} 
variable "port" {}
variable "parameter_group_name" {}
# ebs 
variable "detach_ebs" {}
variable "snapshot_id" {}