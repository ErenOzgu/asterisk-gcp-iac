# Roadmap

Small steps, in order. A step is done when CI is green, the README says what changed and the CHANGELOG has a line for
it. Steps that add behaviour also get a check in `check_plan.sh`, `negative.sh` or `verify.sh`. Each step is meant to
be a few hours of work.

- [ ] `negative.sh`: when `monitoring_source_ranges` is empty, check the plan has **no** `-allow-metrics` rule (today
      the case only checks that the plan is accepted)
- [ ] `terraform/backend.tf.example` with a `gcs` backend block, and a line in the README on creating the bucket
- [ ] TLS transport for PJSIP: a certificate path variable, a `transport-tls` section behind a switch, and a `verify.sh`
      check with `openssl s_client`
- [ ] An optional IP-authenticated trunk (`asterisk_trunks`), off by default, with a check that an unknown address is
      still refused
- [ ] A second, optional VM in another zone as a documented cold standby (restore from the snapshot), not failover
