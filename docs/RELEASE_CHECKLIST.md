# Release Checklist

Run these checks before every public push.

## 1) Secret scan (must be clean)

```bash
cd <repo-root>
rg -n --hidden -g '!**/.git/**' -g '!external/**' \
  -e 'github_pat_[A-Za-z0-9_]{40,}' \
  -e '\bghp_[A-Za-z0-9]{30,}\b' \
  -e 'GITHUB_TOKEN=(ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})' \
  -e 'OPENAI_API_KEY=sk-[A-Za-z0-9-]{20,}'
```

## 2) Path portability scan (must be clean)

```bash
cd <repo-root>
rg -n --hidden -g '!**/.git/**' -g '!external/**' \
  -e '/home/t[a]oduo0428' \
  -e '/mnt/c/Users/[4]8842' \
  -e 'C:\\Users\\[4]8842' \
  -e 't[a]oduo0428'
```

## 3) WSL syntax/runtime baseline

```bash
cd <repo-root>
find wsl -type f -name '*.sh' -print0 | xargs -0 -I{} bash -n {}

# Optional runtime checks on a real WSL machine
bash ~/.agents/automation/scripts/validate_global_runtime.sh --expected-workspace-path "/path/to/workspace"
bash ~/.agents/automation/scripts/run_smoke_prompts.sh --workspace-path "/path/to/workspace" --timeout-seconds 120 --retry-attempts 2
```

## 4) Windows PowerShell parse checks

```powershell
$files = @(
  "win/bootstrap_fresh_global_full.ps1"
) + (Get-ChildItem "common/claude-code-main/scripts" -Filter *.ps1 | ForEach-Object FullName) +
    (Get-ChildItem "common/claude-code-main/dist/global-plugins" -Filter *.ps1 | ForEach-Object FullName)

$failed = $false
foreach ($f in $files) {
  $tokens = $null
  $errors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$errors)
  if ($errors.Count -gt 0) {
    Write-Host "[FAIL] $f" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host $_.Message -ForegroundColor Red }
    $failed = $true
  }
}
if ($failed) { exit 1 }
```

## 5) Doc consistency spot-check

Ensure all examples use:

- `common/claude-code-main` as `RepoRoot`
- clear `WorkspacePath` placeholders
- `external/*` for optional enhanced modules
- submodule behavior note aligned with scripts: missing `external/*` triggers auto-attempt `git submodule update --init --recursive` (unless skip-submodule-init is used)
- no local machine absolute paths

## 6) Placeholder metadata check

Before final release tag, replace placeholder repository metadata:

- search `https://github.com/<ORG>/<REPO>` and replace with real public repo URL where appropriate
- verify plugin metadata fields (`homepage`, `repository`, `websiteURL`) are not left as stale placeholders unless intentionally documented

Quick check:

```bash
cd <repo-root>
rg -n --hidden -g '!**/.git/**' 'https://github.com/<ORG>/<REPO>'
```
