# Evidence

This file summarises the evidence I collected while investigating and hardening SSH on the Ubuntu server.

The raw terminal captures are stored in `docs/captures/`.

---

## 1. System Baseline

I first recorded the system I was working on before making any changes.

The server was running:

```text
Ubuntu 24.04.4 LTS
```

I also recorded the kernel and OpenSSH version so that the project has a clear technical baseline.

### Evidence

- `docs/captures/001-ssh-baseline.txt`

---

## 2. Initial SSH Service State

I checked the initial state of the SSH service, socket and TCP/22 listener.

This gave me a record of how SSH was running before I changed any configuration.

### Evidence

- `docs/captures/002-ssh-service-baseline.txt`

---

## 3. SSH Configuration Sources

I inspected the main SSH configuration and the drop-in directory:

```text
/etc/ssh/sshd_config
/etc/ssh/sshd_config.d/
```

The server contained:

```text
/etc/ssh/sshd_config.d/60-cloudimg-settings.conf
```

This showed that I could not rely on `/etc/ssh/sshd_config` alone when checking the SSH configuration.

### Evidence

- `docs/captures/003-ssh-config-sources.txt`
- `docs/captures/010-main-sshd-config.txt`

---

## 4. Initial Effective SSH Configuration

I used:

```bash
sudo sshd -T
```

to record the configuration OpenSSH actually resolved.

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

This became my baseline for later hardening tests.

### Evidence

- `docs/captures/004-ssh-effective-baseline.txt`

---

## 5. SSH Baseline Configuration Sources

I compared the effective baseline with the main configuration and the files under `/etc/ssh/sshd_config.d/`.

| Effective value | Source |
| --- | --- |
| `PasswordAuthentication no` | Explicitly set by `60-cloudimg-settings.conf` |
| `KbdInteractiveAuthentication no` | Explicit SSH configuration on the instance |
| `PubkeyAuthentication yes` | OpenSSH default |
| `PermitRootLogin without-password` | OpenSSH default |
| `MaxAuthTries 6` | OpenSSH default |
| `LoginGraceTime 120` | OpenSSH default |
| No `AllowUsers` restriction | No explicit user allowlist configured |

Most of the initial values came from OpenSSH defaults rather than changes I had made.

The cloud-image drop-in explicitly contributed:

```text
PasswordAuthentication no
```

### Evidence

- `docs/captures/003-ssh-config-sources.txt`
- `docs/captures/004-ssh-effective-baseline.txt`
- `docs/captures/010-main-sshd-config.txt`

---

## 6. Administrative User

I confirmed that the account I was using to administer the server was:

```text
ubuntu
```

This was important before later introducing an SSH user allowlist.

### Evidence

- `docs/captures/005-current-admin-user.txt`

---

## 7. SSH Socket Activation

I checked how OpenSSH was being started and how TCP/22 was being handled.

`ssh.socket` showed:

```text
Triggers: ssh.service
Listen: 0.0.0.0:22
```

The TCP/22 listener showed both `systemd` and `sshd` holding file descriptors for the same listening socket.

This confirmed the socket-activation model on this server: systemd holds the listening socket and passes it to `sshd` when the service is activated.

### Evidence

- `docs/captures/006-ssh-activation-model.txt`

---

## 8. Root SSH Authorization

Before changing root access, I checked whether root had an SSH authorized key.

The root account had:

```text
/root/.ssh/authorized_keys
```

with one key.

The relevant permissions were:

```text
/root                         700 root:root
/root/.ssh                    700 root:root
/root/.ssh/authorized_keys    600 root:root
```

The key contained restrictions including:

```text
no-port-forwarding
no-agent-forwarding
no-X11-forwarding
```

It also contained a forced command telling the user to connect as `ubuntu` instead of `root`.

### Evidence

- `docs/captures/007-root-ssh-authorization.txt`

---

## 9. Root SSH Behaviour Before Hardening

I tested a root SSH connection using the same private key used for the `ubuntu` account.

