<div align="center">

<a href="https://khemratechconsulting.github.io/github-actions-setup" target="_blank">
  <img src="docs/assets/hero-banner.png" alt="github-actions-setup hero banner" width="100%" />
</a>

# github-actions-setup

**A Claude skill that sets up automated CI/CD for any project in one command.**

![Release](https://img.shields.io/badge/release-v1.1.0-5b8cff?style=for-the-badge)
![Deploy Targets](https://img.shields.io/badge/deploy_targets-6-ff8a5b?style=for-the-badge)
![Languages](https://img.shields.io/badge/languages-node%20%7C%20python%20%7C%20go%20%7C%20rust%20%7C%20docker-3ecf8e?style=for-the-badge)
![Supported IDEs](https://img.shields.io/badge/IDEs-Claude%20Code%20%7C%20Cursor%20%7C%20Windsurf%20%7C%20Antigravity%20%7C%20Void-5b8cff?style=for-the-badge)
![License](https://img.shields.io/badge/license-MIT-e8e9ed?style=for-the-badge)
![Stars](https://img.shields.io/github/stars/khemratechconsulting/github-actions-setup?style=for-the-badge&color=5b8cff)

Auto-detects your language and framework architecture (Next.js, React, Vue, Angular, NestJS, Python, Go, Rust, Docker), writes a tested GitHub Actions workflow, and wires up secrets, environments, and dependency updates — the way a careful senior engineer would, not a copy-pasted tutorial.

[Website](https://khemratechconsulting.github.io/github-actions-setup) · [Setup Guide](docs/setup-guide.md) · [Pricing & Supporter](https://khemratechconsulting.github.io/github-actions-setup#pricing)

</div>

---

## What it does

Point it at a project and it will:

- **Intelligently detect language & framework** — Next.js, React, Vue, Angular, NestJS, Express, Python, Go, Rust, and Docker containers.
- **Differentiate Frontend vs. Backend** — Recommends **Vercel / Cloudflare** for frontend web apps, and **Railway / Render / SSH** for backend APIs and services.
- **Generate a real workflow** — a `test` job gates a `deploy` job; nothing reaches production without passing tests first.
- **Set up Dependabot** — weekly dependency + GitHub Actions version updates, for free.
- **Tell you exactly what to do next** — the precise secret names to add, and which GitHub Environment to create.
- **Audit an existing workflow** — `--validate` checks any `.github/workflows/*.yml` for missing `permissions:`, ungated deploy jobs, and unpinned `@main`/`@master` actions; `--strict` exits non-zero for CI use.

### ⚡ Simple 1-Command Skill Installation

Run this command in your project terminal to install the CI/CD skill into your IDE:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/khemratechconsulting/github-actions-setup/main/skills/github-actions-setup/scripts/setup.sh)
```

---

### 🛡️ Security & Script Integrity Guarantee

We take script execution security seriously:
- **Transparent Source Code:** The script is 100% open source shell script inspectable directly at [`skills/github-actions-setup/scripts/setup.sh`](skills/github-actions-setup/scripts/setup.sh).
- **Inspect Source Code Before Running:** View the raw shell script line-by-line:
  ```bash
  curl -fsSL https://raw.githubusercontent.com/khemratechconsulting/github-actions-setup/main/skills/github-actions-setup/scripts/setup.sh | less
  ```
- **Zero-Dependency & No Elevating Privileges:** Does **not** require `sudo`, root permissions, or binary downloads. It only manipulates `.github/workflows/` and local `.agents/skills/` text files inside your repository workspace.

It auto-detects your IDE's skill directory:
- `.agents/skills/` (Cursor, GitHub Copilot, Gemini CLI, Amp, Cline, Warp)
- `.agent/skills/` (Antigravity)
- `.claude/skills/` (Claude Code)
- `.void/skills/` (Void IDE)
- `.windsurf/skills/` (Windsurf)
- `.kiro/skills/` (Kiro)
- `.codex/skills/` (Codex / OpenAI)
- `.qoder/skills/` (Qoder)

### How to use the skill after installation

Once installed, simply talk to your AI assistant inside your IDE in natural language:

- 💬 **"Set up GitHub Actions CI/CD for this project."**
- 💬 **"Configure automated deployment to Vercel (or Cloudflare / Railway / AWS)."**
- 💬 **"Audit our current `.github/workflows/ci-cd.yml` for security issues."**
- 💬 **"Add Dependabot for automated dependency security updates."**

Your AI assistant will read the local skill rulebook and execute the `setup.sh` automation script directly for you!

*Tip:* Add the skill directory to your project's `.gitignore` if you prefer not to commit internal skill documentation into your repo history.

See `skills/github-actions-setup/SKILL.md` for full trigger details.

## What's included (free, MIT-licensed)

| Template | Covers | Auth |
|---|---|---|
| `ci-only.yml` | Tests only, matrix across two Node versions | — |
| `ci-cd-aws.yml` | Test → deploy to S3/CloudFront | GitHub OIDC, no static keys |
| `ci-cd-vercel.yml` | Test → PR previews → production deploy | Static token |
| `ci-cd-cloudflare.yml` | Test → deploy to Cloudflare Pages (Wrangler) | Static, scoped API token |
| `ci-cd-railway.yml` | Test → deploy via Railway CLI | Static project token |
| `ci-cd-render.yml` | Test → trigger a Render deploy hook | Static hook URL |
| `ci-cd-generic-server.yml` | Test → SSH deploy + process restart | Static SSH key |

AWS is the only target here with GitHub OIDC federation — no long-lived credentials stored anywhere. Cloudflare, Railway, and Render don't support OIDC from GitHub yet, so those three (and Vercel/server) rely on a static secret; scope it as narrowly as the platform allows and rotate it periodically.

Full write-up of the security and efficiency choices baked into these: [`skills/github-actions-setup/references/best-practices.md`](skills/github-actions-setup/references/best-practices.md).

## Pricing

The free tier above covers the three most common deploy targets and is a complete toolkit on its own.

| Tier | Price | Adds |
|---|---|---|
| Free | $0 | Everything listed above |
| **Supporter** | **$1.99/mo** | Priority email support, early access to new templates |

Get either from the [pricing section](https://khemratechconsulting.github.io/github-actions-setup#pricing) on the site.

<!--
Draft tiers — built and tested, held back until the project has a real
user base rather than launching four untested price points at once.
Uncomment this table (and the matching cards in docs/index.html /
docs/pro.html) to relaunch them.

| Tier | Price | Adds |
|---|---|---|
| Builder | $4.77/mo | Google Cloud Run (OIDC), Docker/GHCR multi-arch builds |
| Shipper | $7.77/mo | Staging → production promotion, Slack deploy notifications |
| Pro | $9.77/mo | Custom deploy target requests, 1:1 setup call |

<details>
<summary>Full feature breakdown</summary>

**Builder — $4.77/mo** (everything in Supporter, plus)
- Google Cloud Run deploy, authenticated via Workload Identity Federation
- Docker/GHCR multi-arch builds with layer caching and semver tagging

**Shipper — $7.77/mo** (everything in Builder, plus)
- Staging → production promotion workflow with a manual approval gate
- Slack notifications on deploy

**Pro — $9.77/mo** (everything in Shipper, plus)
- Custom deploy target requests
- A 30-minute 1:1 setup call

</details>
-->

## Contributing

Issues and PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Found a security issue? See [SECURITY.md](SECURITY.md) instead of opening a public issue.

## License

MIT — see [LICENSE](LICENSE).
