param(
  [string]$CommitMessage = "",
  [string]$GitPath = "C:\Program Files\Git\cmd\git.exe"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $root) { $root = Get-Location }
Set-Location $root

if (-not (Test-Path $GitPath)) {
  $GitPath = "git"
}

if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
  $CommitMessage = "Update daily finance report $(Get-Date -Format 'yyyy-MM-dd')"
}

& powershell -ExecutionPolicy Bypass -File (Join-Path $root "update-report-index.ps1") | Out-Null
& powershell -ExecutionPolicy Bypass -File (Join-Path $root "build-pages-site.ps1") | Out-Null

& $GitPath add .
$staged = & $GitPath diff --cached --name-only
if ([string]::IsNullOrWhiteSpace(($staged -join "`n"))) {
  Write-Host "No changes to commit."
} else {
  & $GitPath commit -m $CommitMessage
}

$branch = (& $GitPath branch --show-current).Trim()
if ([string]::IsNullOrWhiteSpace($branch)) { $branch = "main" }
& $GitPath push -u origin $branch

Write-Host "Published report site to origin/$branch"
