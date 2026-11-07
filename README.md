# Linux Server Hardening & Security Audit

## Overview

I am using an Ubuntu 24.04 server on AWS EC2 to practise Linux hardening and security auditing.

I started with OpenSSH because SSH is the main administrative entry point to the server.

Rather than only changing configuration files, I am checking the effective configuration and then testing how the server actually behaves.

My workflow is:

```text
Record baseline
      ↓
Write prediction
      ↓
Make one controlled change
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

Most of the baseline values came from OpenSSH defaults rather than hardening changes I had made.

The cloud-image drop-in explicitly set:

```text
PasswordAuthentication no
```

## Configuration Sources

I inspected both:

```text
/etc/ssh/sshd_config
/etc/ssh/sshd_config.d/
```

The instance contained:

```text
/etc/ssh/sshd_config.d/60-cloudimg-settings.conf
```

I also tested how conflicting drop-in files were resolved.

I temporarily created an earlier drop-in containing:

```text
PasswordAuthentication yes
```

while `60-cloudimg-settings.conf` contained:

```text
PasswordAuthentication no
```

With both files present, `sshd -T` reported:

```text
passwordauthentication yes
```

After removing the temporary file, the effective value returned to:

```text
passwordauthentication no
```

This confirmed the precedence behaviour on my server instead of relying only on documentation.

## Why I Use `sshd -T`

I use:

```bash
sudo sshd -T
```

to inspect the effective SSH configuration.

A configuration file shows what has been written, while `sshd -T` shows how OpenSSH resolves the available configuration.

I use this distinction throughout the project when checking SSH controls.

## SSH Activation Model

I confirmed that OpenSSH is using systemd socket activation.

`ssh.socket` reported:

```text
Triggers: ssh.service
Listen: 0.0.0.0:22
```

The TCP/22 listener showed both `systemd` and `sshd` holding file descriptors for the same listening socket.

This showed that systemd holds the bound socket and passes the file descriptor to `sshd` when the service is activated.

Both processes therefore reference the same listening socket rather than independently binding to TCP/22.

## Root SSH Investigation

Before changing root access, I inspected:

```text
/root/.ssh/authorized_keys
```

The root account had one persistent authorized key with restrictions including:

```text
no-port-forwarding
no-agent-forwarding
no-X11-forwarding
```

It also contained a forced command telling the user to log in as `ubuntu` instead of `root`.

I then tested the behaviour.

The root public key was accepted, but the forced command ran instead of an interactive root shell being provided.

This showed that:

```text
PermitRootLogin without-password
```

did not completely disable root authentication.

### Additional Key Source

While reviewing the SSH service configuration, I also found that `sshd` was started with an AWS EC2 Instance Connect `AuthorizedKeysCommand`.

The service included:

```text
AuthorizedKeysCommand /usr/share/ec2-instance-connect/eic_run_authorized_keys %u %f
AuthorizedKeysCommandUser ec2-instance-connect
```

This means `authorized_keys` files are not the only possible public-key source on this EC2 instance.

My root `authorized_keys` investigation therefore describes the persistent root key configuration, but not every possible key source available to `sshd`.

This is also something I need to account for when I build the audit script.

## SSH Hardening

I am applying controls separately where possible so that I can tell which change caused each result.

### Disable Direct Root Login

I added:

```text
PermitRootLogin no
```

to my own SSH hardening drop-in.

Before reloading SSH, I validated the configuration with:

```bash
sudo sshd -t
```

and checked the effective value with:

```bash
sudo sshd -T
```

After the reload:

- my existing `ubuntu` session remained active;
- a fresh `ubuntu` connection succeeded;
- a new root connection was refused;
- the previous forced-command message was no longer displayed.

The server log recorded the root connection as refused before authentication completed:

```text
ROOT LOGIN REFUSED FROM <REDACTED-PUBLIC-IP> port <REDACTED> [preauth]
Connection reset by authenticating user root <REDACTED-PUBLIC-IP> [preauth]
```

The `[preauth]` marker helped confirm that the rejection happened before the public key was accepted.

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

The server log showed:

```text
User ssh-test from <REDACTED-PUBLIC-IP> not allowed because not listed in AllowUsers [preauth]
```

This confirmed that the test account was rejected by the `AllowUsers` policy before authentication completed.

## Evidence Workflow

I generate terminal evidence on the EC2 instance and transfer it to my local Windows machine using SCP.

I review the captures locally and redact sensitive or unnecessary information before committing them.

The captures are stored in:

```text
docs/captures/
```

I also added `.gitattributes` after Git warned that Linux LF line endings could be changed to Windows CRLF.

I corrected the repository rules, renormalized the files, and verified the result using:

```bash
git ls-files --eol
```

This was preventative. I caught the line-ending issue before it caused a Bash script failure.

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

- [Evidence log](docs/evidence.md) — explains the tests and supporting captures.
- [Troubleshooting log](docs/troubleshooting-log.md) — records my predictions, results and corrections.
- `docs/captures/` — contains redacted terminal evidence.
- `docs/images/` — reserved for screenshots where they add value.

## Current Verified SSH State

The controls I have added and behaviourally tested are:

```text
PermitRootLogin no
AllowUsers ubuntu
```

The following were already part of the effective baseline and have been preserved:

```text
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
```

## Bash SSH Hardening Audit

I built a Bash audit script that evaluates the effective OpenSSH configuration using `sshd -T`.

The script checks:

```text
PermitRootLogin
PasswordAuthentication
KbdInteractiveAuthentication
PubkeyAuthentication
AllowUsers
MaxAuthTries
LoginGraceTime
```

It also reports `AuthorizedKeysCommand` information without automatically treating it as a failure.

The script uses these exit codes:

```text
0 = all required controls passed
1 = one or more security controls failed
2 = audit or configuration error
```

### Failure Testing

I first ran the script against the hardened server:

```text
PASS: 8
FAIL: 0
Result: PASSED
```

I then deliberately changed:

```text
MaxAuthTries 3
```

to:

```text
MaxAuthTries 6
```

The audit detected the change:

```text
[FAIL] MaxAuthTries = 6 (required: <= 3)
Result: FAILED
```

After restoring `MaxAuthTries 3`, the audit returned to:

```text
Result: PASSED
```

This demonstrated that the audit could detect a deliberately introduced configuration failure rather than only reporting the expected state.

## Project Status

**Complete**

The project now includes:

- SSH baseline and configuration-source investigation
- systemd SSH socket-activation investigation
- root SSH behaviour analysis
- `PermitRootLogin no` hardening
- `AllowUsers ubuntu` hardening and behavioural testing
- `MaxAuthTries 3` and `LoginGraceTime 30`
- Bash SSH hardening audit script
- PASS/FAIL reporting
- meaningful exit codes
- deliberate control-failure testing
- control restoration and final PASS verification
- documented evidence and troubleshooting
