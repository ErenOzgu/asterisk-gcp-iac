# Design notes

Why asterisk-gcp-iac is built the way it is. The README says what you get; this says what was decided, what was
rejected, and what the tests can and cannot prove.

## The problem in one paragraph

A small Asterisk PBX on a public address is scanned within hours. The usual ways it goes wrong are a firewall rule
copied from a tutorial (`0.0.0.0/0`), an SSH key file nobody remembers, a service account with more rights than the
machine needs, and a configuration that was fixed by hand once and can no longer be rebuilt. The aim is a PBX where
the cloud side and the machine side are both code, and where the properties that matter are checked on every push.

## Decisions

### Two tools, one boundary

Terraform builds what Google Cloud owns: network, firewall rules, address, VM, service account, snapshots, IAM.
Ansible configures what is inside the VM: Asterisk, the host firewall, fail2ban, the exporters. The boundary is the
operating system. Putting a startup script in Terraform would have made one tool do both jobs, and it would have run
once, at first boot, and never again; Ansible can be run again, and a second run that reports `changed=0` is a test.

### SSH through IAP and OS Login, no key files

SSH is reachable only from Google's IAP range (`35.235.240.0/20`), and logging in is an IAM grant, not a file on the
VM. Project-wide SSH keys are blocked and the serial console is off. Adding an admin is one entry in `admin_members`;
removing one is removing it. The price is that the first login needs `gcloud`, and that the Ansible inventory has to
go through the tunnel (`make inventory`).

### The VM's service account has no roles

Nothing on the PBX needs to call a Google API, so the account has none, and a test makes sure none appear
(`google_project_iam_member` and `google_project_iam_binding` must be absent from the plan). If the PBX is taken over,
the attacker gets a machine, not a project. Admins are granted three narrow things instead: OS Login, an IAP tunnel
and the right to act as that account, which is what reaching a VM that has a service account requires.

### Two firewalls that say the same thing

The VPC has rules scoped to the PBX's network tag, all logging, ending in a deny-all. The host has `nftables` with
default drop and the same source lists. The second layer is there for the day someone edits one of them wrongly:
a mistake in one is not an open port. The cost is that the lists exist twice (`sip_source_ranges` and
`firewall_sip_sources`).

### SIP source ranges have no default

`sip_source_ranges` is required, and `0.0.0.0/0` is refused unless `allow_open_sip = true` is set in the same
file. A default would be a decision made for you, and the usual default is the dangerous one. The refusal message
names the variable and the way out.

### The SSH jail is off in fail2ban

Every admin login arrives from IAP's addresses, so a few typos would ban everyone. SSH is protected by IAP and OS
Login instead. This is written down in the README because it looks like an oversight if you do not know why.

### Local state

Terraform state is local. It is a one-VM example and a backend needs a bucket that has to exist first. The README
says so under Limits, with the line to add.

## How it was checked

* `terraform plan` without credentials (a made-up access token and throwaway values in `tests/ci.tfvars`), turned into
  JSON and checked against 19 promises in `tests/check_plan.sh`. Each promise is a short `jq` filter, so a reviewer can
  read what is promised in one screen.
* Nine inputs in `tests/negative.sh`: seven must be refused **with the module's own message**, two (an acknowledged
  open SIP range, no monitoring ranges) must still be accepted. Checking the message matters: a plan that fails for an
  unrelated reason would otherwise count as a pass.
* The Ansible playbook is run for real on Ubuntu 22.04 and 24.04 runners, then `tests/verify.sh` registers an
  extension with a digest login, sends a wrong password and an unknown extension, and checks that the refusals reach
  the security log, match fail2ban's filter and end in a ban in the packet filter. Then the playbook runs again and has
  to change nothing.
* `ansible-lint` (production profile), `yamllint`, `shellcheck`, `tflint` and Checkov. Where Checkov is overruled, the
  reason is written next to the resource.

The checks that found real faults are listed in the README ("Things the tests caught"): fail2ban on Ubuntu 24.04
watching nothing, `sshd -t` needing `/run/sshd`, and a Terraform resource that does not exist.

## What the tests cannot do

`terraform apply` against a real project, and running the playbook on a Compute Engine VM. The runner is an Ubuntu VM,
not a GCE instance, so OS Login and the IAP tunnel are covered by the design and the documentation, not by a test.
A plan policy test also cannot see what the cloud adds on its own: it checks the plan, not the result.

## What would be changed next

See [ROADMAP.md](../ROADMAP.md). The first item for a real deployment would be a remote state backend; the first item for
a real PBX is TLS for SIP.

## Questions this design usually draws

**Why Terraform and Ansible, not just one?** The cloud objects and the operating system have different lifecycles.
Ansible can be run again and again on a living machine; Terraform should not rebuild a VM to change a config file.

**Why test the plan and not the infrastructure?** The plan is available on every push, without credentials or a bill.
It cannot prove the cloud behaves as the plan says, but it catches the change that would have been wrong.

**Is `0.0.0.0/0` ever acceptable?** For SIP, when the trunk provider will not tell you its ranges. The variable
exists for that, and has to be set on purpose.

**What happens if the VM is deleted?** Deletion protection is on by default. The boot disk is a separate resource that
is kept when the VM goes, and its snapshots are kept when the disk goes.

**Why is the boot disk not encrypted with my own key?** Google-managed encryption is on. A customer-supplied key would
have to be entered at every start, which puts the PBX's availability in the hands of whoever holds the key. The Checkov
exception says this next to the disk.

**Is this production-ready?** It is a sound starting point for one PBX. It has one VM, no failover and no trunk
configuration; the README's Limits say so.

## Three-minute demo

No Google account is needed for the first part.

```sh
cd terraform
terraform init -backend=false
GOOGLE_OAUTH_ACCESS_TOKEN=plan-only-token terraform plan -var-file=tests/ci.tfvars -out=tfplan
terraform show -json tfplan > plan.json
tests/check_plan.sh plan.json     # 19 promises about the plan
tests/negative.sh                 # inputs that must be refused, with the module's own message
```

Then open `tests/check_plan.sh` and change one thing, for example `can_ip_forward = true` in `main.tf`, and run the plan
check again to see the matching promise fail. What to say: nothing is created, nothing needs credentials, and the file
that lists what the module promises is shorter than a page.
