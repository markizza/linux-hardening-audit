## SSH Baseline Configuration Sources

The initial `sshd -T` baseline was compared against the main SSH configuration and the files under `/etc/ssh/sshd_config.d/`.

| Effective value                    | Source                                        |
| ---------------------------------- | --------------------------------------------- |
| `PasswordAuthentication no`        | Explicitly set by `60-cloudimg-settings.conf` |
| `KbdInteractiveAuthentication no`  | Explicit SSH configuration on the instance    |
| `PubkeyAuthentication yes`         | OpenSSH default                               |
| `PermitRootLogin without-password` | OpenSSH default                               |
| `MaxAuthTries 6`                   | OpenSSH default                               |
| `LoginGraceTime 120`               | OpenSSH default                               |
| No `AllowUsers` restriction        | No explicit user allowlist configured         |

The investigation showed that most of the original SSH baseline came from OpenSSH defaults rather than deliberate hardening.

The cloud-image drop-in explicitly contributed `PasswordAuthentication no`.

A temporary configuration collision also confirmed that earlier SSH drop-in files can override later files because the first obtained value for the tested directive was used.
