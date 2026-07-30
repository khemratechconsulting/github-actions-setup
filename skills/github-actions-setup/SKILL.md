---
name: github-actions-setup
description: Sets up automated CI/CD with GitHub Actions for a project in one pass — a test workflow that runs on every push/PR, plus a deploy workflow to AWS, Vercel, or a generic SSH server, wired together with secrets and environment protection following professional DevOps practice. Use this whenever the user wants to "set up GitHub Actions," "add CI/CD," "automate testing and deployment," "configure a github workflow," mentions .github/workflows, asks how to deploy automatically on push to main, or is starting a new project and asks how to get testing/deployment automation going — even if they don't say "GitHub Actions" by name. Also use it when a project has no automation yet and the user is preparing to ship, or when they ask for help with secrets, environments, or workflow triggers on an existing workflow file.
---

# GitHub Actions Setup

This skill takes a project from no automation to "push to main and it tests + deploys itself." It bundles a one-command script, ready-made workflow templates for three common deploy targets, and a best-practices reference — use whichever combination fits what the user actually needs, rather than dumping everything on them at once.

## When this triggers, figure out two things first

1. **What language/stack is the project?** Look for `package.json`, `requirements.txt`/`pyproject.toml`, or `go.mod` in the project directory. If none of those are present, ask.
2. **Where does it deploy?** AWS, Vercel, a generic server (anything reachable over SSH), or nothing yet (tests only). If the user hasn't said, ask — don't guess, since the secrets and deploy steps are completely different per target. If they mention a specific host they SSH into, that's "server"; if they mention S3/CloudFront/ECS, that's "aws"; if they mention Vercel or a framework Vercel is known for (Next.js, etc.) and don't correct you, "vercel" is a safe assumption to confirm.

## Fastest path: run the script

For a real project directory, the cleanest approach is to run `scripts/setup.sh` from the project root (it needs execute permission: `chmod +x scripts/setup.sh` first if copied somewhere new). It auto-detects the language, and takes the deploy target either interactively or via `--deploy=aws|vercel|server|none`. It writes `.github/workflows/ci-cd.yml` and a `.github/dependabot.yml` for automatic dependency updates, and prints the exact secret names the user still needs to add in GitHub before their first push.

Prefer running the script over hand-writing YAML when you have shell access to the user's project — it guarantees valid, tested output and takes one command.

## When to use the standalone templates instead

If the user just wants to see or copy a workflow file (no shell access to their repo, or they want to review before applying), use the matching file in `assets/workflows/` directly:

- `ci-only.yml` — tests only, no deploy. Good starting point for a project not ready to automate deployment yet.
- `ci-cd-aws.yml` — test job + deploy to S3/CloudFront via AWS OIDC (no static keys). Note in the file explains how to adapt the deploy step for ECS/Elastic Beanstalk instead.
- `ci-cd-vercel.yml` — test job + PR preview deploys + production deploy on merge to main.
- `ci-cd-generic-server.yml` — test job + SSH deploy (pull + restart) to any server.

Each template has a comment header listing the exact repo secrets it needs. Walk the user through adding those under **Settings → Secrets and variables → Actions** — don't just hand them the file and move on, since a workflow with missing secrets fails on first run in a confusing way.

## Explaining the "why" behind the setup

If the user asks why something is structured a certain way (why OIDC instead of access keys, why `needs: test` gates the deploy job, why there's a `concurrency:` block), pull the explanation from `references/best-practices.md` rather than improvising — it covers secrets management, environment variables vs. secrets, trigger/concurrency patterns, and least-privilege permissions in more depth than fits here.

For a full walkthrough written for someone setting this up for the first time (workflow anatomy, step-by-step, first-run checklist), point to or adapt `references/guide.md`.

## After setup: the checklist

Once a workflow file exists (from the script or a copied template), walk the user through:

1. Add the required secrets (Settings → Secrets and variables → Actions).
2. If deploying, create a `production` environment (Settings → Environments) — suggest a required reviewer if this is a production-facing project, since it adds a manual approval gate before deploy runs.
3. Push a branch, open a PR, confirm the `test` job passes.
4. Merge to `main`, confirm `deploy` runs and the app actually updates.
5. Optionally turn on branch protection on `main` requiring the CI check before merge — mention this as a good next step, don't assume it's wanted.

Don't invent a deploy target that isn't one of the three supported here. If the user needs something else (Kubernetes, Cloudflare Pages, Netlify, GCP, Azure), say the bundled templates don't cover it directly, then adapt the closest template's structure (test job gating a deploy job, same secrets/environment pattern) using the target's official GitHub Action.
