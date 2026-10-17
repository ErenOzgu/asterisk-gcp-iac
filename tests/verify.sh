#!/usr/bin/env bash
# Checks a converged host. Run as root on the machine the playbook configured:
#
#   sudo -E tests/verify.sh
#
# EP101_PASSWORD must hold the password given to extension 101 in the playbook.
set -uo pipefail

: "${EP101_PASSWORD:?set EP101_PASSWORD}"
here="$(cd "$(dirname "$0")" && pwd)"
pass=0
fail=0
phone_pid=""
trap '[ -n "$phone_pid" ] && kill "$phone_pid" 2>/dev/null' EXIT

check() { # check "description" command...
  local desc="$1" out
  shift
  if out="$("$@" 2>&1)"; then
    echo "[PASS] $desc"
    pass=$((pass + 1))
  else
    echo "[FAIL] $desc"
    [ -n "$out" ] && echo "$out" | tail -n 4 | sed 's/^/         /'
    fail=$((fail + 1))
  fi
}
contains() { grep -q -- "$1" <<<"$2"; }
lacks() { ! grep -q -- "$1" <<<"$2"; }
at_least() { [ "$(grep -c -- "$2" <<<"$3")" -ge "$1" ]; } # at_least N pattern text
ast() { asterisk -rx "$1"; }

units="asterisk fail2ban nftables asterisk-exporter prometheus-node-exporter"
for unit in $units; do
  check "service $unit is active" systemctl is-active --quiet "$unit"
  check "service $unit starts at boot" systemctl is-enabled --quiet "$unit"
done

echo "# Asterisk"
endpoints="$(ast 'pjsip show endpoints')"
check "extension 101 exists" contains 'Endpoint:  101/' "$endpoints"
check "extension 102 exists" contains 'Endpoint:  102/' "$endpoints"
check "chan_sip is not loaded" contains '0 modules loaded' "$(ast 'module show like chan_sip')"
check "the dialplan has the echo test" contains '600' "$(ast 'dialplan show internal')"
check "extension 101 registers with its password" python3 "$here/sip_register.py" --user 101 --password "$EP101_PASSWORD"
check "extension 101 is refused with a wrong password" bash -c "! python3 '$here/sip_register.py' --user 101 --password wrong-wrong-wrong-wrong"
check "an unknown extension is refused" bash -c "! python3 '$here/sip_register.py' --user 999 --password wrong-wrong-wrong-wrong"
listeners="$(ss -ltnH 2>/dev/null)"
check "AMI listens on localhost only" bash -c "grep -q '127.0.0.1:5038' <<<'$listeners' && [ \"\$(grep -c ':5038' <<<'$listeners')\" = 1 ]"
check "pjsip.conf is readable by asterisk only" bash -c "[ \"\$(stat -c '%a %U %G' /etc/asterisk/pjsip.conf)\" = '640 root asterisk' ]"

echo "# fail2ban"
for _ in $(seq 1 20); do fail2ban-client status asterisk >/dev/null 2>&1 && break; sleep 1; done # jails load a few seconds after a restart
check "the security log records the failed logins" grep -q 'ChallengeResponseFailed\|InvalidAccountID' /var/log/asterisk/security_log
matches="$(fail2ban-regex /var/log/asterisk/security_log asterisk 2>&1 | sed -n 's/^Failregex: \([0-9]*\) total.*/\1/p')"
check "fail2ban's asterisk filter matches those lines (matched: ${matches:-0})" test "${matches:-0}" -ge 1
check "the asterisk jail watches the security log" contains 'security_log' "$(fail2ban-client status asterisk 2>&1)"
check "the sshd jail is off (IAP addresses must never be banned)" bash -c "! fail2ban-client status sshd"
# A real ban end to end: fail2ban -> nftables.
fail2ban-client set asterisk banip 192.0.2.77 >/dev/null 2>&1
check "a banned address reaches the packet filter" bash -c "nft list ruleset | grep -q 192.0.2.77"
fail2ban-client set asterisk unbanip 192.0.2.77 >/dev/null 2>&1

echo "# firewall"
rules="$(nft list table inet asterisk_fw 2>&1)"
check "the host firewall drops by default" contains 'policy drop' "$rules"
check "SIP is open to the listed sources" contains 'udp dport 5060' "$rules"
check "RTP is open to the listed sources" contains 'udp dport 10000-20000' "$rules"
check "nothing is open to the whole internet" lacks '0.0.0.0/0' "$rules"

if [ -x /usr/sbin/sshd ]; then
  echo "# ssh"
  check "sshd refuses passwords" bash -c "sshd -T 2>/dev/null | grep -qi '^passwordauthentication no'"
  check "sshd refuses root logins" bash -c "sshd -T 2>/dev/null | grep -qi '^permitrootlogin no'"
fi

echo "# monitoring"
# A phone that stays registered and answers Asterisk's qualify pings.
python3 "$here/sip_register.py" --user 101 --password "$EP101_PASSWORD" --stay --port 5099 >/dev/null 2>&1 &
phone_pid=$!
for _ in $(seq 1 30); do ast 'pjsip show contacts' | grep -q 'Avail' && break; sleep 1; done
check "the phone shows up as reachable in Asterisk" contains 'Avail' "$(ast 'pjsip show contacts')"
sleep 2
metrics="$(curl -fsS http://127.0.0.1:9650/metrics 2>&1)"
check "the exporter reports Asterisk up" contains '^asterisk_up 1' "$metrics"
check "the exporter lists both extensions" at_least 2 '^asterisk_pjsip_endpoint_up{' "$metrics"
check "the exporter sees extension 101 as up" contains '^asterisk_pjsip_endpoint_up{endpoint="101"} 1' "$metrics"
check "the exporter counts the reachable contact" contains '^asterisk_pjsip_contacts{status="reachable"} 1' "$metrics"
check "every collector succeeds" lacks '^asterisk_collector_success{.*} 0' "$metrics"
check "node_exporter answers" bash -c "curl -fsS http://127.0.0.1:9100/metrics | grep -q '^node_cpu_seconds_total'"
check "the exporter's credentials are private to root" bash -c "[ \"\$(stat -c '%a %U' /etc/asterisk-exporter.env)\" = '600 root' ]"
check "the exporter is the pinned release" bash -c "/usr/local/bin/asterisk-exporter -version | grep -q 'v0.1.0'"

echo
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
