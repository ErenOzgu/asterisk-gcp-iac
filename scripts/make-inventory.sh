#!/usr/bin/env bash
# Writes ansible/inventory/hosts.ini from the Terraform outputs, so Ansible can
# reach the VM through an IAP tunnel with OS Login.
#
#   scripts/make-inventory.sh
#
# Needs: terraform (applied), jq, and gcloud logged in as an admin_members user.
# For tests: TF_OUTPUT_JSON overrides `terraform output -json` and OS_LOGIN_USER
# overrides the gcloud lookup.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tf_json="${TF_OUTPUT_JSON:-$(terraform -chdir="$root/terraform" output -json)}"

out() { jq -er --arg k "$1" '.[$k].value' <<<"$tf_json" || { echo "Terraform output '$1' is missing: has 'terraform apply' run?" >&2; exit 1; }; }

os_login_user="${OS_LOGIN_USER:-$(gcloud compute os-login describe-profile --format='value(posixAccounts[0].username)')}"
[[ -n "$os_login_user" ]] || { echo "No OS Login profile found: run 'gcloud auth login' as one of the admin_members." >&2; exit 1; }

dest="$root/ansible/inventory/hosts.ini"
sed \
  -e "s|@NAME@|$(out instance_name)|g" \
  -e "s|@ZONE@|$(out zone)|g" \
  -e "s|@PROJECT@|$(out project_id)|g" \
  -e "s|@OS_LOGIN_USER@|${os_login_user}|g" \
  -e "s|@EXTERNAL_IP@|$(out external_ip)|g" \
  -e "s|@SUBNET_CIDR@|$(out subnet_cidr)|g" \
  "$root/ansible/inventory/hosts.ini.tpl" >"$dest"

echo "wrote $dest"
