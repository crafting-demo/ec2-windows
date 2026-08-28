# The Crafting resource system reads this named output (via `output: output` in
# the sandbox YAML) and saves it as the resource state, readable in the
# workspace at /run/sandbox/fs/resources/windows/state.
#
# Marked sensitive because it carries the Administrator password. `terraform
# output -json output` still emits the value, so saving state is unaffected.

output "output" {
  sensitive = true
  value = {
    public_dns  = length(aws_instance.windows) > 0 ? aws_instance.windows[0].public_dns : null
    public_ip   = length(aws_instance.windows) > 0 ? aws_instance.windows[0].public_ip : null
    instance_id = length(aws_instance.windows) > 0 ? aws_instance.windows[0].id : null
    volume_id   = aws_ebs_volume.data.id

    # password_data is RSA-encrypted with the launch key pair; rsadecrypt needs
    # the matching PKCS#1 private key.
    password = length(aws_instance.windows) > 0 ? rsadecrypt(aws_instance.windows[0].password_data, file(var.keypair_file)) : null
  }
}
