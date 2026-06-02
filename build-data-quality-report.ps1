param(
  [string]$LogsDir = "data\logs",
  [string]$DerivedDir = "data\derived",
  [string]$ReportsDir = "reports"
)

$ErrorActionPreference = "Continue"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $root) { $root = Get-Location }
Set-Location $root

New-Item -ItemType Directory -Force -Path $DerivedDir | Out-Null

$warnings = New-Object System.Collections.Generic.List[object]

function Add-Warning {
  param([string]$Level, [string]$Code, [string]$Message)
  $warnings.Add([pscustomobject]@{ level = $Level; code = $Code; message = $Message }) | Out-Null
}

function Read-JsonSafe {
  param([string]$Path)
  if (-not (Test-Path $Path)) { return $null }
  try { return Get-Content -Raw -Encoding UTF8 $Path | ConvertFrom-Json } catch { return $null }
}

$summary = Read-JsonSafe (Join-Path $LogsDir "latest-fetch-summary.json")
if ($summary) {
  if ($summary.counts.err -ge 5) {
    Add-Warning "high" "many_fetch_errors" "Fetch had $($summary.counts.err) errors."
  } elseif ($summary.counts.err -gt 0) {
    Add-Warning "medium" "some_fetch_errors" "Fetch had $($summary.counts.err) errors."
  }
} else {
  Add-Warning "high" "missing_fetch_summary" "latest-fetch-summary.json is missing."
}

$stocks = Read-JsonSafe (Join-Path $DerivedDir "us-interesting-stocks.json")
if ($stocks -and $stocks.selected) {
  $stockCount = @($stocks.selected).Count
  if ($stockCount -lt 10) { Add-Warning "medium" "few_interesting_stocks" "Only $stockCount interesting stocks selected." }
} else {
  Add-Warning "high" "missing_interesting_stocks" "us-interesting-stocks.json is missing or empty."
}

$macro = Read-JsonSafe (Join-Path $DerivedDir "macro-snapshot.json")
if ($macro -and $macro.items) {
  $macroCount = @($macro.items).Count
  $staleCount = @($macro.items | Where-Object { $_.stale }).Count
  if ($macroCount -lt 5) { Add-Warning "medium" "few_macro_items" "Only $macroCount macro items available." }
  if ($staleCount -gt 0) { Add-Warning "medium" "stale_macro_items" "$staleCount macro items are stale." }
} else {
  Add-Warning "high" "missing_macro_snapshot" "macro-snapshot.json is missing or empty."
}

$news = Read-JsonSafe (Join-Path $DerivedDir "news-digest.json")
if ($news -and $news.selected) {
  $newsCount = @($news.selected).Count
  if ($newsCount -lt 8) { Add-Warning "medium" "few_news_items" "Only $newsCount quality news items selected." }
} else {
  Add-Warning "medium" "missing_news_digest" "news-digest.json is missing or empty."
}

$breadth = Read-JsonSafe (Join-Path $DerivedDir "market-breadth.json")
if ($breadth) {
  if ($breadth.available_quotes -lt 4) { Add-Warning "medium" "thin_breadth_data" "Only $($breadth.available_quotes) breadth quotes available." }
} else {
  Add-Warning "medium" "missing_market_breadth" "market-breadth.json is missing."
}

$index = Read-JsonSafe (Join-Path $ReportsDir "index.json")
if (-not $index -or -not $index.latest) {
  Add-Warning "medium" "missing_report_index" "reports/index.json is missing or has no latest report."
}

$score = 100
foreach ($w in $warnings) {
  if ($w.level -eq "high") { $score -= 25 }
  elseif ($w.level -eq "medium") { $score -= 10 }
  else { $score -= 5 }
}
if ($score -lt 0) { $score = 0 }
$status = if ($score -ge 85) { "good" } elseif ($score -ge 65) { "usable" } else { "degraded" }

$out = [pscustomobject]@{
  generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  score = $score
  status = $status
  warnings = @($warnings.ToArray())
}

$jsonPath = Join-Path $DerivedDir "data-quality.json"
$mdPath = Join-Path $DerivedDir "data-quality.md"
$out | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Data Quality") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("Generated at: $($out.generated_at)") | Out-Null
$lines.Add("Status: $($out.status)") | Out-Null
$lines.Add("Score: $($out.score)") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Level | Code | Message |") | Out-Null
$lines.Add("| --- | --- | --- |") | Out-Null
foreach ($w in $out.warnings) {
  $lines.Add("| $($w.level) | $($w.code) | $($w.message) |") | Out-Null
}
if ($out.warnings.Count -eq 0) {
  $lines.Add("| ok | none | No quality warnings. |") | Out-Null
}
$lines | Set-Content -Path $mdPath -Encoding UTF8

Write-Host "Wrote $jsonPath and $mdPath"
