# Evidence

This file summarises the evidence I collected while investigating and hardening SSH on my Ubuntu EC2 server.

The terminal captures are stored in [`docs/captures/`](captures/).

---

## 1. System Baseline

I first recorded the system state before making any SSH changes.

The server is running Ubuntu 24.04.4 LTS. I also captured the kernel and OpenSSH version so I have a clear baseline for the project.

### Evidence

- [001-ssh-baseline.txt](captures/001-ssh-baseline.txt)

---

## 2. Initial SSH Service State

I checked the initial state of `ssh.socket`, `ssh.service` and the TCP/22 listener.

This gave me a record of how SSH was running before I changed anything.

While reviewing this capture later, I also noticed that `sshd` was started with an AWS EC2 Instance Connect `AuthorizedKeysCommand`.

The service included:

```text
AuthorizedKeysCommand /usr/share/ec2-instance-connect/eic_run_authorized_keys %u %f
AuthorizedKeysCommandUser ec2-instance-connect
```

This means local `authorized_keys` files are not the only possible public-key source on this EC2 instance.

### Evidence

- [002-ssh-service-baseline.txt](captures/002-ssh-service-baseline.txt)

---

## 3. SSH Configuration Sources

I inspected the main SSH configuration and the drop-in directory:

```text
/etc/ssh/sshd_config
/etc/ssh/sshd_config.d/
```

The instance contained:

```text
/etc/ssh/sshd_config.d/60-cloudimg-settings.conf
```

The cloud-image drop-in explicitly set:

```text
PasswordAuthentication no
```

I later inspected the complete main configuration so I could distinguish explicit configuration from values coming from OpenSSH defaults.

### Evidence

- [003-ssh-config-sources.txt](captures/003-ssh-config-sources.txt)
- [010-main-sshd-config.txt](captures/010-main-sshd-config.txt)

---

## 4. Initial Effective SSH Configuration

I recorded the effective SSH configuration using:

```bash
sudo sshd -T
```

The relevant baseline values were:

```text
logingracetime 120
maxauthtries 6
permitrootlogin without-password
pubkeyauthentication yes
passwordauthentication no
kbdinteractiveauthentication no
```

There was no explicit `AllowUsers` restriction.

I used this as the before-state for the later hardening tests.

### Evidence

- [004-ssh-effective-baseline.txt](captures/004-ssh-effective-baseline.txt)

---

## 5. Baseline Configuration Sources

I compared the `sshd -T` output with the main configuration and the drop-in files.

The investigation showed that several baseline values were OpenSSH defaults rather than hardening changes I had made.

| Effective value | Finding |
| --- | --- |
| `PasswordAuthentication no` | Explicitly set by `60-cloudimg-settings.conf` |
| `PubkeyAuthentication yes` | OpenSSH default |
| `PermitRootLogin without-password` | OpenSSH default |
| `MaxAuthTries 6` | OpenSSH default |
| `LoginGraceTime 120` | OpenSSH default |
| No `AllowUsers` restriction | No explicit user allowlist was configured |

`KbdInteractiveAuthentication no` was also present in the effective baseline. I kept the captured configuration as the source of truth rather than making a stronger source claim than the evidence supports.

### Evidence

- [003-ssh-config-sources.txt](captures/003-ssh-config-sources.txt)
- [004-ssh-effective-baseline.txt](captures/004-ssh-effective-baseline.txt)
- [010-main-sshd-config.txt](captures/010-main-sshd-config.txt)

---

## 6. Administrative User

I confirmed that the account I was using to administer the server was:

```text
ubuntu
```

This mattered later when I introduced an explicit SSH user allowlist.

### Evidence

- [005-current-admin-user.txt](captures/005-current-admin-user.txt)

---

## 7. SSH Socket Activation

I checked how SSH was listening on TCP/22.

`ssh.socket` reported:

```text
Triggers: ssh.service
Listen: 0.0.0.0:22
```

The listener also showed both `systemd` and `sshd` holding file descriptors for the same socket.

This confirmed the socket-activation model on this instance: systemd holds the bound socket and passes the file descriptor to `sshd` when the service is activated.

### Evidence

- [006-ssh-activation-model.txt](captures/006-ssh-activation-model.txt)

---

## 8. Root SSH Authorization

Before changing root access, I inspected:

```text
/root/.ssh/authorized_keys
```

The file existed and contained one persistent key.

The relevant permissions were:

```text
/root                         700 root:root
/root/.ssh                    700 root:root
/root/.ssh/authorized_keys    600 root:root
```

The key had restrictions including:

```text
no-port-forwarding
no-agent-forwarding
no-X11-forwarding
```

It also had a forced command telling the connecting user to log in as `ubuntu` instead of `root`.

### Evidence

- [007-root-ssh-authorization.txt](captures/007-root-ssh-authorization.txt)

---

## 9. Root SSH Behaviour Before Hardening

I tested a root SSH connection using the same private key I used for the `ubuntu` account.

The client displayed:

```text
Please login as the user "ubuntu" rather than the user "root".
Connection closed.
```

I did not receive an interactive root shell.

### Evidence

- [008-root-login-behaviour.txt](captures/008-root-login-behaviour.txt)

---

## 10. Server-Side Root Login Result

I checked the SSH logs after the root connection attempt.

The log showed that the public key for root was accepted.

The forced command from `/root/.ssh/authorized_keys` then ran instead of a normal root shell.

The behaviour was:

```text
root public key accepted
        ↓
per-key restrictions applied
        ↓
forced command executed
        ↓
no interactive root shell
```

This showed that `permitrootlogin without-password` did not completely disable root authentication.

### Evidence

- [009-root-login-server-log.txt](captures/009-root-login-server-log.txt)

---

