# Security Policy

## Reporting a vulnerability

Please don't open a public issue for a security concern. Instead, email **sophimphath98@gmail.com** (or use GitHub's private vulnerability reporting under the Security tab, if enabled) with a description and, if possible, steps to reproduce.

## Scope

This repo distributes workflow *templates* and a setup *script* — it does not run any service or handle user data itself. The most relevant security surface is:

- Whether the generated workflows follow least-privilege practice (explicit `permissions:`, OIDC over static keys, deploy gated behind tests).
- Whether `setup.sh` could be tricked into overwriting files unexpectedly (it prompts before overwriting an existing workflow file).

Reports about either are very welcome.
