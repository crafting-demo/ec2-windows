#!/usr/bin/env bash
#
# Find and clean up Windows VM resources left behind in AWS.
#
# Normally `terraform destroy` runs when the sandbox is deleted and nothing is
# left over. Orphans happen when a sandbox is force-deleted, when destroy fails
# partway, or while iterating on the Terraform. Everything this repo creates is
# tagged ManagedBy=crafting-sandbox plus the sandbox name and id, so orphans are
# always attributable.
#
# Usage:
#   examples/teardown.sh list                 show every managed resource
#   examples/teardown.sh list SANDBOX_NAME    show one sandbox's resources
#   examples/teardown.sh delete SANDBOX_NAME  delete one sandbox's resources
#
# Auth comes from the ambient AWS config; set AWS_CONFIG_FILE / AWS_PROFILE and
# REGION as needed.

set -uo pipefail

REGION="${REGION:-${AWS_DEFAULT_REGION:-us-west-1}}"
TAG_FILTER="Name=tag:ManagedBy,Values=crafting-sandbox"

ACTION="${1:-list}"
SANDBOX="${2:-}"

aws_ec2() { aws ec2 --region "$REGION" "$@"; }

sandbox_filter() {
  [[ -n "$SANDBOX" ]] && echo "Name=tag:Sandbox,Values=$SANDBOX"
}

list_instances() {
  aws_ec2 describe-instances \
    --filters $TAG_FILTER $(sandbox_filter) \
      "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].{Id:InstanceId,Sandbox:Tags[?Key==`Sandbox`]|[0].Value,State:State.Name}' \
    --output text
}

list_volumes() {
  aws_ec2 describe-volumes --filters $TAG_FILTER $(sandbox_filter) \
    --query 'Volumes[].{Id:VolumeId,Sandbox:Tags[?Key==`Sandbox`]|[0].Value,State:State}' \
    --output text
}

list_security_groups() {
  aws_ec2 describe-security-groups --filters $TAG_FILTER $(sandbox_filter) \
    --query 'SecurityGroups[].{Id:GroupId,Sandbox:Tags[?Key==`Sandbox`]|[0].Value}' \
    --output text
}

case "$ACTION" in
  list)
    echo "== instances ==";       list_instances
    echo "== data volumes ==";    list_volumes
    echo "== security groups =="; list_security_groups
    echo
    echo "Cross-check a sandbox still exists before deleting:  cs sandbox show SANDBOX_NAME"
    ;;

  delete)
    [[ -n "$SANDBOX" ]] || { echo "refusing to delete without a sandbox name" >&2; exit 2; }

    echo "== terminating instances for sandbox '$SANDBOX' =="
    ids=$(list_instances | awk '{print $1}')
    if [[ -n "$ids" ]]; then
      # shellcheck disable=SC2086
      aws_ec2 terminate-instances --instance-ids $ids \
        --query 'TerminatingInstances[].CurrentState.Name' --output text
      # shellcheck disable=SC2086
      aws_ec2 wait instance-terminated --instance-ids $ids
    else
      echo "  none"
    fi

    echo "== deleting data volumes =="
    for vol in $(list_volumes | awk '{print $1}'); do
      echo "  $vol"
      aws_ec2 delete-volume --volume-id "$vol" >/dev/null || echo "  failed: $vol"
    done

    echo "== deleting security groups =="
    # The network interface can outlive the instance briefly, holding the group.
    for sg in $(list_security_groups | awk '{print $1}'); do
      for attempt in $(seq 1 12); do
        if aws_ec2 delete-security-group --group-id "$sg" 2>/dev/null; then
          echo "  $sg deleted"; break
        fi
        echo "  $sg still in use, retry $attempt/12"; sleep 10
      done
    done

    echo "Done."
    ;;

  *)
    sed -n '3,20p' "$0"
    exit 2
    ;;
esac
