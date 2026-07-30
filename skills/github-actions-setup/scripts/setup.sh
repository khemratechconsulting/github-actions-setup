#!/usr/bin/env bash
#
# One-command GitHub Actions setup.
#
# Usage:
#   ./setup.sh                    interactive prompts
#   ./setup.sh --deploy=aws       non-interactive (aws | vercel | server | none)
#   ./setup.sh --lang=node        skip language auto-detection (node | python | go)
#   ./setup.sh --force            overwrite an existing workflow file without asking
#
# Recommended ways to run this remotely (see README for why this matters):
#   bash <(curl -fsSL <raw-url>)
#   bash -c "$(curl -fsSL <raw-url>)"
# Both keep your real terminal attached to stdin, so the prompts below work.
# Piping straight into bash (`curl ... | bash`) still works for the fully
# non-interactive case (pass --deploy=/--lang=/--force), but interactive
# prompts fall back to /dev/tty automatically - see the block below.
#
# Run this from your project root. It detects your project's language from
# files already in the directory (package.json -> Node, requirements.txt /
# pyproject.toml -> Python, go.mod -> Go), asks (or takes as a flag) which
# environment to deploy to, and writes .github/workflows/ci-cd.yml plus
# .github/dependabot.yml. Safe to re-run - it asks before overwriting.

set -euo pipefail

WORKFLOW_DIR=".github/workflows"
WORKFLOW_FILE="$WORKFLOW_DIR/ci-cd.yml"
DEPENDABOT_FILE=".github/dependabot.yml"
DEPLOY_TARGET=""
LANG_OVERRIDE=""
FORCE=false

for arg in "$@"; do
  case $arg in
    --deploy=*) DEPLOY_TARGET="${arg#*=}" ;;
    --lang=*) LANG_OVERRIDE="${arg#*=}" ;;
    --force) FORCE=true ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

# --- stdin/tty handling -------------------------------------------------
# When this script runs via `curl ... | bash`, bash's stdin (fd 0) is the
# pipe carrying the script's own source - not your terminal. Any `read`
# below would read from that pipe, find it already at EOF, and return
# immediately with an empty value instead of waiting for a keypress. That's
# the "Invalid choice" you see with no visible pause: `read` got "" back,
# it matched no case, and the script exited before you could type anything.
#
# Fix: if stdin isn't a terminal but a real one is reachable at /dev/tty,
# redirect our stdin there for the rest of the script, so every `read`
# below waits on your actual keyboard again. If there's truly no terminal
# available (CI runners, some containers), INTERACTIVE is set to false and
# every prompt below falls back to requiring the matching flag instead of
# hanging or silently choosing wrong.
INTERACTIVE=true
if [ ! -t 0 ]; then
  if [ -r /dev/tty ] && exec < /dev/tty; then
    :
  else
    INTERACTIVE=false
  fi
fi

detect_language() {
  if [ -f "package.json" ]; then echo "node"
  elif [ -f "requirements.txt" ] || [ -f "pyproject.toml" ]; then echo "python"
  elif [ -f "go.mod" ]; then echo "go"
  else echo "unknown"
  fi
}

if [ -n "$LANG_OVERRIDE" ]; then
  LANG_DETECTED="$LANG_OVERRIDE"
  echo "Using language: $LANG_DETECTED (from --lang)"
else
  LANG_DETECTED=$(detect_language)
  echo "Detected project language: $LANG_DETECTED"
fi

if [ "$LANG_DETECTED" = "unknown" ]; then
  echo "Could not auto-detect a language from package.json / requirements.txt / pyproject.toml / go.mod."
  if [ "$INTERACTIVE" = true ]; then
    read -rp "Enter language to use for the test job [node/python/go] (default: node): " LANG_DETECTED
    LANG_DETECTED=${LANG_DETECTED:-node}
  else
    echo "No terminal available to ask - defaulting to node." >&2
    echo "Pass --lang=node|python|go next time to be explicit." >&2
    LANG_DETECTED="node"
  fi
fi

if [ -z "$DEPLOY_TARGET" ]; then
  if [ "$INTERACTIVE" = true ]; then
    echo ""
    echo "Where should this project deploy to?"
    echo "  1) AWS (S3 + CloudFront)"
    echo "  2) Vercel"
    echo "  3) Generic server (SSH)"
    echo "  4) None (tests only)"
    read -rp "Choose [1-4]: " choice
    case $choice in
      1) DEPLOY_TARGET="aws" ;;
      2) DEPLOY_TARGET="vercel" ;;
      3) DEPLOY_TARGET="server" ;;
      4) DEPLOY_TARGET="none" ;;
      *) echo "Invalid choice" >&2; exit 1 ;;
    esac
  else
    echo "No terminal available to prompt for a deploy target." >&2
    echo "Re-run with --deploy=aws|vercel|server|none, e.g.:" >&2
    echo '  curl -fsSL <raw-url> | bash -s -- --deploy=vercel' >&2
    exit 1
  fi
fi

mkdir -p "$WORKFLOW_DIR"

if [ -f "$WORKFLOW_FILE" ]; then
  if [ "$FORCE" = true ]; then
    : # overwrite without asking
  elif [ "$INTERACTIVE" = true ]; then
    read -rp "$WORKFLOW_FILE already exists. Overwrite? [y/N]: " overwrite
    if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
      echo "Aborted. No files changed."
      exit 0
    fi
  else
    echo "$WORKFLOW_FILE already exists and no terminal is available to confirm overwrite." >&2
    echo "Re-run with --force to overwrite non-interactively." >&2
    exit 1
  fi
