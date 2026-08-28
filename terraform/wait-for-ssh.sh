#!/bin/bash
# Blocks until the Windows VM accepts an SSH command as Administrator.
#
# Windows reports "running" well before user-data has installed and started
# sshd, so Terraform needs an explicit gate before the resource is treated as
# ready. Authentication uses the workspace's SSH agent, matching the key that
# user-data injected into administrators_authorized_keys.

set -u

HOST="${1:?usage: wait-for-ssh.sh HOST [TIMEOUT_SECONDS]}"
TIMEOUT="${2:-1200}"
INTERVAL=10

SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
  -o ConnectTimeout=10
)

echo "Waiting for SSH on $HOST (timeout ${TIMEOUT}s)..."
deadline=$(( SECONDS + TIMEOUT ))

while (( SECONDS < deadline )); do
  if ssh "${SSH_OPTS[@]}" "Administrator@$HOST" 'exit 0' 2>/dev/null; then
    echo "SSH is ready on $HOST after ${SECONDS}s"
    exit 0
  fi
  sleep "$INTERVAL"
done

echo "Timed out after ${TIMEOUT}s waiting for SSH on $HOST" >&2
echo "Check the VM's user-data log at C:\\Windows\\Temp\\user-data.log via the EC2 console." >&2
exit 1
