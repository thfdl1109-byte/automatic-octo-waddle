Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$fetchScript = Join-Path $root "fetch-market-data.ps1"
$summaryScript = Join-Path $root "summarize-report-inputs.ps1"

if (-not (Test-Path -LiteralPath $fetchScript)) {
  throw "Missing fetch script: $fetchScript"
}

if (-not (Test-Path -LiteralPath $summaryScript)) {
  throw "Missing summary script: $summaryScript"
}

Write-Host "RUN_DAILY_REPORT_DATA_REFRESH start"
& powershell -NoProfile -ExecutionPolicy Bypass -File $fetchScript

Write-Host "RUN_DAILY_REPORT_DATA_REFRESH summarize"
& powershell -NoProfile -ExecutionPolicy Bypass -File $summaryScript

Write-Host "RUN_DAILY_REPORT_DATA_REFRESH done"
