# GitHub Actions: Security & Efficiency Best Practices

## Secrets

- Store anything sensitive (API keys, SSH keys, cloud credentials, tokens) as a **repository or environment secret** (Settings → Secrets and variables → Actions), never as plain `env:` values in the YAML.
- Prefer **environment-scoped** secrets over repo-wide ones when a value differs between staging and production (e.g., two different database URLs). Create a `staging` and `production` environment and set the secret once inside each — the workflow just references `environment: production` and gets the right value automatically.
- Where the provider supports it, use **OIDC federation** instead of static credentials: GitHub issues a short-lived token, the cloud provider (AWS/GCP/Azure) trusts GitHub's identity provider directly, and there's no long-lived key sitting in Settings that can leak or need rotation. The AWS template in this pack (`ci-cd-aws.yml`) is set up this way via `aws-actions/configure-aws-credentials`.
- Require a **manual reviewer** on the `production` environment (Settings → Environments → production → required reviewers) so a deploy job pauses for a human click before it touches prod — cheap insurance against a bad merge auto-deploying.
- Never `echo` or `run: env` a secret for debugging — GitHub masks known secret values in logs, but only for exact string matches, so a transformed/encoded secret can still leak.

## Environment variables vs. secrets

- Use `vars.NAME` (Settings → Secrets and variables → Actions → Variables tab) for non-sensitive configuration — a region name, a feature flag, a build target — so secrets stay reserved for things that actually need protecting.
- Set shared values once at the workflow level (`env:` at the top of the file) instead of repeating them in every step.
- For values that differ by matrix entry (e.g., Node version), reference `${{ matrix.node-version }}` rather than hardcoding duplicate jobs.

## Triggers and efficiency

- Add a `concurrency:` group keyed on the branch/ref so a new push automatically cancels a superseded run instead of two deploys racing each other:
  ```yaml
  concurrency:
    group: deploy-${{ github.ref }}
    cancel-in-progress: true
  ```
  For deploy jobs, consider `cancel-in-progress: false` — you don't want to kill a deploy that's halfway through.
- Scope `on.push.branches` and `on.pull_request.branches` deliberately — running full CI on every feature branch push is often wasted compute; running it on PRs into `main`/`develop` is usually enough.
- Add `workflow_dispatch:` to every workflow, even fully automated ones — it's a free manual trigger button in the Actions tab, useful for re-running a deploy without an empty commit.
- In a monorepo, use `paths:`/`paths-ignore:` filters so a docs-only or README change doesn't trigger a full test+deploy cycle.
- Cache dependencies with the `cache:` option on `actions/setup-node`/`setup-python`/`setup-go` (or `actions/cache` directly) — this is usually the single biggest speed win available.

## Permissions

- Set `permissions:` explicitly at the top of the workflow (least privilege) rather than relying on the default `GITHUB_TOKEN` scope, which is broader than most workflows need:
  ```yaml
  permissions:
    contents: read
    id-token: write   # only if using OIDC
  ```
- Only grant `contents: write` to jobs that actually push commits/tags (e.g., a release-automation job).

## Testing before deploying

- Always gate the deploy job behind the test job with `needs: test` — a red test run should never be able to reach production.
- Restrict the deploy `if:` condition to the exact branch and event you intend (`github.ref == 'refs/heads/main' && github.event_name == 'push'`) so a PR from a fork can never trigger a deploy with access to your secrets. (Secrets aren't passed to workflows triggered by forked-repo pull requests by default — but being explicit here avoids relying on that alone.)
