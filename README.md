# Provisioning aws infrastructure for Redmine with terraform 

## Infrastructure
Creates a VPN with private and public subnets, 
On te public subnet, an EC2 instance, with attached EBS volume for uploads.
On the private subnet, an RDS instance, with ssh access to the EC2 instance
which holds the redmine data. 
The RDS has configured snapshots for backup. 
The EBS is backed up using data lifecycle resource policy & IAM role for implementation. 

## Ansible 
The Redmine instance is provisioned with Ansible in /provisioning, and the 
EBS is configured with Ansible in /ebs_configure.

## Requirements 
Needs to have created an AWS keypair with private key named 'redmine.pem'.
Needs permissions to create the aforementioned resources. 

## Monitoring 
Monitoring for redmine instance can be found at <https://github.com/Intimaria/redmine_monitoring>
