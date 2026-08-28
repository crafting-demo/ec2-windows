# ec2-windows

Run a Windows VM as part of a [Crafting](https://crafting.dev) sandbox, with SSH
from the workspace and browser-based RDP through an authenticated sandbox
endpoint.

This is the Windows counterpart to
[ec2-mac](https://github.com/crafting-demo/ec2-mac).

## What you get

- An EC2 Windows VM provisioned as a sandbox **resource**, so it follows the
  sandbox lifecycle: created with the sandbox, terminated on suspend, recreated
  on resume, destroyed on delete.
- A **persistent EBS data volume** that survives suspend/resume, mounted as `D:`.
- **Passwordless SSH** from the workspace, using the sandbox's own SSH key.
- **Web RDP** at a sandbox endpoint, served by a single container running guacd
  plus a small Jetty websocket tunnel. No Guacamole web app and no MySQL.

## Layout

| Path | Purpose |
| --- | --- |
| `terraform/` | The VM, data volume, and security group |
| `user-data/user-data.ps1` | First-boot Windows setup: OpenSSH, keys, volume, RDP |
| `scripts/` | Helper scripts run inside the sandbox |
| `.sandbox/template.yaml` | Sandbox template wiring it all together |
| `examples/` | A ready-to-copy sandbox definition and a teardown helper |
| `guacamole-jetty/`, `Dockerfile`, `start.sh` | The web RDP container |
| `docs/windows-in-crafting-sandbox.md` | Full setup and customization guide |

## Quick start

Read [the guide](docs/windows-in-crafting-sandbox.md). In short: build and
publish the RDP image, fill in the `# <-- REPLACE` values in
`.sandbox/template.yaml` (VPC, subnet, key pair, image), then create a sandbox
from the template.

## Requirements

- An AWS account with permission to manage EC2 instances, volumes, and security
  groups.
- An EC2 key pair, with its private key stored as a Crafting org secret. The VM's
  Administrator password is encrypted with this key and decrypted by Terraform.
- A container registry your sandboxes can pull from, for the RDP image.
