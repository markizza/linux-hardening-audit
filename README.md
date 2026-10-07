# Linux Server Hardening & Security Audit

## Overview

I am using an Ubuntu 24.04 server on AWS EC2 to practise Linux hardening and security auditing.

I started with OpenSSH because SSH is the main administrative entry point to the server. Rather than only editing configuration files, I am checking the effective configuration and testing how the server actually behaves after each change.

My general workflow is:

```text
Record baseline
      ↓
Write prediction
      ↓
Make controlled change
      ↓
Validate configuration
      ↓
Check effective state
      ↓
Test behaviour
      ↓
Capture evidence
```

## Environment

- Ubuntu 24.04.4 LTS
- AWS EC2
- OpenSSH
- systemd
- Bash
- Git / GitHub
- VS Code

## Initial SSH Baseline

I recorded the effective OpenSSH configuration using:

```bash
sudo sshd -T
```

The initial values included:

```text
logingracetime 120
maxauthtries 6
permitrootlogin without-password
pubkeyauthentication yes
passwordauthentication no
kbdinteractiveauthentication no
```

There was no explicit `AllowUsers` restriction.

This gave me a baseline to compare against as I hardened the server.

## Configuration Sources

I checked both:

```text
/etc/ssh/sshd_config
/etc/ssh/sshd_config.d/
```

The EC2 image contained:

```text
/etc/ssh/sshd_config.d/60-cloudimg-settings.conf
```

which explicitly set:

```text
PasswordAuthentication no
```

I also tested SSH drop-in precedence by deliberately creating two conflicting `PasswordAuthentication` values.

The earlier drop-in value was reported by `sshd -T`, and removing the temporary file restored the original value.

This confirmed the precedence behaviour on my own server rather than only relying on documentation.

## Why I Use `sshd -T`

I use:

```bash
sudo sshd -T
```

to check the effective SSH configuration.

A configuration file shows what has been written, while `sshd -T` shows how OpenSSH resolves the available configuration.

I use this distinction throughout the project when checking security controls.

## SSH Activation Model

I confirmed that OpenSSH is using systemd socket activation.

`ssh.socket` reported:

```text
Triggers: ssh.service
Listen: 0.0.0.0:22
```

The TCP/22 listener showed both `systemd` and `sshd` holding file descriptors for the same listening socket.

This showed that systemd creates and holds the socket and passes it to `sshd` when the service is activated.

## Root SSH Investigation

Before changing root access, I checked `/root/.ssh/authorized_keys`.

The root account had one authorized key with restrictions including:

```text
no-port-forwarding
no-agent-forwarding
no-X11-forwarding
```

It also contained a forced command telling the user to log in as `ubuntu` instead of `root`.

I tested this behaviour before hardening.

The root public key was accepted, but the forced command ran instead of an interactive root shell being provided.

This showed me that:

```text
PermitRootLogin without-password
```

did not mean unrestricted root shell access, but it also did not completely disable root authentication.

## SSH Hardening

I am applying the controls one at a time so that I can tell which change caused each result.

### Disable Direct Root Login

I added:

```text
PermitRootLogin no
```

to my SSH hardening drop-in.

Before reloading SSH, I validated the configuration with:

```bash
sudo sshd -t
```

and checked the effective state with:

```bash
sudo sshd -T
```

After the reload:

- my existing `ubuntu` session remained active;
- a fresh `ubuntu` connection succeeded;
- a new root SSH connection was refused;
- the previous root forced-command message was no longer reached.

This moved root access control from a per-key restriction to an explicit SSH daemon policy.

### Restrict SSH Users

I then added:

```text
AllowUsers ubuntu
```

To test this separately, I created a temporary `ssh-test` account and gave it a valid SSH key.

Before the new configuration was loaded:

```text
ssh-test + valid key → SUCCESS
```

After reloading SSH with `AllowUsers ubuntu`:

```text
ssh-test + same valid key → DENIED
ubuntu + valid key        → SUCCESS
```

I removed the temporary account after testing.

This confirmed that the SSH allowlist was being enforced independently of whether the account had a valid key.

## Evidence Workflow

I generate evidence on the EC2 instance and transfer it to my local Windows machine using SCP.

Before committing evidence, I review and redact information such as:

- public IP addresses;
- AWS account information;
- credentials;
- key material.

Terminal captures are stored in:

```text
docs/captures/
```

I also added `.gitattributes` after Git warned that Linux LF line endings could be converted to Windows CRLF.

I verified the rule using:

```bash
git ls-files --eol
```

rather than assuming it had been applied.

## Repository Structure

```text
linux-hardening-audit/
├── README.md
├── .gitattributes
├── .gitignore
└── docs/
    ├── evidence.md
    ├── troubleshooting-log.md
    ├── captures/
    └── images/
```

- `evidence.md` explains the tests and points to the supporting captures.
- `troubleshooting-log.md` records my predictions, results and lessons.
- `captures/` contains redacted terminal evidence.
- `images/` is reserved for screenshots where they add value.

## Current Hardening State

The controls I have completed so far are:

```text
PermitRootLogin no
AllowUsers ubuntu
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
```

`PermitRootLogin no` and `AllowUsers ubuntu` were added and tested during this project.

The authentication settings were already part of the effective baseline and were preserved.

## Next Steps

Next I plan to:

- reduce `MaxAuthTries` from `6` to `3`;
- reduce `LoginGraceTime` from `120` to `30`;
- build a Bash security audit script;
- make the script report PASS/FAIL for defined controls;
- deliberately break one control and confirm the script detects it;
- restore the control and confirm the script returns to PASS.

## Status

### Completed

- Ubuntu 24.04.4 baseline captured
- Effective SSH baseline recorded with `sshd -T`
- SSH configuration sources inspected
- SSH drop-in precedence tested
- systemd socket activation verified
- Root SSH authorization behaviour investigated
- `PermitRootLogin no` applied and behaviourally tested
- `AllowUsers ubuntu` applied and behaviourally tested
- Evidence transfer and redaction workflow established
- Repository line-ending handling configured and verified

### In Progress

- `MaxAuthTries` and `LoginGraceTime` hardening
- Bash security audit script
- Deliberate control-failure testing
