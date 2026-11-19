# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/), versions follow [SemVer](https://semver.org/).

## Unreleased

### Added
- Optional SIP over TLS: `asterisk_tls_enabled`, `asterisk_tls_cert_file`, `asterisk_tls_key_file` add a `transport-tls`
  (tcp/5061, TLS 1.2 minimum) and the matching host firewall rule; the role refuses to run if the files are missing.
  Terraform gets `sip_tls_enabled` (default `false`) for the VPC rule, with the same `0.0.0.0/0` guard as plain SIP.
  CI converges both Ubuntu versions with a throwaway certificate, and `verify.sh` does a real TLS 1.2 handshake.
- Plan promise: deleting the VM keeps the boot disk (`auto_delete = false`), and deleting the disk keeps its
  automatic snapshots (`KEEP_AUTO_SNAPSHOTS`). Both were already in `main.tf`; nothing checked them.
- Every firewall rule now has a `description` saying why it exists, and a plan promise that none is left empty.
  Someone reading the cloud console sees the intent next to the rule, not only the name.
- `docs/design-notes.md`: why the module is built the way it is, what the tests can and cannot prove, and the
  questions this design usually draws.
- `terraform/backend.tf.example`: a `gcs` backend block with the commands to create the bucket. CI copies it to
  `backend.tf` in a scratch directory and runs `terraform validate`, so the example cannot rot.
- `ROADMAP.md`: the next small steps, in order.

### Fixed
- A compiled `tests/__pycache__/*.pyc` file had been committed; it is removed and `__pycache__/` is ignored.

### Changed
- `negative.sh`: the case with empty `monitoring_source_ranges` no longer only checks that the plan is accepted; it
  also checks that the plan has no `-allow-metrics` rule (and still has the SIP rule, so an empty plan cannot pass).
- The plan check goes from 17 to 20 promises (the last: the TLS rule does not exist unless asked for), and
  `negative.sh` from nine to eleven cases.

## Before this file

There were no releases. The module had 17 plan promises, nine refused or accepted inputs, and a playbook converged on
Ubuntu 22.04 and 24.04.