The client displayed:

```text
Please login as the user "ubuntu" rather than the user "root".
```

The connection then closed and no interactive root shell was provided.

### Evidence

- `docs/captures/008-root-login-behaviour.txt`

---

## 10. Server-Side Root Login Confirmation

I checked the server logs after the root connection attempt.

The logs showed that the public key for root was accepted.

However, the forced command from `/root/.ssh/authorized_keys` ran instead of an interactive root shell.

This showed that the original protection was not a complete daemon-level block on root authentication.

The behaviour was:

```text
root public key accepted
        ↓
authorized_keys restrictions applied
        ↓
forced command executed
        ↓
no interactive root shell
```

### Evidence

- `docs/captures/009-root-login-server-log.txt`

---

## 11. SSH Drop-In Precedence Test

I wanted to confirm how conflicting drop-in settings were resolved instead of assuming the precedence behaviour.

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

After removing the temporary file, it returned to:

```text
passwordauthentication no
```

I did not reload SSH during this test.

This confirmed the drop-in precedence behaviour directly on the server.

### Evidence

- `docs/captures/011-ssh-dropin-precedence-test.txt`

---

## 12. PermitRootLogin Hardening

I created my own hardening drop-in and initially added only:

```text
PermitRootLogin no
```

I kept this change separate so that I could test its effect without mixing it with other controls.

Before reloading SSH, I validated the configuration with:

```bash
sudo sshd -t
```

and checked the effective value with:

```bash
sudo sshd -T | grep '^permitrootlogin'
```

The resolved value was:

```text
permitrootlogin no
```

### Evidence

- `docs/captures/012-permitrootlogin-pre-reload.txt`

---

## 13. Ubuntu Login After PermitRootLogin Change

After reloading SSH:

- my existing `ubuntu` session remained active;
- a fresh `ubuntu` SSH connection also succeeded.

This confirmed that disabling direct root login did not remove my normal administrative access.

### Evidence

- `docs/captures/013-ubuntu-login-after-permitrootlogin.txt`

---

## 14. Root Login After PermitRootLogin Change

I repeated the root SSH test after applying:

```text
PermitRootLogin no
```

This time the root connection was refused.

The previous forced-command message was not displayed.

This showed that root access was now being blocked by the SSH daemon policy rather than relying on the per-key forced command.

### Evidence

- `docs/captures/014-root-login-after-permitrootlogin.txt`
- `docs/captures/015-permitrootlogin-server-log.txt`

---

## 15. AllowUsers Behavioural Validation

I then added:

```text
AllowUsers ubuntu
```

I tested this control separately so that I could tell whether it was actually responsible for blocking other users.

I created a temporary local account named:

```text
ssh-test
```

and configured it with a valid SSH public key.

Before reloading the new SSH configuration:

```text
ssh-test + valid key → SUCCESS
```

### Evidence

- `docs/captures/016-allowusers-before-reload.txt`

---

## 16. AllowUsers After Reload

After reloading SSH with:

```text
AllowUsers ubuntu
```

active:

```text
ubuntu + valid key        → SUCCESS
ssh-test + same valid key → DENIED
```

The user and key had not changed. The important change was the active SSH allowlist.

This confirmed that having a valid local account and authorized key was no longer enough to gain SSH access if the username was not included in `AllowUsers`.

### Evidence

- `docs/captures/017-allowusers-after-reload.txt`

---

## 17. AllowUsers Server-Side Confirmation

I also checked the server logs for the rejected `ssh-test` connection.

The log confirmed that the test account was not permitted under the active SSH policy.

After completing the test, I removed the temporary `ssh-test` account.

### Evidence

- `docs/captures/018-allowusers-server-log.txt`

---

## Current Verified SSH State

At this stage, I have directly added and tested:

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

The next controls I plan to change are:

```text
MaxAuthTries 3
LoginGraceTime 30
```

After that, I will build the Bash audit script and test it against both compliant and deliberately broken controls.