## 11. EC2 Instance Connect Finding

While reviewing the original SSH service capture, I found that `sshd` was also configured with:

```text
AuthorizedKeysCommand /usr/share/ec2-instance-connect/eic_run_authorized_keys %u %f
AuthorizedKeysCommandUser ec2-instance-connect
```

This gives OpenSSH another way to obtain authorized keys through EC2 Instance Connect.

My earlier root investigation therefore describes the persistent `/root/.ssh/authorized_keys` path, but it does not describe every possible public-key source available to `sshd`.

This is important for the audit script I plan to build. A script that only checks local `authorized_keys` files could miss another authentication path.

### Evidence

- [002-ssh-service-baseline.txt](captures/002-ssh-service-baseline.txt)
- [007-root-ssh-authorization.txt](captures/007-root-ssh-authorization.txt)

---

## 12. SSH Drop-In Precedence Test

I wanted to test how conflicting SSH drop-ins were resolved on this server.

`60-cloudimg-settings.conf` contained:

```text
PasswordAuthentication no
```

I temporarily created an earlier drop-in containing:

```text
PasswordAuthentication yes
```

With both files present, `sshd -T` reported:

```text
passwordauthentication yes
```

After removing the temporary file, the result returned to:

```text
passwordauthentication no
```

I did not reload SSH during this test.

The test showed that the earlier drop-in supplied the effective value in this configuration. This was consistent with OpenSSH's documented processing behaviour.

### Evidence

- [011-ssh-dropin-precedence-test.txt](captures/011-ssh-dropin-precedence-test.txt)

---

## 13. PermitRootLogin Hardening

I created my own SSH hardening drop-in and initially added only:

```text
PermitRootLogin no
```

I kept this as a separate change so I could test its effect without mixing it with `AllowUsers`.

Before reloading SSH, I validated the configuration with:

```bash
sudo sshd -t
```

I then checked the resolved value using:

```bash
sudo sshd -T | grep '^permitrootlogin'
```

The effective value was:

```text
permitrootlogin no
```

### Evidence

- [012-permitrootlogin-pre-reload.txt](captures/012-permitrootlogin-pre-reload.txt)

---

## 14. Root Login After PermitRootLogin Hardening

After reloading SSH:

- my existing `ubuntu` session remained active;
- a fresh `ubuntu` connection succeeded;
- a fresh root connection was refused.

The previous forced-command message was no longer displayed.

The server log recorded:

```text
ROOT LOGIN REFUSED FROM <REDACTED-PUBLIC-IP> port <REDACTED> [preauth]
Connection reset by authenticating user root <REDACTED-PUBLIC-IP> [preauth]
```

The `[preauth]` marker showed that the root connection was refused before authentication completed.

This was different from the earlier test, where the root key was accepted and the forced command executed.

This confirmed that `PermitRootLogin no` moved the protection to the SSH daemon-policy layer instead of relying on the per-key forced command.

### Evidence

- [013-ubuntu-login-after-permitrootlogin.txt](captures/013-ubuntu-login-after-permitrootlogin.txt)
- [014-root-login-after-permitrootlogin.txt](captures/014-root-login-after-permitrootlogin.txt)
- [015-permitrootlogin-server-log.txt](captures/015-permitrootlogin-server-log.txt)

---

## 15. AllowUsers Test Setup

I then added:

```text
AllowUsers ubuntu
```

I wanted to test this independently rather than using root, because root was already blocked by `PermitRootLogin no`.

I created a temporary local account called:

```text
ssh-test
```

and configured it with a valid SSH public key.

Before the new `AllowUsers` configuration was loaded, I confirmed:

```text
ssh-test + valid key → SUCCESS
```

This gave me a working before-state.

### Evidence

- [016-allowusers-before-reload.txt](captures/016-allowusers-before-reload.txt)

---

## 16. AllowUsers Behaviour After Reload

After reloading SSH with:

```text
AllowUsers ubuntu
```

active:

```text
ubuntu + valid key        → SUCCESS
ssh-test + same valid key → DENIED
```

The account and key had not changed. The active SSH allowlist was the control being tested.

### Evidence

- [017-allowusers-after-reload.txt](captures/017-allowusers-after-reload.txt)

---

## 17. AllowUsers Server-Side Confirmation

I checked the SSH server logs for the rejected `ssh-test` connection.

The log recorded:

```text
User ssh-test from <REDACTED-PUBLIC-IP> not allowed because not listed in AllowUsers [preauth]
```

This directly confirmed why the account was rejected.

The `[preauth]` marker showed that the connection was denied before authentication completed.

### Evidence

- [018-allowusers-server-log.txt](captures/018-allowusers-server-log.txt)

---

## 18. Cross-Platform Repository Handling

While adding Linux-generated captures to the repository from Windows, Git warned that LF line endings could be converted to CRLF.

This matters because CRLF line endings can later break Bash scripts on Linux.

I added repository-level line-ending rules with `.gitattributes`, corrected the rules when the first version did not apply as expected, and renormalized the repository.

I verified the result using:

```bash
git ls-files --eol
```

rather than assuming the configuration had worked.

This was a preventative fix. I encountered the warning before any Bash script actually failed.

---

## Current Verified SSH State

At this stage, I have added and tested:

```text
PermitRootLogin no
AllowUsers ubuntu
```

The following controls were already present in the effective baseline and have been preserved:

```text
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
```

The next hardening changes are planned as:

```text
MaxAuthTries 3
LoginGraceTime 30
```

After that, I plan to build the Bash audit script and test it against both compliant and deliberately broken controls.

---

## Evidence Still to Add

I created `ssh-test` only for the `AllowUsers` experiment.

I will only mark its cleanup as evidenced once I capture a check confirming that the temporary account is no longer present.
