# Build the Velociraptor Server for Operator Lab

# Locals for Velociraptor internal PKI, IP address, and credentials
locals {
  ca_crt               = indent(4, tls_self_signed_cert.certificate_authority.cert_pem)
  private_key_ca       = indent(4, tls_self_signed_cert.certificate_authority.private_key_pem)
  gw_crt               = indent(4, tls_locally_signed_cert.gw.cert_pem)
  private_key_gw       = indent(4, tls_private_key.gw.private_key_pem)
  frontend_crt         = indent(4, tls_locally_signed_cert.frontend.cert_pem)
  private_key_fe       = indent(4, tls_private_key.frontend.private_key_pem)
  pinned_gw_name       = "GRPC_GW"
  pinned_server_name   = "VelociraptorServer"
  vadmin_username      = "admin"
  vadmin_password      = "${random_pet.vel.id}-${random_string.vel.id}"
  vdownload_server     = "https://github.com/Velocidex/velociraptor/releases/download/v0.7.1/velociraptor-v0.7.1-1-linux-amd64"
  vdownload_client     = "https://github.com/Velocidex/velociraptor/releases/download/v0.7.1/velociraptor-v0.7.1-1-windows-amd64.msi"
  msi_file             = "velociraptor.msi"
}

resource "random_pet" "vel" {
  length = 2
}

resource "random_string" "vel" {
  length  = 4
  special = false
  upper   = true
}


resource "tls_private_key" "certificate_authority" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_private_key" "gw" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_private_key" "frontend" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "certificate_authority" {
  private_key_pem = tls_private_key.certificate_authority.private_key_pem

  subject {
    organization = "Velociraptor CA"
  }

  is_ca_certificate     = true
  validity_period_hours = 8760

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
    "client_auth",
    "crl_signing",
    "cert_signing"
  ]
}

resource "tls_cert_request" "gw" {
  private_key_pem = tls_private_key.gw.private_key_pem
  dns_names     = [local.pinned_gw_name]

  subject {
    common_name     = local.pinned_gw_name
    organization    = "Velociraptor"
  }
}

resource "tls_cert_request" "frontend" {
  private_key_pem = tls_private_key.frontend.private_key_pem
  dns_names     = [local.pinned_server_name]
  uris          = [local.pinned_server_name]
  ip_addresses  = [aws_instance.velociraptor.private_ip]

  subject {
    common_name  = local.pinned_server_name
    organization = "Velociraptor"
  }
}

resource "tls_locally_signed_cert" "gw" {
  cert_request_pem   = tls_cert_request.gw.cert_request_pem
  ca_private_key_pem = tls_private_key.certificate_authority.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.certificate_authority.cert_pem

  validity_period_hours = 8760

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
    "client_auth"
  ]
}


resource "tls_locally_signed_cert" "frontend" {
  cert_request_pem   = tls_cert_request.frontend.cert_request_pem
  ca_private_key_pem = tls_private_key.certificate_authority.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.certificate_authority.cert_pem

  validity_period_hours = 8760

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
    "client_auth"
  ]
}

# AWS AMI for Velociraptor 
data "aws_ami" "velociraptor" {
  most_recent      = true
  owners           = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

variable "vel_root_block_device_size" {
  description = "The volume size of the root block device."
  default     =  90 
}

variable "vel_instance_type" {
  description = "The AWS instance type to use for Velociraptor Server"
  default     = "t3a.medium"
}

variable "vserver_config" {
  description = "The name of the velociraptor config file"
  default     = "vel_server_config.yml"
}

# EC2 Velociraptor Instance
resource "aws_instance" "velociraptor" {
  ami           = data.aws_ami.velociraptor.id
  instance_type = var.vel_instance_type 
  key_name      = module.key_pair.key_pair_name
  subnet_id     = aws_subnet.user_subnet.id
  private_ip     = "10.100.20.200"
  associate_public_ip_address = true
  vpc_security_group_ids = [aws_security_group.vel_ingress.id, aws_security_group.vel_ssh_ingress.id, aws_security_group.vel_allow_all_internal.id]

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.private_key.private_key_pem
    host        = self.public_ip
  }

  user_data = templatefile("files/velociraptor/bootstrap.sh.tpl", {
    s3_bucket                 = "${aws_s3_bucket.staging.id}"
    region                    = var.region
    server_config             = var.vserver_config 
    vadmin_username           = local.vadmin_username 
    vadmin_password           = local.vadmin_password 
    vdownload_url             = local.vdownload_server
    kapefile                  = var.velociraptor_kapefile 
  })

  root_block_device {
    volume_type           = "gp2"
    volume_size           = var.vel_root_block_device_size
    delete_on_termination = "true"
  }

  tags = {
    "Name" = "velociraptor"
  }

}

resource "aws_security_group" "vel_ingress" {
  name   = "vel-ingress"
  vpc_id = aws_vpc.operator.id

  # Velociraptor specific 
  ingress {
    from_port       = 8000 
    to_port         = 8000 
    protocol        = "tcp"
    cidr_blocks     = [local.src_ip]
  }
  # Velociraptor specific
  ingress {
    from_port       = 8001
    to_port         = 8001
    protocol        = "tcp"
    cidr_blocks     = [local.src_ip]
  }
  # Velociraptor specific
  ingress {
    from_port       = 8889
    to_port         = 8889
    protocol        = "tcp"
    cidr_blocks     = [local.src_ip]
  }
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "vel_ssh_ingress" {
  name   = "vel-ssh-ingress"
  vpc_id = aws_vpc.operator.id

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.src_ip]
  }

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "vel_allow_all_internal" {
  name   = "vel-allow-all-internal"
  vpc_id = aws_vpc.operator.id

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = [var.vpc_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }
}

resource "aws_s3_object" "velociraptor_config_yml" {
  bucket = aws_s3_bucket.staging.id
  key    = var.vserver_config 
  source = local_file.velociraptor_config_yml.filename
  content_type = "text/plain"

  depends_on = [local_file.velociraptor_config_yml]
}

resource "local_file" "velociraptor_config_yml" {
  content  = data.template_file.velociraptor_local_yml.rendered
  filename = "${path.module}/output/velociraptor/${var.vserver_config}"
}

data "template_file" "velociraptor_local_yml" {
  template = file("${path.module}/files/velociraptor/config.yml.tpl")

  vars = {
    velociraptor_ip = aws_instance.velociraptor.private_ip
    ca_key          = local.private_key_ca
    ca_crt          = local.ca_crt 
    gw_crt          = local.gw_crt 
    gw_key          = local.private_key_gw
    fe_key          = local.private_key_fe
    fe_crt          = local.frontend_crt
  }
}

output "Velociraptor_server_details" {
  value = <<CONFIGURATION
-------
Velociraptor Console
-------------------
https://${aws_instance.velociraptor.public_dns}:8889

Velociraptor Credentials
------------------------
${local.vadmin_username}:${local.vadmin_password}

SSH to Velociraptor
-------------------
ssh -i ssh_key.pem ubuntu@${aws_instance.velociraptor.public_ip}

CONFIGURATION
}
