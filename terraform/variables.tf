variable "vpc_id" {
  description = "VPC to launch the Windows VM in"
  type        = string
}

variable "subnet_id" {
  description = "Subnet to launch into. Must route to the internet so the workspace can reach the VM; the data volume is created in this subnet's AZ."
  type        = string
}

variable "key_name" {
  description = "Name of the EC2 key pair used to encrypt the Administrator password"
  type        = string
}

variable "keypair_file" {
  description = "Path to the private key PEM matching key_name, used to decrypt the Administrator password. Must be PKCS#1 (BEGIN RSA PRIVATE KEY)."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the Windows VM"
  type        = string
  default     = "t3.large"
}

variable "ami_id" {
  description = "Windows AMI to launch. Leave empty to resolve ami_ssm_parameter instead. Set this to a custom AMI with your tooling pre-installed for faster startup."
  type        = string
  default     = ""
}

variable "ami_ssm_parameter" {
  description = "Public SSM parameter used to resolve the AMI when ami_id is empty"
  type        = string
  default     = "/aws/service/ami-windows-latest/Windows_Server-2022-English-Full-Base"
}

variable "allowed_cidrs" {
  description = "CIDRs allowed to reach the VM on 22 and 3389. Set this to your Crafting cluster's egress CIDR; do not leave it open to the internet."
  type        = list(string)
}

variable "root_volume_size" {
  description = "Size of the Windows system disk in GB"
  type        = number
  default     = 100
}

variable "data_volume_size" {
  description = "Size of the persistent data volume in GB. This volume survives suspend/resume."
  type        = number
  default     = 100
}

variable "data_volume_type" {
  description = "EBS volume type for the data volume"
  type        = string
  default     = "gp3"
}

variable "data_volume_label" {
  description = "NTFS label applied to the data volume on first boot"
  type        = string
  default     = "data"
}

variable "extra_setup" {
  description = "Extra PowerShell appended to user-data, for customer-specific setup (hosts entries, dev certs, software installs). Runs once on first boot."
  type        = string
  default     = ""
}

variable "suspended" {
  description = "When true the instance is destroyed but the data volume is kept, so a resume restores the same data."
  type        = bool
  default     = false
}
