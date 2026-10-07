# Troubleshooting Log

This log records the predictions I made before selected tests, what actually happened, and what I learned from the result.

---

## 001 — Root SSH Behavioural Test

### Prediction

Before inspecting the root account, I expected `/root/.ssh/authorized_keys` to exist and possibly contain the same key used for the default `ubuntu` account.

After inspecting the file, I found one authorized key with a forced command telling the user to log in as `ubuntu`.

I therefore predicted that a root SSH attempt would not provide an interactive root shell.

### Test

I connected as `root` using the same private key used for the `ubuntu` account.

### Result

**Prediction: Correct, but my explanation needed refining.**

The connection displayed:

```text
Please login as the user "ubuntu" rather than the user "root".
Connection closed.
```

The server-side log showed that the root public key was accepted, but no interactive root shell was provided.

### Analysis

The connection was not rejected during public-key authentication.

Instead, the key was accepted and the forced command in `/root/.ssh/authorized_keys` ran instead of the normal root shell.

### Lesson

`PermitRootLogin` alone does not describe the full behaviour of root SSH access.

In this case, the SSH daemon allowed public-key authentication for root, while the per-key options in `authorized_keys` controlled what happened after authentication.

### Evidence

- `docs/captures/007-root-ssh-authorization.txt`
- `docs/captures/008-root-login-behaviour.txt`
- `docs/captures/009-root-login-server-log.txt`

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

### Result

**Prediction: Correct.**

With both files present, `sshd -T` reported:

```text
passwordauthentication yes
```

After removing the temporary `00-precedence-test.conf` file, the result returned to:

```text
passwordauthentication no
```

### Lesson

The included drop-in files were processed in lexical order, and the first value obtained for this directive was used.

This test also showed that I could use `sshd -T` to check how a configuration would resolve before reloading the SSH service.

### Evidence

- `docs/captures/011-ssh-dropin-precedence-test.txt`

---

## 003 — Cross-Platform Line Endings

### Finding

Git warned that an LF-formatted terminal capture copied from Linux would be converted to CRLF in my Windows working copy.

### Risk

CRLF can break Bash scripts on Linux.

For example, a shebang may effectively become:

```text
#!/bin/bash\r
```

Linux can then treat the hidden carriage return as part of the interpreter path and report:

```text
bad interpreter: No such file or directory
```

even though `/bin/bash` exists.

I caught this from the Git warning before it caused a script failure.

### Resolution

I added a `.gitattributes` file enforcing LF endings for:

```text
*.sh
*.txt
*.md
```

I then ran:

```bash
git add --renormalize .
```

and verified the result with:

```bash
git ls-files --eol docs/captures/011-ssh-dropin-precedence-test.txt
```

The index and working copy both reported LF line endings.

### Lesson

I should not rely on platform defaults for line endings in a repository that moves files between Windows and Linux.

I verified the rule after adding it rather than assuming it had taken effect.

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
- a new `root` connection would be rejected;
- the forced command in `/root/.ssh/authorized_keys` would no longer run.

### Recovery Plan

If a fresh `ubuntu` connection failed, I planned to:

1. Keep the original SSH session open.
2. Remove or correct the hardening configuration.
3. Validate it with `sshd -t`.
4. Reload SSH.
5. Test another fresh connection before closing the original session.

### Test

I added only:

```text
PermitRootLogin no
```

to `00-hardening.conf`.

Before reloading SSH, I validated the configuration with:

```bash
sudo sshd -t
```

and confirmed the effective value with:

```bash
sudo sshd -T | grep '^permitrootlogin'
```

After reloading SSH, I tested both `ubuntu` and `root` from fresh connections.

### Result

**Prediction: Correct.**

- The existing `ubuntu` session remained active.
- A fresh `ubuntu` connection succeeded.
- The new root connection was refused.
- The previous forced-command message was no longer displayed.

### Lesson

Before this change, root public-key authentication was accepted and the per-key forced command prevented a normal shell.

After `PermitRootLogin no`, root access was refused by the SSH daemon itself.

This moved the control from a per-key restriction to an explicit server-wide SSH policy.

The existing session also remained active after reload, which confirmed that the new policy affected new connections rather than retroactively changing the established session.

### Evidence

- `docs/captures/012-permitrootlogin-pre-reload.txt`
- `docs/captures/013-ubuntu-login-after-permitrootlogin.txt`
- `docs/captures/014-root-login-after-permitrootlogin.txt`
- `docs/captures/015-permitrootlogin-server-log.txt`

---

## 005 — Restrict SSH Users

### Prediction

I predicted that after adding:

```text
AllowUsers ubuntu
```

and reloading SSH:

- the existing `ubuntu` session would remain active;
- a fresh `ubuntu` connection would succeed;
- another valid local user would be denied SSH access even with a valid authorized key.

### Test

I created a temporary local user called `ssh-test` and configured it with the same public key used for the `ubuntu` account.

Before reloading SSH, I confirmed that `ssh-test` could successfully authenticate using the key.

I then reloaded SSH with:

```text
AllowUsers ubuntu
```

active and repeated the same connection attempt.

### Result

**Prediction: Correct.**

Before the reload:

```text
ssh-test + valid key → SUCCESS
```

After the reload:

```text
ssh-test + same valid key → DENIED
ubuntu + valid key        → SUCCESS
```

I removed the temporary `ssh-test` account after completing the test.

### Lesson

`AllowUsers` provides an explicit SSH account allowlist.

The test kept the user, key and authentication method the same while changing whether the allowlist was active.

This showed that a valid local account and valid SSH key are not enough for SSH access when the username is excluded by daemon policy.

### Evidence

- `docs/captures/016-allowusers-before-reload.txt`
- `docs/captures/017-allowusers-after-reload.txt`
- `docs/captures/018-allowusers-server-log.txt`
