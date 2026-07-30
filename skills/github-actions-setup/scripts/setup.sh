#!/usr/bin/env bash
#
# One-command GitHub Actions setup.
#
# Usage:
#   ./setup.sh                    interactive prompts
#   ./setup.sh --deploy=aws       non-interactive
#                                 (aws | vercel | cloudflare | railway | render | server | none)
#   ./setup.sh --lang=node        skip language auto-detection (node | python | go)
#   ./setup.sh --force            overwrite an existing workflow file without asking
#   ./setup.sh --validate         audit existing .github/workflows/*.yml instead of
#                                 generating anything (works on ANY workflow file,
#                                 not just ones this script wrote)
#   ./setup.sh --validate=path/to/file.yml   audit just that one file
#   ./setup.sh --validate --strict           exit non-zero if any warnings are found
#                                 (useful as a CI step or pre-push hook)
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
#
# Security note on deploy targets: AWS authenticates via GitHub OIDC (no
# long-lived keys stored anywhere). Cloudflare, Railway, and Render do not
# currently support OIDC federation from GitHub Actions, so those three use a
# static API token/deploy hook stored as a repo secret instead - a real step
# down in posture from the AWS pattern. Scope those tokens as narrowly as
# each platform allows and rotate them periodically.

set -euo pipefail

WORKFLOW_DIR=".github/workflows"
WORKFLOW_FILE="$WORKFLOW_DIR/ci-cd.yml"
DEPENDABOT_FILE=".github/dependabot.yml"
DEPLOY_TARGET=""
LANG_OVERRIDE=""
FORCE=false
INSTALL_SKILL=false
VALIDATE_MODE=false
VALIDATE_TARGET=""
STRICT=false

for arg in "$@"; do
  case $arg in
    --deploy=*) DEPLOY_TARGET="${arg#*=}" ;;
    --lang=*) LANG_OVERRIDE="${arg#*=}" ;;
    --force) FORCE=true ;;
    --install-skill) INSTALL_SKILL=true ;;
    --validate) VALIDATE_MODE=true ;;
    --validate=*) VALIDATE_MODE=true; VALIDATE_TARGET="${arg#*=}" ;;
    --strict) STRICT=true ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

# --- validate mode -------------------------------------------------------
# Audits existing workflow YAML for the same anti-patterns this script's own
# generated workflows avoid: no explicit `permissions:` (relying on the
# broader default token scope), a deploy-looking job with no `needs:` gate
# (it can run even if tests failed), a deploy-looking job with no `if:`
# restricting it to a specific branch/event (it can fire from any PR,
# including forks), and actions pinned to a mutable `@main`/`@master` tag
# instead of a version or commit SHA (a known GitHub Actions supply-chain
# risk - the tag's contents can change under you). This runs independently
# of everything else in this script and works on any workflow file, not
# just ones this script generated, so it's safe to run as a standalone
# check on a repo you didn't set up with this tool.
validate_workflow_file() {
  local file="$1"
  local warnings=0
  local current_job=""
  local job_is_deploy=false
  local job_has_needs=false
  local job_has_if=false

  report_job() {
    if [ "$job_is_deploy" = true ]; then
      if [ "$job_has_needs" = false ]; then
        echo "  WARN  job '$current_job' looks like a deploy job but has no needs: gate - it can run even if tests fail"
        warnings=$((warnings + 1))
      fi
      if [ "$job_has_if" = false ]; then
        echo "  WARN  job '$current_job' looks like a deploy job but has no if: condition - it may run from any branch or PR, including forks"
        warnings=$((warnings + 1))
      fi
    fi
  }

  echo "Checking $file"

  if grep -qE '^permissions:' "$file"; then
    echo "  OK    explicit top-level permissions: block found"
  else
    echo "  WARN  no top-level permissions: block - relying on the default (broader) token scope"
    warnings=$((warnings + 1))
  fi

  local unpinned_count=0
  while IFS= read -r match_line; do
    [ -z "$match_line" ] && continue
    echo "  WARN  ${match_line# } <- pinned to a mutable @main/@master tag, not a version tag or commit SHA"
    warnings=$((warnings + 1))
    unpinned_count=$((unpinned_count + 1))
  done < <(grep -nE 'uses:[[:space:]]*[^[:space:]]+@(main|master)\b' "$file" || true)
  if [ "$unpinned_count" -eq 0 ]; then
    echo "  OK    all actions pinned to a version tag or SHA"
  fi

  while IFS= read -r line; do
    if [[ "$line" =~ ^\ \ ([A-Za-z0-9_-]+):[[:space:]]*$ ]]; then
      report_job
      current_job="${BASH_REMATCH[1]}"
      job_is_deploy=false
      job_has_needs=false
      job_has_if=false
      if [[ "$current_job" =~ (deploy|publish|release) ]]; then
        job_is_deploy=true
      fi
    elif [[ "$line" =~ needs: ]]; then
      job_has_needs=true
    elif [[ "$line" =~ ^\ \ \ \ if: ]]; then
      job_has_if=true
    fi
  done < "$file"
  report_job

  echo ""
  return "$warnings"
}

