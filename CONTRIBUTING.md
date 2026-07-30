# Contributing

Thanks for considering a contribution.

## Reporting bugs / requesting a deploy target

Open an issue with: what you ran, what you expected, what happened instead. For a new deploy target request, mention the platform and, if you can, a link to its official GitHub Action.

## Submitting a change

1. Fork the repo and create a branch from `main`.
2. If you're changing a workflow template, validate it parses as YAML and, ideally, test it against a throwaway repo before opening the PR.
3. If you're changing `setup.sh`, run it against a sample Node/Python/Go project locally for each deploy target before submitting.
4. Open a PR describing the change and why. Small, focused PRs get reviewed faster than large ones.

## Scope

This project intentionally stays narrow: language auto-detection (Node/Python/Go) and a small set of well-tested deploy targets, rather than trying to cover every possible platform. New deploy targets are welcome as long as they follow the existing pattern (test job gates deploy job, secrets documented in a header comment, environment-gated production deploy).
