<div align="center">

![github-actions-setup]([docs/assets/hero-banner.png](https://khemratechconsulting.github.io/github-actions-setup/)

# github-actions-setup

**A Claude skill that sets up automated CI/CD for any project in one command.**

![Release](https://img.shields.io/badge/release-v1.0.0-5b8cff?style=for-the-badge)
![Deploy Targets](https://img.shields.io/badge/deploy_targets-3-ff8a5b?style=for-the-badge)
![Languages](https://img.shields.io/badge/languages-node%20%7C%20python%20%7C%20go-3ecf8e?style=for-the-badge)
![License](https://img.shields.io/badge/license-MIT-e8e9ed?style=for-the-badge)
![Stars](https://img.shields.io/github/stars/khemratechconsulting/github-actions-setup?style=for-the-badge&color=5b8cff)

Auto-detects your language, writes a tested GitHub Actions workflow, and wires up secrets, environments, and dependency updates — the way a careful senior engineer would, not a copy-pasted tutorial.

[Website](https://khemratechconsulting.github.io/github-actions-setup) · [Setup Guide](docs/setup-guide.md) · [Pro](https://khemratechconsulting.github.io/github-actions-setup#pricing)

</div>

---

## What it does

Point it at a project and it will:

- **Detect the language** — Node, Python, or Go, from files already in the repo.
- **Ask where you deploy** — AWS (S3 + CloudFront via OIDC), Vercel (preview + production), or any server over SSH.
- **Generate a real workflow** — a `test` job gates a `deploy` job; nothing reaches production without passing tests first.
- **Set up Dependabot** — weekly dependency + GitHub Actions version updates, for free.
- **Tell you exactly what to do next** — the precise secret names to add, and which GitHub Environment to create.

```bash
curl -fsSL https://raw.githubusercontent.com/khemratechconsulting/github-actions-setup/main/skills/github-actions-setup/scripts/setup.sh | bash
```

(Or run it from a local clone: `bash skills/github-actions-setup/scripts/setup.sh`.)

## Using it as a Claude skill

This repo is also a [Claude skill](https://docs.claude.com/en/docs/claude-code/skills) — add it to Claude Code or Cowork and it triggers automatically whenever you ask to "set up GitHub Actions," "add CI/CD," or similar. See `skills/github-actions-setup/SKILL.md`.

## What's included (free, MIT-licensed)

| Template | Covers |
|---|---|
| `ci-only.yml` | Tests only, matrix across two Node versions |
| `ci-cd-aws.yml` | Test → deploy to S3/CloudFront, OIDC auth |
| `ci-cd-vercel.yml` | Test → PR previews → production deploy |
| `ci-cd-generic-server.yml` | Test → SSH deploy + process restart |

Full write-up of the security and efficiency choices baked into these: [`skills/github-actions-setup/references/best-practices.md`](skills/github-actions-setup/references/best-practices.md).

## Pro

The free tier covers the three most common deploy targets. **Pro** adds Google Cloud Run, Docker/GHCR multi-arch builds, and a staging→production promotion workflow with manual approval gates and Slack notifications — see the [pricing section](https://khemratechconsulting.github.io/github-actions-setup#pricing) on the site.

## Contributing

Issues and PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Found a security issue? See [SECURITY.md](SECURITY.md) instead of opening a public issue.

## License

MIT — see [LICENSE](LICENSE).
