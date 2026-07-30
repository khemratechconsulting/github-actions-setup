---
name: github-actions-setup
description: Sets up automated CI/CD with GitHub Actions for any project in one pass. Intelligently auto-detects language (Node.js, Python, Go, Rust, Docker, Java, Ruby) and architecture (Frontend web apps vs Backend APIs/microservices). Generates production-ready workflow files for AWS, Vercel, Cloudflare, Railway, Render, or SSH servers with OIDC security and Dependabot. Can also install itself as a local IDE skill for Claude Code (.claude/), Cursor/Copilot/Gemini (.agents/), Antigravity (.agent/), or Windsurf (.windsurf/). Trigger whenever the user asks to "set up GitHub Actions," "add CI/CD," "configure a github workflow," or asks how to automate testing and deployment.
---

# GitHub Actions Setup

This skill takes a project from no automation to "push to main and it tests + deploys itself." It bundles a one-command script, ready-made workflow templates for three common deploy targets, and a best-practices reference — use whichever combination fits what the user actually needs, rather than dumping everything on them at once.

## When this triggers, figure out two things first

1. **What language/stack is the project?** Look for `package.json`, `requirements.txt`/`pyproject.toml`, or `go.mod` in the project directory. If none of those are present, ask.
2. **Where does it deploy?** AWS, Vercel, Cloudflare Pages/Workers, Railway, Render, a generic server (anything reachable over SSH), or nothing yet (tests only). If the user hasn't said, ask — don't guess, since the secrets and deploy steps are completely different per target. If they mention a specific host they SSH into, that's "server"; if they mention S3/CloudFront/ECS, that's "aws"; if they mention Vercel or a framework Vercel is known for (Next.js, etc.) and don't correct you, "vercel" is a safe assumption to confirm; Cloudflare Pages/Workers, Railway, and Render map directly if named.

   Only AWS authenticates via GitHub OIDC (no stored long-lived credentials). Cloudflare, Railway, and Render don't support OIDC federation from GitHub yet, so those three use a static API token or deploy hook URL stored as a repo secret instead — mention this when walking through secrets for one of those targets, don't imply all five are equivalent in security posture.

   When the target isn't obvious from what the user said, the script's interactive menu badges a recommended target based on the detected stack (static Node frontends toward Vercel/Cloudflare; Node APIs, Python web frameworks, and Go services toward Railway/Render/server) — a useful default to suggest, not a rule to enforce.

## Fastest path: run the script

For a real project directory, the cleanest approach is to run `scripts/setup.sh` from the project root (it needs execute permission: `chmod +x scripts/setup.sh` first if copied somewhere new). It auto-detects the language, and takes the deploy target either interactively or via `--deploy=aws|vercel|cloudflare|railway|render|server|none`. It writes `.github/workflows/ci-cd.yml` and a `.github/dependabot.yml` for automatic dependency updates, and prints the exact secret names the user still needs to add in GitHub before their first push.

Prefer running the script over hand-writing YAML when you have shell access to the user's project — it guarantees valid, tested output and takes one command.

## Installing as a local project skill for AI IDEs & Agents

`scripts/setup.sh` includes an opt-in skill installer (`--install-skill` or via interactive prompt). It auto-detects existing local IDE skill root directories in the current project:
- `.agents/skills/github-actions-setup` (Cursor, Copilot, Gemini CLI, Amp, Cline, Warp)
- `.agent/skills/github-actions-setup` (Antigravity)
- `.claude/skills/github-actions-setup` (Claude Code)
- `.windsurf/skills/github-actions-setup` (Windsurf)

When running with `--install-skill`, it copies `SKILL.md`, `references/`, and `scripts/` directly into the detected directory so AI assistants running inside the user's project automatically gain the CI/CD setup skill. Recommend adding the installed skill root (e.g., `.agents/skills/`) to `.gitignore` if the user prefers not to commit internal skill documentation into their project history.

## Auditing an existing workflow

If the user already has a `.github/workflows/*.yml` file (whether this script wrote it or not) and asks you to review it, don't just eyeball the YAML — run `scripts/setup.sh --validate` from the project root (or `--validate=path/to/file.yml` for a specific file). It checks for the same things a careful reviewer would: a missing top-level `permissions:` block, a deploy-looking job with no `needs:` gate (so it can run even if tests failed), a deploy-looking job with no `if:` restricting it to a branch/event (so it can fire from any PR, including forks), and actions pinned to a mutable `@main`/`@master` tag instead of a version or SHA. Add `--strict` if the user wants a non-zero exit code for CI/pre-push use. This is a real check against real files — prefer it over guessing from a pasted snippet, since it won't miss something a quick read would.

## When to use the standalone templates instead

If the user just wants to see or copy a workflow file (no shell access to their repo, or they want to review before applying), use the matching file in `assets/workflows/` directly:

- `ci-only.yml` — tests only, no deploy. Good starting point for a project not ready to automate deployment yet.
- `ci-cd-aws.yml` — test job + deploy to S3/CloudFront via AWS OIDC (no static keys). Note in the file explains how to adapt the deploy step for ECS/Elastic Beanstalk instead.
- `ci-cd-vercel.yml` — test job + PR preview deploys + production deploy on merge to main.
- `ci-cd-cloudflare.yml` — test job + deploy to Cloudflare Pages via a scoped API token (Wrangler CLI).
- `ci-cd-railway.yml` — test job + deploy via the official Railway CLI and a project token.
- `ci-cd-render.yml` — test job + trigger a Render deploy hook (no checkout needed in the deploy step — Render builds from its own connected source).
- `ci-cd-generic-server.yml` — test job + SSH deploy (pull + restart) to any server.

Cloudflare, Railway, and Render templates all use a static token/hook URL rather than OIDC, since none of the three support GitHub OIDC federation yet — call this out if the user asks why it differs from the AWS template.

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

Don't invent a deploy target that isn't one of the six supported here (AWS, Vercel, Cloudflare, Railway, Render, generic server). If the user needs something else (Kubernetes, Netlify, GCP, Azure), say the bundled templates don't cover it directly, then adapt the closest template's structure (test job gating a deploy job, same secrets/environment pattern) using the target's official GitHub Action.