fi

build_test_job_node() {
cat <<'EOF'
  test:
    name: Test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20.x'
          cache: 'npm'
      - run: npm ci
      - run: npm run lint --if-present
      - run: npm test --if-present
EOF
}

build_test_job_python() {
cat <<'EOF'
  test:
    name: Test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'
          cache: 'pip'
      - run: pip install -r requirements.txt
      - run: pip install pytest flake8
      - run: flake8 . || true
      - run: pytest
EOF
}

build_test_job_go() {
cat <<'EOF'
  test:
    name: Test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version: '1.22'
          cache: true
      - run: go build ./...
      - run: go test ./...
EOF
}

case $LANG_DETECTED in
  node) TEST_JOB=$(build_test_job_node) ;;
  python) TEST_JOB=$(build_test_job_python) ;;
  go) TEST_JOB=$(build_test_job_go) ;;
  *) echo "Unsupported language: $LANG_DETECTED" >&2; exit 1 ;;
esac

DEPLOY_JOB=""
SECRETS_NEEDED=""

case $DEPLOY_TARGET in
  aws)
    DEPLOY_JOB=$(cat <<'EOF'

  deploy:
    name: Deploy to AWS
    needs: test
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    runs-on: ubuntu-latest
    environment: production
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_DEPLOY_ROLE_ARN }}
          aws-region: ${{ secrets.AWS_REGION }}
      - name: Sync build output to S3
        run: aws s3 sync ./dist "s3://${{ secrets.AWS_S3_BUCKET }}" --delete
      - name: Invalidate CloudFront cache
        run: |
          aws cloudfront create-invalidation \
            --distribution-id "${{ secrets.AWS_CLOUDFRONT_DISTRIBUTION_ID }}" \
            --paths "/*"
EOF
)
    SECRETS_NEEDED="AWS_DEPLOY_ROLE_ARN, AWS_REGION, AWS_S3_BUCKET, AWS_CLOUDFRONT_DISTRIBUTION_ID"
    ;;
  vercel)
    DEPLOY_JOB=$(cat <<'EOF'

  deploy:
    name: Deploy to Vercel
    needs: test
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4
      - uses: amondnet/vercel-action@v25
        with:
          vercel-token: ${{ secrets.VERCEL_TOKEN }}
          vercel-org-id: ${{ secrets.VERCEL_ORG_ID }}
          vercel-project-id: ${{ secrets.VERCEL_PROJECT_ID }}
          vercel-args: '--prod'
EOF
)
    SECRETS_NEEDED="VERCEL_TOKEN, VERCEL_ORG_ID, VERCEL_PROJECT_ID"
    ;;
  server)
    DEPLOY_JOB=$(cat <<'EOF'

  deploy:
    name: Deploy via SSH
    needs: test
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    runs-on: ubuntu-latest
    environment: production
    steps:
      - name: Deploy to server
        uses: appleboy/ssh-action@v1.0.3
        with:
          host: ${{ secrets.SERVER_HOST }}
          username: ${{ secrets.SERVER_USER }}
          key: ${{ secrets.SERVER_SSH_KEY }}
          port: ${{ secrets.SERVER_PORT || 22 }}
          script: |
            cd /var/www/${{ github.event.repository.name }}
            git pull origin main
            npm ci --omit=dev
            npm run build --if-present
            pm2 restart ${{ github.event.repository.name }} || pm2 start npm --name "${{ github.event.repository.name }}" -- start
EOF
)
    SECRETS_NEEDED="SERVER_HOST, SERVER_USER, SERVER_SSH_KEY (SERVER_PORT optional, defaults to 22)"
    ;;
  none)
    DEPLOY_JOB=""
    SECRETS_NEEDED="(none - test-only workflow)"
    ;;
  *)
    echo "Unknown deploy target: $DEPLOY_TARGET" >&2
    exit 1
    ;;
esac

{
  echo "name: CI/CD"
  echo ""
  echo "on:"
  echo "  push:"
  echo "    branches: [main]"
  echo "  pull_request:"
  echo "    branches: [main]"
  echo "  workflow_dispatch:"
  echo ""
  echo "concurrency:"
  echo "  group: ci-cd-\${{ github.ref }}"
  echo "  cancel-in-progress: true"
  echo ""
  echo "permissions:"
  echo "  contents: read"
  echo ""
  echo "jobs:"
  echo "$TEST_JOB"
  echo "$DEPLOY_JOB"
} > "$WORKFLOW_FILE"

if [ ! -f "$DEPENDABOT_FILE" ]; then
  case $LANG_DETECTED in
    node) ECOSYSTEM="npm" ;;
    python) ECOSYSTEM="pip" ;;
    go) ECOSYSTEM="gomod" ;;
  esac
  cat > "$DEPENDABOT_FILE" <<EOF
version: 2
updates:
  - package-ecosystem: "$ECOSYSTEM"
    directory: "/"
    schedule:
      interval: "weekly"
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
EOF
fi

echo ""
echo "Done. Created:"
echo "  - $WORKFLOW_FILE"
echo "  - $DEPENDABOT_FILE"
echo ""
echo "Language: $LANG_DETECTED | Deploy target: $DEPLOY_TARGET"
echo ""
echo "Before your first push, add these secrets under"
echo "Settings > Secrets and variables > Actions:"
echo "  $SECRETS_NEEDED"
echo ""
if [ "$DEPLOY_TARGET" != "none" ]; then
  echo "Also create a 'production' environment under Settings > Environments"
  echo "(optionally with a required reviewer) - the deploy job targets it."
fi
