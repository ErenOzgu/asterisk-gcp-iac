#!/usr/bin/env bash
# Plans that must be refused. Run from the terraform directory after `terraform init`:
#
#   tests/negative.sh
#
# Every case supplies a bad input on top of tests/ci.tfvars and expects the plan
# to fail with the module's own error message, not with something unrelated.
set -uo pipefail

tf="${TERRAFORM:-terraform}"
failed=0

plan() { # plan [terraform plan arguments]
  GOOGLE_OAUTH_ACCESS_TOKEN=plan-only-token "$tf" plan -input=false -lock=false -no-color -var-file=tests/ci.tfvars "$@" 2>&1
}

expect_refused() { # expect_refused "description" "message fragment" [plan arguments]
  local desc="$1" fragment="$2" out
  shift 2
  if out="$(plan "$@")"; then
    echo "[FAIL] $desc: the plan was accepted"
    failed=1
  elif tr -d '│' <<<"$out" | tr '\n' ' ' | tr -s ' ' | grep -qF -- "$fragment"; then # error text wraps across lines
    echo "[PASS] $desc"
  else
    echo "[FAIL] $desc: refused, but not with the expected message"
    echo "$out" | tail -15
    failed=1
  fi
}

expect_accepted() { # expect_accepted "description" [plan arguments]
  local desc="$1" out
  shift
  if out="$(plan "$@")"; then
    echo "[PASS] $desc"
  else
    echo "[FAIL] $desc"
    echo "$out" | tail -15
    failed=1
  fi
}

expect_refused "SIP open to the internet" "exposes SIP to the whole internet" -var 'sip_source_ranges=["0.0.0.0/0"]'
expect_accepted "SIP open to the internet when acknowledged" -var 'sip_source_ranges=["0.0.0.0/0"]' -var allow_open_sip=true
expect_refused "RTP open to the internet" "exposes the media ports to the whole internet" -var 'rtp_source_ranges=["0.0.0.0/0"]'
expect_refused "SSH open to the internet" "SSH is meant to be reached through IAP" -var 'ssh_source_ranges=["0.0.0.0/0"]'
expect_refused "no SIP sources at all" "sip_source_ranges needs at least one" -var 'sip_source_ranges=[]'
expect_refused "a malformed CIDR range" "sip_source_ranges needs at least one valid" -var 'sip_source_ranges=["198.51.100.300/24"]'
expect_refused "an admin without a member prefix" "must start with user:, group: or serviceAccount:" -var 'admin_members=["admin@example.com"]'
expect_refused "a bad project ID" "valid GCP project ID" -var 'project_id=My_Project'
expect_accepted "the monitoring rule disappears when no ranges are given" -var 'monitoring_source_ranges=[]'

exit "$failed"
