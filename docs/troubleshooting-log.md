# Troubleshooting Log

This log records predictions, tests, corrections and lessons from the project.

I use it to separate what I expected to happen from what the server actually did.

---

## 001 — Root SSH Behavioural Test

### Prediction

Before inspecting the root account, I expected `/root/.ssh/authorized_keys` to exist and possibly contain the same key used for the default `ubuntu` account.

After inspecting the file, I found one authorized key with a forced command telling the user to log in as `ubuntu`.

I therefore predicted that connecting as `root` with the matching private key would not give me an interactive root shell.

### Test

I connected as `root` using the same private key used for the `ubuntu` account.

### Result

**Prediction: Correct, but my explanation needed refining.**

The client displayed:

```text
Please login as the user "ubuntu" rather than the user "root".
Connection closed.
```

The server log showed that the root public key was accepted.

The forced command in `/root/.ssh/authorized_keys` then ran instead of the normal root shell.

### Analysis

My original wording suggested that the root login would simply be rejected.

That was not quite what happened.

The authentication progressed far enough for the authorized key to be accepted. The restriction happened afterwards, when the forced command replaced the normal shell.

The behaviour was:

```text
root public key accepted
        ↓
authorized_keys options applied
        ↓
forced command executed
        ↓
no interactive root shell
```

I later found another important limitation in my investigation.

The SSH service was also started with:

```text
AuthorizedKeysCommand /usr/share/ec2-instance-connect/eic_run_authorized_keys %u %f
AuthorizedKeysCommandUser ec2-instance-connect
```

This means `/root/.ssh/authorized_keys` is not the only possible source of SSH public keys on this EC2 instance.

My test therefore proved the behaviour of the persistent root key I inspected, but it did not describe every possible key source available to `sshd`.

### Lesson

`PermitRootLogin` alone does not describe the full practical behaviour of root SSH access.

I need to consider:

- the effective SSH daemon policy;
- local `authorized_keys` files;
- options attached to individual keys;
- file ownership and permissions;
- additional key sources such as EC2 Instance Connect;
- actual connection behaviour.

### Evidence

- [007-root-ssh-authorization.txt](captures/007-root-ssh-authorization.txt)
- [008-root-login-behaviour.txt](captures/008-root-login-behaviour.txt)
- [009-root-login-server-log.txt](captures/009-root-login-server-log.txt)
- [002-ssh-service-baseline.txt](captures/002-ssh-service-baseline.txt)

---

## 002 — SSH Drop-In Precedence Test

### Prediction

`60-cloudimg-settings.conf` contained:

```text
PasswordAuthentication no
```

I predicted that if I temporarily created an earlier drop-in containing:

```text
PasswordAuthentication yes
```

then `sshd -T` would report:

```text
passwordauthentication yes
```

I did not reload SSH during this test.

### Test

I created a temporary:

```text
00-precedence-test.conf
```

containing:

```text
PasswordAuthentication yes
```

I then checked the resolved configuration using:

```bash
sudo sshd -T | grep '^passwordauthentication'
```

After the test, I removed the temporary file and checked the value again.

### Result

**Prediction: Correct.**

With both files present:

```text
passwordauthentication yes
```

After removing `00-precedence-test.conf`:

```text
passwordauthentication no
```

The SSH service was not reloaded during the experiment.

### Lesson

The test showed that `00-precedence-test.conf` supplied the effective value when it conflicted with `60-cloudimg-settings.conf`.

This was consistent with OpenSSH's documented lexical processing and first-obtained-value behaviour.

The experiment itself only tested this specific ordering on my server, so I do not treat it as standalone proof of every possible OpenSSH precedence case.

It also showed that `sshd -T` is useful for checking how a configuration resolves before applying it to the running SSH service.

### Evidence

- [011-ssh-dropin-precedence-test.txt](captures/011-ssh-dropin-precedence-test.txt)

---

## 003 — Cross-Platform Line Endings

### Finding

While adding a Linux-generated capture to Git from Windows, Git warned that LF line endings would be replaced by CRLF in the working copy.

### Risk

CRLF can cause a Bash script to fail on Linux if the carriage return becomes part of the shebang.

For example:

```text
#!/bin/bash\r
```

can cause Linux to report:

```text
bad interpreter: No such file or directory
```

even though `/bin/bash` exists.

I encountered the warning before any Bash script actually failed, so this was a preventative fix.

### Initial Fix

I first added `.gitattributes`, but my original rule did not apply to the file as expected.

I checked using:

```bash
git ls-files --eol
```

and saw that no attribute rule was being reported for the capture.

### Correction

I corrected `.gitattributes` to apply LF handling at repository level, renormalized the files, and checked again.

I used:

```bash
git add --renormalize .
```

and verified the result with:

```bash
git ls-files --eol docs/captures/011-ssh-dropin-precedence-test.txt
```

The index and working copy then reported LF line endings.

### Lesson

Adding a configuration file does not prove the configuration has taken effect.

I had to check Git's actual state after making the change.

This is the same approach I use with SSH configuration: configure first, then verify the effective result.

### Related File

