terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">=5"
    }
    external = {
      source  = "hashicorp/external"
      version = ">=2"
    }
  }
}

data "external" "env" {
  program = ["${path.module}/env.sh"]
}

provider "aws" {
  default_tags {
    tags = {
      Sandbox   = data.external.env.result.sandbox_name
      SandboxID = data.external.env.result.sandbox_id
      ManagedBy = "crafting-sandbox"
    }
  }
}

locals {
  name = "crafting-windows-${data.external.env.result.sandbox_name}"
}

# The data volume must live in the same AZ as the instance, so derive the AZ
# from the subnet rather than asking for it separately and risking a mismatch.
data "aws_subnet" "target" {
  id = var.subnet_id
}

data "aws_ssm_parameter" "windows_ami" {
  count = var.ami_id == "" ? 1 : 0
  name  = var.ami_ssm_parameter
}

locals {
  ami_id = var.ami_id != "" ? var.ami_id : data.aws_ssm_parameter.windows_ami[0].value
}

# --- Security group ---
#
# Ingress is limited to the CIDRs the caller supplies, which should be the
# Crafting cluster's egress range. Both SSH and RDP are reached from inside the
# sandbox: SSH from the workspace, RDP from the guacd container.

resource "aws_security_group" "windows" {
  name_prefix = "crafting-windows-"
  description = "Crafting sandbox Windows VM"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from the Crafting sandbox"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  ingress {
    description = "RDP from the guacd container in the sandbox"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = local.name }

  lifecycle {
    create_before_destroy = true
  }
}

# --- Persistent data volume (survives suspend) ---

resource "aws_ebs_volume" "data" {
  availability_zone = data.aws_subnet.target.availability_zone
  size              = var.data_volume_size
  type              = var.data_volume_type

  tags = { Name = "${local.name}-data" }
}

# --- Windows instance (destroyed on suspend, recreated on resume) ---

resource "aws_instance" "windows" {
  count = var.suspended ? 0 : 1

  ami                         = local.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.windows.id]
  associate_public_ip_address = true

  # Required for the Administrator password to be retrievable at all.
  get_password_data = true

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/../user-data/user-data.ps1", {
    ssh_public_key    = data.external.env.result.ssh_pub
    data_volume_label = var.data_volume_label
    extra_setup       = var.extra_setup
  })

  tags = { Name = local.name }
}

resource "aws_volume_attachment" "data" {
  count = var.suspended ? 0 : 1

  device_name = "xvdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.windows[0].id

  # On suspend the instance is destroyed while the volume lives on; without this
  # the detach can hang waiting for a guest that is already gone.
  force_detach = true
}

# --- Wait until the VM is actually usable ---
#
# Windows reports "running" long before sshd is listening. Without this gate the
# resource would go ready while `ssh` still fails, and the RDP params push would
# fire against a VM that cannot accept it.

#
# This deliberately uses local-exec rather than remote-exec. Terraform's SSH
# remote-exec uploads a script and executes it by path, which does not work
# against a Windows host whose default shell is PowerShell.

resource "null_resource" "wait_for_ssh" {
  count = var.suspended ? 0 : 1

  depends_on = [aws_volume_attachment.data]

  triggers = {
    instance_id = aws_instance.windows[0].id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "${path.module}/wait-for-ssh.sh ${aws_instance.windows[0].public_ip}"
  }
}
