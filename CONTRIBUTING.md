# Contributing

## Workflow

1. Fork or create a branch.
2. Keep changes minimal and scoped.
3. Run local checks before PR.
4. Open PR with verification output.

## Required local checks

```bash
# secret/path scan
rg -n --hidden -g '!**/.git/**' -g '!external/**' "github_pat_[A-Za-z0-9_]{40,}|\\bghp_[A-Za-z0-9]{30,}\\b|GITHUB_TOKEN=(ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})|OPENAI_API_KEY=sk-[A-Za-z0-9-]{20,}|/home/t[a]oduo0428|/mnt/c/Users/[4]8842|C:\\\\Users\\\\[4]8842|t[a]oduo0428" .

# bash syntax
find wsl -type f -name "*.sh" -print0 | xargs -0 -I{} bash -n {}
```

```powershell
# PowerShell parse checks
$files = @(
  "win/bootstrap_fresh_global_full.ps1"
) + (Get-ChildItem "common/claude-code-main/scripts" -Filter *.ps1 | ForEach-Object FullName)

$failed = $false
foreach ($f in $files) {
  $tokens = $null
  $errors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$errors)
  if ($errors.Count -gt 0) {
    Write-Host "[FAIL] $f" -ForegroundColor Red
    $failed = $true
  }
}
if ($failed) { exit 1 }
```

## PR checklist

- No machine-specific paths in docs/examples
- No plaintext secrets
- Win/WSL docs consistent with `common/` and `external/`
- CI green
