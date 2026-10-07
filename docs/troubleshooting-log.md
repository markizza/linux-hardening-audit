### Root SSH authorization prediction

Before inspecting the root account:

1. **Does `/root/.ssh/authorized_keys` exist?**
   Prediction: Yes. Since this is an AWS Ubuntu image, I expect some form of
   root SSH authorization configuration to exist.

2. **If it exists, how many keys are present and whose are they?**
   Prediction: I expect one key, potentially related to the key installed for
   the default `ubuntu` account. I will verify rather than assume ownership from
   the key comment alone.

3. **What will happen if someone connects as root using the matching private key?**
   Prediction: Since the effective configuration currently reports
   `permitrootlogin without-password`, public-key authentication for root is
   potentially permitted. However, the actual result may depend on restrictions
   attached to the root `authorized_keys` entry.


### Root SSH behavioural test prediction

The effective OpenSSH configuration currently reports:

`permitrootlogin without-password`

The root account also has an SSH authorization configuration that has now
been inspected.

Based on the effective daemon configuration and the options attached to the
authorized key, I predict that:

the root ssh login attempt would be rejected because the options in the authorized key has an echo command to prompt the user to login as ubuntu user rather than root

I will now test a fresh SSH connection as `root` using the same private key
used for the `ubuntu` account.

The existing `ubuntu` SSH session will remain open throughout the test.

## 001 — Root SSH Behavioural Test

### Prediction

I expected the root SSH attempt to be blocked because the root `authorized_keys` entry contained a forced command telling the user to log in as `ubuntu`.

### Test

I connected as `root` using the same private key used for the `ubuntu` account.

### Result

The connection displayed:

```text
Please login as the user "ubuntu" rather than the user "root".
Connection closed.
```

No interactive root shell was provided.

### Analysis

My outcome prediction was correct, but the mechanism was slightly different.

The connection was not simply rejected at authentication. The authorized key was processed and its forced command ran instead of giving access to a root shell.

### Lesson

`PermitRootLogin` alone does not show the full behaviour of root SSH access. The daemon configuration and the options inside `authorized_keys` both affect what happens.

### Evidence

* `docs/captures/007-root-ssh-authorization.txt`
* `docs/captures/008-root-login-behaviour.txt`

## 002 — SSH Drop-in Precedence Test

### Prediction

`60-cloudimg-settings.conf` currently sets:

`PasswordAuthentication no`

I predict that if I temporarily create an earlier drop-in containing:

`PasswordAuthentication yes`

then `sshd -T` will report `passwordauthentication yes`, because included
files are processed in lexical order and OpenSSH normally uses the first
obtained value for a directive.

I will not reload SSH during this test, so the running SSH service should
remain unchanged.

### Result

**Prediction: Correct.**

With both files present, `sshd -T` reported:

```text
passwordauthentication yes
```

After removing `00-precedence-test.conf`, `sshd -T` returned:

```text
passwordauthentication no
```

No SSH reload was performed during the test.

### Lesson

OpenSSH processed the included drop-in files in lexical order, and the first value obtained for this directive won.

This demonstrated the precedence behaviour directly on the server rather than assuming it from documentation.

It also confirmed that `sshd -T` can be used to test how the configuration resolves before applying it to the running SSH service.

## 003 — Cross-Platform Line Endings

### Finding

Git warned that an LF-formatted terminal capture copied from Linux would be converted to CRLF in the Windows working copy.

### Risk

CRLF can break Bash scripts executed on Linux. If a script's shebang becomes:

```text
#!/bin/bash\r
```

Linux may treat the carriage return as part of the interpreter path and report:

```text
bad interpreter: No such file or directory
```

even though `/bin/bash` exists.

This issue was caught preventatively from the Git warning before it caused a script failure.

### Resolution

I added a `.gitattributes` file enforcing LF line endings for:

```text
*.sh
*.txt
*.md
```

I then ran:

```bash
git add --renormalize .
```

and verified the evidence capture with:

```bash
git ls-files --eol docs/captures/011-ssh-dropin-precedence-test.txt
```

The repository and working copy reported LF line endings, confirming that the rule had been applied rather than only declared.

### Lesson

Cross-platform repositories should define line-ending behaviour at repository level rather than relying on each machine's Git configuration.

This prevents Windows line-ending conversion from silently altering Linux evidence files or breaking shell scripts.
