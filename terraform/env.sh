#!/bin/bash
# Exports sandbox environment as JSON for Terraform's `data "external"`.
#
# Provides the sandbox name and id (used for tagging, so stray AWS resources are
# attributable to a sandbox) and the workspace's SSH public key, which user-data
# installs into the VM's administrators_authorized_keys.

set -eu

public_key="$(ssh-add -L 2>/dev/null | head -1)"

if [[ -z "$public_key" ]]; then
  echo "no SSH key available from ssh-add -L; is SSH_AUTH_SOCK set in this workspace?" >&2
  exit 1
fi

jq -n \
  --arg sandbox_name "${SANDBOX_NAME:-local}" \
  --arg sandbox_id "${SANDBOX_ID:-local}" \
  --arg ssh_pub "$public_key" \
  '{sandbox_name: $sandbox_name, sandbox_id: $sandbox_id, ssh_pub: $ssh_pub}'