if [ "$VALIDATE_MODE" = true ]; then
  TARGETS=()
  if [ -n "$VALIDATE_TARGET" ]; then
    if [ ! -f "$VALIDATE_TARGET" ]; then
      echo "File not found: $VALIDATE_TARGET" >&2
      exit 1
    fi
    TARGETS=("$VALIDATE_TARGET")
  else
    shopt -s nullglob
    TARGETS=(.github/workflows/*.yml .github/workflows/*.yaml)
    shopt -u nullglob
    if [ ${#TARGETS[@]} -eq 0 ]; then
      echo "No workflow files found under .github/workflows/ - nothing to validate." >&2
      exit 1
    fi
  fi

  TOTAL_WARNINGS=0
  for f in "${TARGETS[@]}"; do
    set +e
    validate_workflow_file "$f"
    file_warnings=$?
    set -e
    TOTAL_WARNINGS=$((TOTAL_WARNINGS + file_warnings))
  done

  echo "-----"
  if [ "$TOTAL_WARNINGS" -eq 0 ]; then
    echo "All clear - $TOTAL_WARNINGS warnings across ${#TARGETS[@]} file(s)."
  else
    echo "$TOTAL_WARNINGS warning(s) across ${#TARGETS[@]} file(s)."
  fi

  if [ "$STRICT" = true ] && [ "$TOTAL_WARNINGS" -gt 0 ]; then
    exit 1
  fi
  exit 0
fi

# --- Skill Installer Mode ------------------------------------------------
# When --install-skill is passed, install the skill files directly into the
# project's IDE skill directory (.agents/, .claude/, .void/, etc.) and exit.
# Does NOT ask for deploy targets or generate workflow files.
if [ "$INSTALL_SKILL" = true ]; then
  INTERACTIVE=true
  if [ ! -t 0 ]; then
    if [ -r /dev/tty ] && exec < /dev/tty; then
      :
    else
      INTERACTIVE=false
    fi
  fi
  install_project_skill
  exit 0
fi

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

# Smart stack & framework profile detector. Automatically separates Frontend
# (Next.js, React, Vue.js, Angular, Svelte, Nuxt, Astro) from Backend (NestJS,
# Express, Fastify, Python FastAPI/Django, Go) to recommend the exact deploy target.
detect_stack_profile() {
  case "$LANG_DETECTED" in
    node)
      if [ -f "package.json" ]; then
        if grep -qE '"@nestjs/core"[[:space:]]*:' package.json; then
          echo "backend-nestjs"
        elif grep -qE '"(express|fastify|koa|hapi|@adonisjs/core)"[[:space:]]*:' package.json; then
          echo "backend-node-api"
        elif grep -qE '"next"[[:space:]]*:' package.json; then
          echo "frontend-nextjs"
        elif grep -qE '"(vue|nuxt)"[[:space:]]*:' package.json; then
          echo "frontend-vue"
        elif grep -qE '"@angular/core"[[:space:]]*:' package.json; then
          echo "frontend-angular"
        elif grep -qE '"(react|react-dom|vite|astro|svelte)"[[:space:]]*:' package.json; then
          echo "frontend-react-static"
        else
          echo "node-generic"
        fi
      else
        echo "node-generic"
      fi
      ;;
    python)
      if grep -qsE 'fastapi|flask|django|tornado|sanic' requirements.txt pyproject.toml Pipfile 2>/dev/null; then
        echo "backend-python"
      else
        echo "python-generic"
      fi
      ;;
    go) echo "backend-go" ;;
    *) echo "unknown" ;;
  esac
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
    STACK_PROFILE=$(detect_stack_profile)

    # Recommendation badges only - every option stays selectable regardless.
    # Mapping follows the stack table: node-static -> vercel/cloudflare,
    # node-api -> railway/render/server, python-web -> render/railway/server,
    # go-web -> railway/render/server. Ambiguous profiles show no badge.
    REC_VERCEL=""; REC_CLOUDFLARE=""; REC_RAILWAY=""; REC_RENDER=""; REC_SERVER=""
    case "$STACK_PROFILE" in
      frontend-nextjs|frontend-vue|frontend-angular|frontend-react-static)
        REC_VERCEL=" (Recommended for Frontend)"
        REC_CLOUDFLARE=" (Recommended for Frontend)"
        ;;
      backend-nestjs|backend-node-api|backend-python|backend-go)
        REC_RAILWAY=" (Recommended for Backend)"
        REC_RENDER=" (Recommended for Backend)"
        REC_SERVER=" (Recommended for Backend)"
        ;;
    esac

    echo ""
    echo "Where should this project deploy to?"
    echo "  1) AWS (S3 + CloudFront)"
    echo "  2) Vercel${REC_VERCEL}"
    echo "  3) Cloudflare Pages/Workers${REC_CLOUDFLARE}"
    echo "  4) Railway${REC_RAILWAY}"
    echo "  5) Render${REC_RENDER}"
    echo "  6) Generic server (SSH)${REC_SERVER}"
    echo "  7) None (tests only)"
    read -rp "Choose [1-7]: " choice
    case $choice in
      1) DEPLOY_TARGET="aws" ;;
      2) DEPLOY_TARGET="vercel" ;;
      3) DEPLOY_TARGET="cloudflare" ;;
      4) DEPLOY_TARGET="railway" ;;
      5) DEPLOY_TARGET="render" ;;
      6) DEPLOY_TARGET="server" ;;
      7) DEPLOY_TARGET="none" ;;
      *) echo "Invalid choice" >&2; exit 1 ;;
    esac
  else
    echo "No terminal available to prompt for a deploy target." >&2
    echo "Re-run with --deploy=aws|vercel|cloudflare|railway|render|server|none, e.g.:" >&2
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
  cloudflare)
    DEPLOY_JOB=$(cat <<'EOF'

  deploy:
    name: Deploy to Cloudflare Pages
    needs: test
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    runs-on: ubuntu-latest
    environment: production
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20.x'
          cache: 'npm'
      - run: npm ci
      - run: npm run build --if-present
      # Uses a scoped Cloudflare API Token (Account.Cloudflare Pages:Edit),
      # not OIDC - Cloudflare does not support GitHub OIDC federation yet.
      - name: Deploy to Cloudflare Pages
        uses: cloudflare/wrangler-action@v3
        with:
          apiToken: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          accountId: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
          command: pages deploy ./dist --project-name=${{ secrets.CLOUDFLARE_PROJECT_NAME }}
EOF
)
    SECRETS_NEEDED="CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID, CLOUDFLARE_PROJECT_NAME"
    ;;
  railway)
    DEPLOY_JOB=$(cat <<'EOF'

  deploy:
    name: Deploy to Railway
    needs: test
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    runs-on: ubuntu-latest
    environment: production
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v4
      # Uses the official Railway CLI authenticated with a project token, not
      # OIDC - Railway does not support GitHub OIDC federation yet.
      - name: Install Railway CLI
        run: npm install -g @railway/cli
      - name: Deploy
        env:
          RAILWAY_TOKEN: ${{ secrets.RAILWAY_TOKEN }}
        run: railway up --service "${{ secrets.RAILWAY_SERVICE }}"
EOF
)
    SECRETS_NEEDED="RAILWAY_TOKEN, RAILWAY_SERVICE"
    ;;
  render)
    DEPLOY_JOB=$(cat <<'EOF'

  deploy:
    name: Deploy to Render
    needs: test
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    runs-on: ubuntu-latest
    environment: production
    permissions:
      contents: read
    steps:
      # Render deploy hooks trigger a deploy of whatever Render already has
      # connected/configured for this service - no checkout needed here, and
      # no OIDC support from Render yet, so the hook URL itself is the secret.
      - name: Trigger Render deploy hook
        run: curl -fsSL -X POST "${{ secrets.RENDER_DEPLOY_HOOK_URL }}"
EOF
)
    SECRETS_NEEDED="RENDER_DEPLOY_HOOK_URL"
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
    *) ECOSYSTEM="npm" ;;  # unreachable in practice (LANG_DETECTED is already
                           # validated above), kept as an explicit no-op default
                           # rather than an implicit fallthrough
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

case "$DEPLOY_TARGET" in
  cloudflare|railway|render)
    echo ""
    echo "Note: $DEPLOY_TARGET deploys with a static API token/hook URL, not"
    echo "OIDC (that platform doesn't support GitHub OIDC federation yet)."
    echo "Scope it as narrowly as the platform allows and rotate it periodically."
    ;;
esac

# --- IDE / Agent Skill Installer -----------------------------------------
# Opt-in installation into project-level AI assistant skill directories.
# Never runs silently in non-interactive mode unless --install-skill is passed.
install_project_skill() {
  # Determine target directory based on existing markers or prompt
  local target_dir=""
  local detected_dirs=()

  [ -d ".claude/skills" ] && detected_dirs+=(".claude/skills")
  [ -d ".windsurf/skills" ] && detected_dirs+=(".windsurf/skills")
  [ -d ".void/skills" ] && detected_dirs+=(".void/skills")
  [ -d ".kiro/skills" ] && detected_dirs+=(".kiro/skills")
  [ -d ".codex/skills" ] && detected_dirs+=(".codex/skills")
  [ -d ".qoder/skills" ] && detected_dirs+=(".qoder/skills")
  [ -d ".agent/skills" ] && detected_dirs+=(".agent/skills")
  [ -d ".agents/skills" ] && detected_dirs+=(".agents/skills")

  if [ ${#detected_dirs[@]} -eq 1 ]; then
    target_dir="${detected_dirs[0]}"
  elif [ ${#detected_dirs[@]} -gt 1 ]; then
    if [ "$INTERACTIVE" = true ]; then
      echo ""
      echo "Multiple IDE skill directories found:"
      local idx=1
      for d in "${detected_dirs[@]}"; do
        echo "  $idx) $d"
        idx=$((idx + 1))
      done
      read -rp "Choose target [1-${#detected_dirs[@]}]: " sel
      if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "${#detected_dirs[@]}" ]; then
        target_dir="${detected_dirs[$((sel - 1))]}"
      else
        target_dir="${detected_dirs[0]}"
      fi
    else
      target_dir="${detected_dirs[0]}"
    fi
  else
    if [ "$INTERACTIVE" = true ]; then
      echo ""
      echo "Select IDE skill root format to install to:"
      echo "  1) .agents/skills  (Cursor, GitHub Copilot, Gemini CLI, Amp, Cline, Warp)"
      echo "  2) .agent/skills   (Antigravity)"
      echo "  3) .claude/skills  (Claude Code)"
      echo "  4) .void/skills    (Void IDE)"
      echo "  5) .windsurf/skills (Windsurf)"
      echo "  6) .kiro/skills    (Kiro)"
      echo "  7) .codex/skills   (Codex / OpenAI)"
      echo "  8) .qoder/skills   (Qoder)"
      read -rp "Choose [1-8] (default: 1): " choice
      case $choice in
        1|"") target_dir=".agents/skills" ;;
        2) target_dir=".agent/skills" ;;
        3) target_dir=".claude/skills" ;;
        4) target_dir=".void/skills" ;;
        5) target_dir=".windsurf/skills" ;;
        6) target_dir=".kiro/skills" ;;
        7) target_dir=".codex/skills" ;;
        8) target_dir=".qoder/skills" ;;
        *) target_dir=".agents/skills" ;;
      esac
    else
      target_dir=".agents/skills"
    fi
  fi

  local skill_name="github-actions-setup"
  local skill_dest="$target_dir/$skill_name"

  if [ -d "$skill_dest" ] && [ "$FORCE" = false ]; then
    if [ "$INTERACTIVE" = true ]; then
      echo ""
      echo "Skill at $skill_dest already exists."
      echo "  1) Overwrite existing skill ($skill_dest)"
      echo "  2) Create a new skill with a custom folder name"
      echo "  3) Cancel"
      read -rp "Choose [1-3] (default: 1): " ow_choice
      case $ow_choice in
        2)
          read -rp "Enter new skill name (e.g. github-actions-setup-v2): " custom_name
          if [ -n "$custom_name" ]; then
            skill_name="$custom_name"
            skill_dest="$target_dir/$skill_name"
          fi
          ;;
        3)
          echo "Installation cancelled."
          return 0
          ;;
        *)
          # Overwrite chosen
          ;;
      esac
    else
      echo "Skill at $skill_dest already exists. Pass --force to overwrite." >&2
      return 0
    fi
  fi

  # Find origin skill directory
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local skill_src
  skill_src="$(cd "$script_dir/.." && pwd)"

  mkdir -p "$skill_dest"
  if [ -f "$skill_src/SKILL.md" ]; then
    cp -R "$skill_src/"* "$skill_dest/" 2>/dev/null || cp -r "$skill_src/"* "$skill_dest/"
    echo ""
    echo "Skill installed to $skill_dest"
    echo "Tip: Consider adding '$target_dir/' to your .gitignore if you don't want internal skill docs committed."
  else
    # Running via remote curl pipe (curl | bash): fetch SKILL.md, scripts, and references from remote repository
    echo "Fetching skill files from GitHub repository..."
    local raw_base="https://raw.githubusercontent.com/khemratechconsulting/github-actions-setup/main/skills/github-actions-setup"
    
    mkdir -p "$skill_dest/scripts" "$skill_dest/references" "$skill_dest/assets/workflows"
    curl -fsSL "$raw_base/SKILL.md" -o "$skill_dest/SKILL.md"
    curl -fsSL "$raw_base/scripts/setup.sh" -o "$skill_dest/scripts/setup.sh" && chmod +x "$skill_dest/scripts/setup.sh"
    curl -fsSL "$raw_base/references/best-practices.md" -o "$skill_dest/references/best-practices.md" 2>/dev/null || true
    curl -fsSL "$raw_base/references/guide.md" -o "$skill_dest/references/guide.md" 2>/dev/null || true

    echo ""
    echo "🎉 Skill successfully installed to $skill_dest"
    echo ""
    echo "How to use it in your IDE (Claude Code, Cursor, Windsurf, Antigravity):"
    echo "  Ask your AI assistant in chat:"
    echo "    - \"Set up GitHub Actions CI/CD for this project\""
    echo "    - \"Audit our .github/workflows/ci-cd.yml for security issues\""
    echo "    - \"Add automated deployment to Vercel / Cloudflare / Railway\""
    echo ""
    echo "Tip: Consider adding '$target_dir/' to your .gitignore if you don't want internal skill docs committed."
  fi
}

