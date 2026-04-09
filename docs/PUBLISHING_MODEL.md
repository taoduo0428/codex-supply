# Publishing Model (Open-Source Boundary)

This document defines exactly what should be public, what should stay local, and why.

## 1) Public repository root

Publish only the `GitHub上线` directory as your GitHub repository root.

Why:
- `GitHub上线` is the curated distribution bundle (scripts + docs + compliance notes).
- `源码工程` is your local source workspace and may contain internal history, experiments, or non-distribution assets.

## 2) What to publish

Required:
- `win/`
- `wsl/`
- `common/`
- `docs/`
- `.github/`
- `README.md`, `README.zh-CN.md`
- `LICENSE`, `SECURITY.md`, `THIRD_PARTY_NOTICES.md`, `CONTRIBUTING.md`, `.gitignore`
- `.gitmodules`

## 3) What not to publish

Do not publish local runtime state or private workspace artifacts:
- `~/.codex`
- `~/.agents`
- real `.env` secrets and any token-bearing files
- private workspaces such as `源码工程` and unrelated local folders

## 4) Why external submodules are transparent

`external/*` is intentionally transparent:
- It preserves upstream attribution and license traceability.
- It allows downstream users to audit provenance and updates.
- Hiding or renaming origin does not remove legal obligations.

## 5) If you want a lighter public repo

Supported low-risk options:
- Keep submodules but document them as optional.
- Publish without initializing submodules; bootstrap can auto-attempt init when needed.
- Keep third-party notices updated.

High-risk option to avoid:
- Copying selected upstream files without full attribution/license context.

## 6) Release checklist tie-in

Before public push:
1. Run secret/path scans.
2. Run shell and PowerShell parse checks.
3. Confirm docs and plugin metadata placeholders are ready.
4. Confirm only `GitHub上线` content is being pushed.