- [.gitattributes](../.gitattributes)

---

## 004 — Disable Direct Root SSH Login

### Prediction

I predicted that after setting:

```text
PermitRootLogin no
```

and reloading SSH:

- my existing `ubuntu` session would remain active;
- a fresh `ubuntu` connection would still succeed;
- a fresh `root` connection would be refused;
- the forced command in `/root/.ssh/authorized_keys` would no longer run.

### Recovery Plan

If a fresh `ubuntu` connection failed, I planned to:

1. Keep the original SSH session open.
2. Remove or correct the hardening configuration.
3. Validate the configuration with `sshd -t`.
4. Reload SSH.
5. Test a fresh `ubuntu` connection before closing the original session.

### Test

I added only:

```text
PermitRootLogin no
```

to `00-hardening.conf`.

Before reloading SSH, I ran:

```bash
sudo sshd -t
```

and checked the effective value with:

```bash
sudo sshd -T | grep '^permitrootlogin'
```

The effective result was:

```text
permitrootlogin no
```

I then reloaded SSH and tested:

- the existing `ubuntu` session;
- a fresh `ubuntu` connection;
- a fresh `root` connection.

### Result

**Prediction: Correct.**

The existing `ubuntu` session remained active.

A fresh `ubuntu` connection succeeded.

The root connection was refused, and the earlier forced-command message was not displayed.

The server log recorded:

```text
ROOT LOGIN REFUSED FROM <REDACTED-PUBLIC-IP> port <REDACTED> [preauth]
Connection reset by authenticating user root <REDACTED-PUBLIC-IP> [preauth]
```

### Analysis

The `[preauth]` marker showed that the connection was refused before authentication completed.

This was different from the earlier root test, where the public key was accepted and the forced command executed.

The behaviour changed from:

```text
BEFORE

root key accepted
      ↓
forced command
      ↓
no shell
```

to:

```text
AFTER

PermitRootLogin no
      ↓
root refused during pre-authentication
```

### Lesson

`PermitRootLogin no` moved the protection to the SSH daemon-policy layer.

The server no longer relied on the per-key forced command to prevent an interactive root session.

The test also confirmed that reloading SSH did not terminate my already-established session. New connection attempts were evaluated against the updated configuration.

### Evidence

- [012-permitrootlogin-pre-reload.txt](captures/012-permitrootlogin-pre-reload.txt)
- [013-ubuntu-login-after-permitrootlogin.txt](captures/013-ubuntu-login-after-permitrootlogin.txt)
- [014-root-login-after-permitrootlogin.txt](captures/014-root-login-after-permitrootlogin.txt)
- [015-permitrootlogin-server-log.txt](captures/015-permitrootlogin-server-log.txt)

---

## 005 — Restrict SSH Users

### Prediction

I predicted that after adding:

```text
AllowUsers ubuntu
```

and reloading SSH:

- my existing `ubuntu` session would remain active;
- a fresh `ubuntu` SSH connection would succeed;
- another valid local user would be denied SSH access even if it had a valid authorized key.

### Test

I created a temporary local account called:

```text
ssh-test
```

I configured it with the same public key used for the `ubuntu` account.

Before reloading SSH, I confirmed that the account could successfully connect:

```text
ssh-test + valid key → SUCCESS
```

I then reloaded SSH with:

```text
AllowUsers ubuntu
```

active and repeated the same connection attempt.

### Result

**Prediction: Correct.**

After the reload:

```text
ubuntu + valid key        → SUCCESS
ssh-test + same valid key → DENIED
```

The server log recorded:

```text
User ssh-test from <REDACTED-PUBLIC-IP> not allowed because not listed in AllowUsers [preauth]
```

### Analysis

The `[preauth]` message gave me the reason for the failure directly.

The account was rejected because it was not included in `AllowUsers`.

The test kept the user, key and authentication method the same. The relevant change was that the SSH allowlist had become active.

### Lesson

A valid local account and valid SSH key are not enough for SSH access when the username is excluded by daemon policy.

Testing with `ssh-test` also allowed me to verify `AllowUsers` separately instead of using `root`, which was already blocked by `PermitRootLogin no`.

### Cleanup

I used `ssh-test` only for this experiment.

After completing the test, I removed the temporary account and its home directory.

I verified the cleanup rather than assuming the removal command had succeeded:

```text
ssh-test account     → NOT PRESENT
/home/ssh-test       → NOT PRESENT
```
A separate capture confirming that the temporary account is no longer present is still required before I treat the cleanup as evidenced.

### Evidence

- [016-allowusers-before-reload.txt](captures/016-allowusers-before-reload.txt)
- [017-allowusers-after-reload.txt](captures/017-allowusers-after-reload.txt)
- [018-allowusers-server-log.txt](captures/018-allowusers-server-log.txt)
- [019-ssh-test-cleanup.txt](captures/019-ssh-test-cleanup.txt)

---

## Next Troubleshooting Entry

The next hardening stage will cover:

```text
MaxAuthTries 3
LoginGraceTime 30
```

From this point onward, I will commit the prediction before making the corresponding server change so the Git history also records the order of the experiment.
