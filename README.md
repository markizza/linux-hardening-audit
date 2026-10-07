# Linux Server Hardening & Security Audit

## Overview

This project documents the hardening and security auditing of an Ubuntu 24.04 server running on AWS EC2.

The first stage focuses on OpenSSH, with an emphasis on verifying the server's actual security state rather than relying only on configuration-file contents.

The project follows this workflow:

```text
Record baseline
      ↓
Write prediction
      ↓
Make controlled change
      ↓
Verify effective state
      ↓
Test behaviour
      ↓
Capture evidence
```

## Environment

* Ubuntu 24.04.4 LTS
* AWS EC2
* OpenSSH
* systemd
* Bash
* Git / GitHub
* VS Code

## Current SSH Baseline

The effective OpenSSH configuration was checked using:

```bash
sudo sshd -T
```

Baseline values:

```text
logingracetime 120
maxauthtries 6
permitrootlogin without-password
pubkeyauthentication yes
passwordauthentication no
kbdinteractiveauthentication no
```

This showed that some SSH security controls were already enabled before any hardening changes were made.

## SSH Activation Model

The server uses systemd socket activation for OpenSSH.

The `ssh.socket` unit reported:

```text
Triggers: ssh.service
Listen: 0.0.0.0:22
```

The TCP/22 listener was also associated with both `systemd` and the running `sshd` process.

This confirmed that `ssh.socket` manages the listening socket and triggers `ssh.service`.

## Why `sshd -T`?

OpenSSH settings can come from multiple configuration sources, including:

```text
/etc/ssh/sshd_config
/etc/ssh/sshd_config.d/*.conf
```

Because of this, reading only `/etc/ssh/sshd_config` may not show the configuration actually being enforced.

This project uses:

```bash
sudo sshd -T
```

to inspect the daemon's effective configuration.

The server currently contains the SSH drop-in file:

```text
/etc/ssh/sshd_config.d/60-cloudimg-settings.conf
```

Its relationship with the main SSH configuration is still being investigated.

## Project Method

For each major change:

1. Record the current state.
2. Write a prediction.
3. Make one controlled change.
4. Validate the SSH configuration.
5. Check the effective configuration.
6. Test actual SSH behaviour.
7. Capture evidence.
8. Document the result.

## Repository Structure

```text
linux-hardening-audit/
├── README.md
├── .gitignore
└── docs/
    ├── evidence.md
    ├── troubleshooting-log.md
    ├── captures/
    └── images/
```

* `evidence.md` — explains tests and results.
* `troubleshooting-log.md` — records predictions, investigations and lessons learned.
* `captures/` — contains redacted terminal evidence.
* `images/` — contains selected screenshots where useful.

## Evidence Workflow

Evidence is generated on the EC2 instance and transferred to the local machine using SCP.

Before entering the Git repository, captured files are reviewed and redacted where necessary.

Sensitive information such as public IP addresses, AWS account identifiers and credentials is not committed to the repository.

## SSH Safety Plan

Before making SSH configuration changes:

* Keep the current SSH session open.
* Confirm that a second SSH connection works.
* Validate SSH configuration before reloading.
* Check the effective configuration after changes.
* Test a fresh connection before closing the original session.
* Make one controlled change at a time.

## Controls Under Review

The current SSH review includes:

* `PermitRootLogin`
* `PasswordAuthentication`
* `KbdInteractiveAuthentication`
* `PubkeyAuthentication`
* `AllowUsers`
* `MaxAuthTries`
* `LoginGraceTime`

## Planned Audit Script

A Bash audit script will later be developed to check defined host security controls and return PASS or FAIL results.

The script will be tested against both compliant and deliberately broken controls:

```text
Correct configuration → PASS
Broken configuration  → FAIL
Restored configuration → PASS
```

## Status

### Completed

* Ubuntu 24.04.4 LTS baseline captured
* SSH effective configuration captured using `sshd -T`
* SSH socket activation confirmed
* TCP/22 listener verified
* SSH drop-in directory identified
* `60-cloudimg-settings.conf` identified
* Evidence transferred from EC2 using SCP
* Evidence reviewed and redacted locally before committing

### In Progress

* SSH configuration-source investigation
* Root SSH authorization investigation
* SSH hardening
* Behavioural SSH testing
* Bash security audit script
