# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/), versions follow [SemVer](https://semver.org/).

## Unreleased

### Added
- Plan promise: deleting the VM keeps the boot disk (`auto_delete = false`), and deleting the disk keeps its
  automatic snapshots (`KEEP_AUTO_SNAPSHOTS`). Both were already in `main.tf`; nothing checked them.
- Every firewall rule now has a `description` saying why it exists, and a plan promise that none is left empty.
  Someone reading the cloud console sees the intent next to the rule, not only the name.
- `docs/design-notes.md`: why the module is built the way it is, what the tests can and cannot prove, and the
  questions this design usually draws.
- `ROADMAP.md`: the next small steps, in order.

### Changed
- The plan check goes from 17 to 19 promises.

## Before this file

There were no releases. The module had 17 plan promises, nine refused or accepted inputs, and a playbook converged on
Ubuntu 22.04 and 24.04.
