# Windows in a Crafting Sandbox

This guide sets up a Crafting sandbox with an EC2 Windows VM attached: SSH from
the workspace, a browser-based desktop through an authenticated endpoint, and a
data disk that survives suspend and resume.

It is the Windows counterpart to
[ec2-mac](https://github.com/crafting-demo/ec2-mac).

---

## Prerequisites

| What | Why | Notes |
| --- | --- | --- |
| AWS account and credentials | Provisioning the VM | Needs EC2 instance, volume, and security group permissions |
| An EC2 key pair | Windows encrypts the Administrator password with it | Must be RSA in PKCS#1 format |
| The key pair's `.pem` as an org secret | Terraform decrypts the password with it | See [Key pair](#key-pair) |
| An AWS config file as an org secret | Gives the sandbox its AWS identity | See [AWS credentials](#aws-credentials) |
| A container registry your sandboxes can pull from | Hosting the RDP image | See [Building the RDP image](#building-the-rdp-image) |
| Your Crafting cluster's egress CIDR | Locking down the VM's firewall | See [Finding your egress CIDR](#finding-your-egress-cidr) |

A VPC with a public subnet is also required. The subnet must assign public IPs
and route to an internet gateway, because the workspace reaches the VM over its
public address.

---

## Quick start

1. Fork this repo. The sandbox template checks it out, so it must be reachable
   from your org.
2. Build and publish the RDP image, then put its tag in the template. See
   [Building the RDP image](#building-the-rdp-image).
3. Store your key pair PEM and AWS config as org secrets.
4. Fill in every `# <-- REPLACE` in [`.sandbox/template.yaml`](../.sandbox/template.yaml):
   VPC, subnet, key pair name, secret paths, and your egress CIDR.
5. Create a sandbox from the template.

First creation takes roughly 5-10 minutes: most of it is Windows booting and
running first-boot setup.

---

## How it works

```mermaid
flowchart LR
  subgraph sandbox [Crafting Sandbox]
    dev[dev workspace]
    prov[provisioner workspace]
    tunnel["rdp-tunnel container<br/>guacd + Jetty"]
    ep[["rdp endpoint<br/>(authenticated)"]]
  end

  vm["EC2 Windows VM<br/>sshd + RDP"]
  vol[("EBS data volume<br/>persists across suspend")]

  prov -->|terraform apply| vm
  prov -->|"push-rdp-params.sh"| tunnel
  tunnel -->|"RDP 3389"| vm
  ep --> tunnel
  dev -->|"SSH 22"| vm
  vm --- vol
  browser([Browser]) --> ep
```

The `provisioner` workspace runs Terraform, which creates the VM and saves its
address and decrypted password as the `windows` resource state. A daemon in the
same workspace reads that state and configures the RDP tunnel. The browser only
ever talks to the sandbox endpoint, which Crafting authenticates.

### Lifecycle

| Event | What happens |
| --- | --- |
| Create | Terraform creates the security group, data volume, and VM; first-boot setup installs OpenSSH and formats the data volume |
| Suspend | The VM is **terminated**. The data volume and security group remain |
| Resume | A **new** VM is created and the existing data volume is re-attached |
| Delete | Everything, including the data volume, is destroyed |

Suspend terminating rather than stopping the instance is deliberate: it means
you pay only for the data volume while suspended. The consequence is that
**anything on `C:` is lost on suspend**. Keep work on `D:`.

The VM also comes back at a **different public address** after every resume.
Nothing should hard-code the address; read it from the resource state instead.

---

## Repository structure

| Path | Purpose |
| --- | --- |
| [`terraform/main.tf`](../terraform/main.tf) | Security group, data volume, VM, readiness gate |
| [`terraform/variables.tf`](../terraform/variables.tf) | Every knob, documented |
| [`terraform/outputs.tf`](../terraform/outputs.tf) | The `output` object saved as resource state |
| [`terraform/env.sh`](../terraform/env.sh) | Feeds sandbox name/id and the workspace SSH key to Terraform |
| [`terraform/wait-for-ssh.sh`](../terraform/wait-for-ssh.sh) | Blocks until the VM accepts SSH |
| [`user-data/user-data.ps1`](../user-data/user-data.ps1) | First-boot Windows setup |
| [`scripts/push-rdp-params.sh`](../scripts/push-rdp-params.sh) | Points the RDP tunnel at the VM, and keeps it pointed there |
| [`examples/teardown.sh`](../examples/teardown.sh) | Finds and cleans up orphaned AWS resources |
| `Dockerfile`, `start.sh`, `guacamole-jetty/` | The RDP tunnel image |

---

## Building the RDP image

The image is guacd plus a small Jetty websocket tunnel in a single container.
There is no Guacamole web application and no MySQL: the tunnel serves its own
client page and takes its connection settings over a tiny HTTP API.

```bash
docker build -t YOUR_REGISTRY/ec2-windows-guacamole:latest .
docker push YOUR_REGISTRY/ec2-windows-guacamole:latest
```

Then set that tag as the `rdp-tunnel` container image in your template.

The build is multi-stage: Maven compiles the Java tunnel, then it is layered
onto `guacamole/guacd:1.5.4`. The first build takes a few minutes while Maven
downloads dependencies.

### Ports

| Port | Purpose | Exposed? |
| --- | --- | --- |
| 8080 | Client page and the `/rdp` websocket | Yes, via the sandbox endpoint |
| 8081 | `PUT /params` configuration API | **No** |
| 4822 | guacd, internal to the container | No |

Port 8081 has no authentication of its own. Anyone who can reach it can point
the tunnel at a different host or read back which host it is targeting. Keep it
off the endpoint; the template exposes only 8080.

---

## Terraform configuration

### Required variables

| Variable | Description |
| --- | --- |
| `vpc_id` | VPC to launch into |
| `subnet_id` | Public subnet; its AZ also determines where the data volume lives |
| `key_name` | EC2 key pair name |
| `keypair_file` | Path to the matching PEM inside the sandbox |
| `allowed_cidrs` | CIDRs allowed to reach ports 22 and 3389 |

### Useful optional variables

| Variable | Default | Description |
| --- | --- | --- |
| `ami_id` | resolved from SSM | Set this to a custom AMI with your tooling baked in |
| `instance_type` | `t3.large` | |
| `data_volume_size` | `100` | Size of the persistent `D:` drive in GB |
| `root_volume_size` | `100` | Size of `C:`, which is lost on suspend |
| `extra_setup` | empty | Extra PowerShell for first-boot customization |
| `suspended` | `false` | Set by the sandbox on suspend; you should not set it yourself |

By default the AMI is resolved from the public SSM parameter for the latest
Windows Server 2022 base image, so nothing needs pinning to get started.

### How the password works

Windows encrypts the generated Administrator password with the launch key pair.
Terraform requests it with `get_password_data` and decrypts it in
[`outputs.tf`](../terraform/outputs.tf) using `rsadecrypt`, so the plaintext
password lands in the resource state and never needs a manual step.

The PEM must be PKCS#1, the format that begins:

```
-----BEGIN RSA PRIVATE KEY-----
```

A key in PKCS#8 format (`BEGIN PRIVATE KEY`) will fail. Convert it with:

```bash
openssl rsa -in key-pkcs8.pem -out key-pkcs1.pem
```

---

## Sandbox YAML

The template has four parts that matter.

**The resource** runs Terraform and saves its output as state:

```yaml
resources:
  - name: windows
    terraform:
      workspace: provisioner
      dir: ec2-windows/terraform
      output: output
      save_state: true
      on_suspend:
        vars:
          suspended: "true"
      on_delete: {}
```

Specifying `on_suspend` automatically enables resume, so there is no separate
`on_resume` field.

**The container** runs the RDP tunnel, with a readiness probe on `/index.html`
rather than `/`, because `/` returns a redirect that a probe treats as failure.

**The endpoint** exposes only port 8080 and is protected by Crafting's endpoint
authentication by default.

**The daemon** keeps the tunnel pointed at the VM:

```yaml
daemons:
  rdp-params:
    run:
      cmd: ./scripts/push-rdp-params.sh --watch
      dir: ec2-windows
      env:
        - PARAMS_URL=http://rdp-tunnel:8081/params
```

It runs in the `provisioner` workspace and needs no `wait_for`, because it polls
for the resource state itself. Adding `wait_for: [windows]` there would deadlock,
since that same workspace is what creates the resource.

`--watch` matters. The script reconciles continuously, so the tunnel recovers
both when the VM comes back at a new address after a resume and when the
container restarts and loses its settings.

> If you rename the `windows` resource, also set `STATE_FILE` in the daemon's
> environment, since the state path contains the resource name.

---

## Finding your egress CIDR

Traffic from a sandbox leaves your Crafting cluster from a small set of
addresses. Run this **inside a workspace** in the target cluster:

```bash
curl -s https://checkip.amazonaws.com
```

Use that address, or the range your cluster is configured with, as
`allowed_cidrs`. Ask your Crafting contact for the full range if the cluster has
more than one egress address.

Do not use `0.0.0.0/0`. It exposes RDP to the entire internet, where Windows
hosts are scanned and brute-forced continuously.

---

## AMI preparation

The default AMI is a stock Windows Server 2022 image, which is enough to get a
working desktop. A custom AMI is worth building when you need software
preinstalled, because baking it in is far faster than installing on every boot.

Build one by launching an instance from the base AMI, configuring it, then
creating an image from it. Typical additions:

- Your language runtimes and IDEs
- Git Bash, if you want a Unix-like shell
- `rsync`, if you plan to sync code from the workspace (see below)
- IIS or other server roles

Set `ami_id` in the template to use it.

### Installing rsync

`rsync` makes syncing code from the workspace much faster than `scp`. It needs
Git Bash installed first. Run in Git Bash on the VM:

```bash
mkdir tmp && cd tmp
GITBIN='c:\Program Files\Git\usr\bin\'

curl -L https://github.com/facebook/zstd/releases/download/v1.5.5/zstd-v1.5.5-win64.zip -o z.zip
unzip z.zip && cp zstd-v1.5.5-win64/zstd.exe "$GITBIN"

for pkg in \
  rsync-3.2.7-2-x86_64 \
  libzstd-1.5.5-1-x86_64 \
  libxxhash-0.8.1-1-x86_64 \
  liblz4-1.9.4-1-x86_64 \
  libopenssl-3.1.1-1-x86_64
do
  curl -L "https://repo.msys2.org/msys/x86_64/$pkg.pkg.tar.zst" -o p.tar.zst
  tar -I zstd -xf p.tar.zst
  cp usr/bin/*.exe usr/bin/*.dll "$GITBIN" 2>/dev/null
done
```

Then add `C:\Program Files\Git\usr\bin` to the system `PATH`.

### Sharing an AMI across accounts

A new AMI is private to the account that created it:

```bash
aws ec2 modify-image-attribute \
  --image-id ami-xxxxxxxx \
  --launch-permission "Add=[{UserId=TARGET_ACCOUNT_ID}]"
```

---

## Key pair

```bash
aws ec2 create-key-pair \
  --key-name crafting-shared \
  --key-type rsa \
  --key-format pem \
  --query KeyMaterial --output text > crafting-shared.pem
```

Store the PEM as an org secret and point `keypair_file` at its mounted path.
Rotating the key pair means updating the secret too, and any VM launched with
the old key keeps a password that only the old key can decrypt.

## AWS credentials

The workspace needs an AWS identity. Store an AWS config file as an org secret
and reference it with `AWS_CONFIG_FILE`. Anything the AWS SDK understands works,
including a `credential_process` for federated access:

```ini
[default]
region = us-west-1
credential_process = your-credential-helper
```

---

## Customization

### Extra first-boot setup

Use the `extra_setup` variable for PowerShell that should run once when the VM
boots. It runs after OpenSSH, the data volume, and RDP are configured:

```yaml
vars:
  extra_setup: |
    Add-Content -Path "C:\Windows\System32\drivers\etc\hosts" -Value "127.0.0.1 app.local.example.com"
    dotnet dev-certs https -v
    choco install -y nodejs
```

Prefer a custom AMI for anything slow. `extra_setup` runs on every create *and
every resume*, so a long install is a long wait, every time.

### Syncing code to the VM

With `rsync` on the VM, a build hook in your `dev` workspace can push code and
run a build:

```yaml
hooks:
  build:
    cmd: |
      set -e
      REMOTE=$(jq -r .public_dns /run/sandbox/fs/resources/windows/state)
      rsync -az --exclude '.git' -e "ssh -o StrictHostKeyChecking=no" \
        my-app/ "Administrator@$REMOTE:C:/work/my-app/"
      ssh "Administrator@$REMOTE" "cd C:\work\my-app; .\build.ps1"
```

Read the address from the state file rather than hard-coding it, since it
changes on every resume.

---

## Cost

You pay for three things: the instance while it runs, the data volume always,
and the root volume while the instance exists.

Windows instances carry a license surcharge on top of the Linux price, so a
`t3.large` is roughly $0.13/hour rather than $0.083. Suspending terminates the
instance, leaving only volume cost, which is a few dollars per month for a 100 GB
`gp3` volume. Suspending overnight and at weekends is the single biggest saving
available.

---

## Security

- **Lock down `allowed_cidrs`.** This is the one setting most worth getting
  right. RDP open to the internet is attacked constantly.
- **Keep port 8081 unexposed.** It can retarget the tunnel and has no auth.
- **The Administrator password is in the resource state**, readable by anyone
  with workspace access. That is the same trust boundary as the sandbox itself.
- **The endpoint is authenticated by default.** Do not set `auth_proxy.disabled`
  on it; that would put a Windows desktop on the public internet.
- SSH uses the sandbox's own key via the agent. No private key is ever written
  to the VM.

---

## Troubleshooting

### Terraform times out waiting for SSH

The VM booted but first-boot setup did not finish. Check the transcript at
`C:\Windows\Temp\user-data.log` through the EC2 console's "Get system log", or
by connecting with the password over RDP.

The usual causes are an AMI without the OpenSSH capability available, or a
security group that does not allow port 22 from the sandbox.

### The endpoint loads but the desktop stays blank or disconnects

The tunnel is reachable but cannot open an RDP session. Check what it is
targeting, from the provisioner workspace:

```bash
curl -s http://rdp-tunnel:8081/params
```

If `hostname` is `localhost`, the params push never landed. Check the daemon's
log. If it looks right, confirm the VM allows 3389 from the sandbox and that RDP
is enabled on the VM.

### Login fails with the correct password

The password in the state is the one generated at launch. If the VM was
recreated by a resume, re-read the state file rather than reusing an old value.
If the AMI has a preset Administrator password, EC2 will not generate one, and
`rsadecrypt` has nothing to decrypt; use the AMI's password instead.

### Data is missing after a resume

Confirm the work was on `D:`. `C:` is destroyed on suspend. If `D:` itself is
missing, check the first-boot log: the volume is only reformatted when it is
genuinely blank, so a missing drive letter is more likely than data loss.

### Orphaned AWS resources

If a sandbox was force-deleted, resources can survive. Everything is tagged, so:

```bash
examples/teardown.sh list
examples/teardown.sh delete SANDBOX_NAME
```
