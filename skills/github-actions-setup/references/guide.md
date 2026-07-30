# GitHub Actions CI/CD: A Complete Setup Guide

This guide gets a project from "no automation" to "push to main and it tests + deploys itself" — beginner-friendly, but built on the same patterns used in professional DevOps setups.

## 1. How GitHub Actions is organized

Everything lives under a `.github/workflows/` folder at the root of your repo. Each `.yml` file in that folder is one independent **workflow** — GitHub watches for the trigger you define and runs the file's jobs on its own virtual machine when that trigger fires.

```
your-project/
└── .github/
    ├── workflows/
    │   └── ci-cd.yml
    └── dependabot.yml       (optional, keeps dependencies patched)
```

You don't need to install anything locally — GitHub reads the YAML the moment you push it, no CLI or account setup beyond having a GitHub repo.

## 2. Anatomy of a workflow file

Every workflow has the same four building blocks:

```yaml
name: CI/CD                # shows up in the Actions tab
on: [push, pull_request]   # trigger: when does this run?
jobs:                      # one or more independent units of work
  test:
    runs-on: ubuntu-latest  # the VM the job executes on
    steps:                  # ordered commands/actions inside the job
      - uses: actions/checkout@v4
      - run: npm test
```

- **`on`** — the trigger. Common choices: `push`, `pull_request`, `workflow_dispatch` (manual "Run workflow" button), or `schedule` (cron).
- **`jobs`** — each job runs on a fresh VM. Jobs run in parallel unless you tell one to wait on another with `needs:`.
- **`steps`** — a job's steps run in sequence, either `uses:` (a reusable action from the marketplace) or `run:` (a raw shell command).

## 3. Setting up the test (CI) workflow

The test job should run on every push and every pull request, so broken code never reaches `main` unnoticed:

```yaml
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]
```

Inside the job: check out the code, install the language runtime, install dependencies (using a lockfile — `npm ci`, not `npm install` — for reproducible builds), then run lint and tests. See `assets/workflows/ci-only.yml` for a ready-to-use version that tests against multiple Node.js versions in parallel via a build matrix.

Key habit: use `actions/setup-node` (or `setup-python`, `setup-go`) with its built-in `cache:` option — it caches dependencies between runs and can cut CI time by more than half.

## 4. Setting up the deploy (CD) workflow

Deployment should only happen after tests pass, and only from `main` (never from a PR from an unknown fork). That's expressed with `needs:` and an `if:` condition:

```yaml
jobs:
  test:
    ...
  deploy:
    needs: test
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    environment: production   # ties into GitHub's environment protection rules
    steps: ...
```

The `environment: production` line is what lets you (in repo Settings → Environments) require a manual approval before the deploy step runs — a one-click way to add a safety gate to production releases.

Three ready-made deploy targets are included in `assets/workflows/`:

- **`ci-cd-aws.yml`** — builds the app, then syncs the output to S3 and invalidates CloudFront, authenticating via OpenID Connect (OIDC) instead of long-lived AWS keys.
- **`ci-cd-vercel.yml`** — deploys PRs as preview URLs and pushes to `main` as production, using the official Vercel action.
- **`ci-cd-generic-server.yml`** — SSHes into any server (a VPS, EC2 box, on-prem host) and runs a pull + restart script.

Pick the one matching your infrastructure, drop it into `.github/workflows/`, and fill in the secrets it references (listed at the top of each file).

## 5. Managing secrets and environment variables

- **Secrets** (API keys, SSH keys, tokens) go in **Settings → Secrets and variables → Actions**, never in the YAML itself or in code. Reference them as `${{ secrets.NAME }}`.
- **Non-secret config** (a region name, a feature flag) should be a **variable** (`${{ vars.NAME }}`), also configured in the same settings page — this keeps secrets scoped to things that actually need protecting.
- **Per-environment secrets**: if staging and production need different values for the same secret name (e.g., different S3 buckets), define the secret at the **environment** level (Settings → Environments → production → secrets) rather than the repository level.
- Prefer **OIDC federation** (cloud provider trusts GitHub directly) over storing static cloud credentials as secrets, wherever the provider supports it — AWS, GCP, and Azure all do. The AWS template in this pack uses this pattern.

Full details and more patterns are in `references/best-practices.md`.

## 6. Trigger and efficiency best practices

- Add `concurrency:` groups so a new push cancels an in-flight run for the same branch, instead of wasting minutes on outdated code.
- Add `workflow_dispatch:` even to automated workflows — it costs nothing and lets you manually re-run a deploy without pushing an empty commit.
- Use `paths:` filters if your repo is a monorepo, so a docs-only change doesn't trigger a full test+deploy cycle.
- Set `permissions:` explicitly (least privilege) instead of relying on the default token scope.

## 7. One-command setup

Instead of copying files by hand, run the bundled script from your project root:

```bash
bash setup.sh
```

It detects whether your project is Node, Python, or Go, asks which deploy target you want (AWS / Vercel / generic server / none), then writes `.github/workflows/ci-cd.yml` and `.github/dependabot.yml` for you — and prints the exact list of secrets you still need to add in GitHub before your first push. See `setup.sh` usage notes at the top of the script for non-interactive/CI usage (flags instead of prompts).

## 8. First-run checklist

1. Run `setup.sh` (or copy a template manually) into `.github/workflows/`.
2. Add the required secrets under **Settings → Secrets and variables → Actions**.
3. If deploying, create a `production` environment under **Settings → Environments** and optionally require a reviewer.
4. Push to a branch, open a PR, confirm the `test` job goes green.
5. Merge to `main`, confirm the `deploy` job runs and the app updates.
6. (Optional) Add branch protection on `main` requiring the CI check to pass before merging.
