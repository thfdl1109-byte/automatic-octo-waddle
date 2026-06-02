param(
  [string]$ReportsDir = ".",
  [string]$OutDir = "reports",
  [string]$LatestPattern = "*daily-global-finance-report.md"
)

$ErrorActionPreference = "Continue"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $root) { $root = Get-Location }
Set-Location $root

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$candidates = @()
$searchDirs = @(
  (Join-Path $root "daily-reports-2026-01-01_2026-06-02"),
  $root
) | Where-Object { Test-Path $_ }

foreach ($dir in $searchDirs) {
  $candidates += Get-ChildItem -Path $dir -Filter $LatestPattern -File -ErrorAction SilentlyContinue
  $candidates += Get-ChildItem -Path $dir -Filter "*investment-report.md" -File -ErrorAction SilentlyContinue
}

$reports = $candidates |
  Where-Object { $_.Name -match "^\d{4}-\d{2}-\d{2}" } |
  Sort-Object FullName -Unique |
  ForEach-Object {
    $date = if ($_.Name -match "^(\d{4}-\d{2}-\d{2})") { $matches[1] } else { "" }
    $_ | Add-Member -NotePropertyName report_date -NotePropertyValue $date -Force
    $_
  } |
  Group-Object report_date |
  ForEach-Object {
    $_.Group | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  } |
  Sort-Object report_date -Descending

$indexItems = foreach ($r in $reports) {
  [pscustomobject]@{
    date = $r.report_date
    name = $r.Name
    path = $r.FullName
    updated_at = $r.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
    bytes = $r.Length
  }
}

$latest = $indexItems | Select-Object -First 1
$out = [pscustomobject]@{
  generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  latest = $latest
  reports = @($indexItems)
  derived = @(
    [pscustomobject]@{ name = "fetch_summary"; path = (Join-Path $root "data\logs\latest-fetch-summary.json") },
    [pscustomobject]@{ name = "interesting_stocks"; path = (Join-Path $root "data\derived\us-interesting-stocks.json") },
    [pscustomobject]@{ name = "macro_snapshot"; path = (Join-Path $root "data\derived\macro-snapshot.json") },
    [pscustomobject]@{ name = "news_digest"; path = (Join-Path $root "data\derived\news-digest.json") },
    [pscustomobject]@{ name = "market_breadth"; path = (Join-Path $root "data\derived\market-breadth.json") }
  )
}

$indexPath = Join-Path $OutDir "index.json"
$out | ConvertTo-Json -Depth 10 | Set-Content -Path $indexPath -Encoding UTF8

if ($latest -and (Test-Path $latest.path)) {
  Copy-Item -LiteralPath $latest.path -Destination (Join-Path $OutDir "latest.md") -Force
}

Write-Host "Wrote $indexPath and latest.md"
