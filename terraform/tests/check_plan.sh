#!/usr/bin/env bash
# Policy checks on a Terraform plan in JSON form:
#
#   terraform show -json tfplan > plan.json && tests/check_plan.sh plan.json
#
# These are the properties the module promises. If a change breaks one, CI fails.
set -euo pipefail

plan="${1:?usage: check_plan.sh plan.json}"
failed=0

check() { # check "description" jq-filter
  if jq -e "$2" "$plan" >/dev/null; then
    echo "[PASS] $1"
  else
    echo "[FAIL] $1"
    failed=1
  fi
}

rules='[.resource_changes[] | select(.type == "google_compute_firewall") | .change.after]'
instance='.resource_changes[] | select(.type == "google_compute_instance") | .change.after'

check "the plan only creates resources" \
  '[.resource_changes[] | select(.change.actions != ["create"])] | length == 0'
check "every firewall rule says why it exists" \
  "$rules | map(select((.description // \"\") == \"\")) | length == 0"
check "no rule that allows traffic is open to 0.0.0.0/0" \
  "$rules | map(select((.allow // []) | length > 0) | select((.source_ranges // []) | index(\"0.0.0.0/0\"))) | length == 0"
check "every allow rule is scoped to the PBX's network tag" \
  "$rules | map(select((.allow // []) | length > 0) | select((.target_tags // []) | length == 0)) | length == 0"
check "every firewall rule logs" \
  "$rules | map(select(.log_config == null or (.log_config | length) == 0)) | length == 0"
check "SSH is reachable from the IAP range only" \
  "$rules | map(select((.allow // []) | map(.ports // []) | flatten | index(\"22\"))) | map(.source_ranges) == [[\"35.235.240.0/20\"]]"
check "SIP is a single UDP port" \
  "$rules | map(select(.name | endswith(\"-allow-sip\"))) | .[0].allow == [{\"ports\": [\"5060\"], \"protocol\": \"udp\"}]"
check "the metrics ports are only open to the monitoring ranges" \
  "$rules | map(select(.name | endswith(\"-allow-metrics\"))) | .[0] | .source_ranges == [\"10.20.0.5/32\"] and (.allow[0].ports | sort) == [\"9100\", \"9650\"]"
check "a logging deny-all rule closes everything else" \
  "$rules | map(select(.name | endswith(\"-deny-all-ingress\"))) | .[0] | .priority == 65000 and .direction == \"INGRESS\""
check "the VM is a shielded VM" \
  "$instance | .shielded_instance_config[0] | .enable_secure_boot and .enable_vtpm and .enable_integrity_monitoring"
check "OS Login is on and project-wide SSH keys are blocked" \
  "$instance | .metadata | .\"enable-oslogin\" == \"TRUE\" and .\"block-project-ssh-keys\" == \"TRUE\" and .\"serial-port-enable\" == \"FALSE\""
check "the VM is protected against deletion by default" \
  "$instance | .deletion_protection == true"
check "the VM cannot forward packets" \
  "$instance | .can_ip_forward == false"
check "exactly one public address exists" \
  '[.resource_changes[] | select(.type == "google_compute_address")] | length == 1'
check "the subnet writes flow logs" \
  '.resource_changes[] | select(.type == "google_compute_subnetwork") | .change.after.log_config | length == 1'
# shellcheck disable=SC2016 # $p is a jq variable, not a shell one
check "the VM has a dedicated service account that gets no project roles" \
  '. as $p
   | ([$p.resource_changes[] | select(.type == "google_service_account")] | length == 1)
     and ([$p.resource_changes[] | select(.type == "google_project_iam_member" or .type == "google_project_iam_binding")] | length == 0)'
check "the boot disk is snapshotted daily and kept for a week" \
  '.resource_changes[] | select(.type == "google_compute_resource_policy") | .change.after.snapshot_schedule_policy[0] | .schedule[0].daily_schedule[0].days_in_cycle == 1 and .retention_policy[0].max_retention_days == 7'
check "deleting the VM keeps the boot disk, and deleting the disk keeps its snapshots" \
  '([.resource_changes[] | select(.type == "google_compute_instance") | .change.after.boot_disk[0].auto_delete] == [false])
   and ([.resource_changes[] | select(.type == "google_compute_resource_policy") | .change.after.snapshot_schedule_policy[0].retention_policy[0].on_source_disk_delete] == ["KEEP_AUTO_SNAPSHOTS"])'
check "each admin gets OS Login, an IAP tunnel and the right to act as the VM account" \
  '[.resource_changes[] | select(.type == "google_compute_instance_iam_member" or .type == "google_iap_tunnel_instance_iam_member" or .type == "google_service_account_iam_member")] | length == 3'

exit "$failed"
