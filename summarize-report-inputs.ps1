Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$derived = Join-Path $root "data\derived"
$logs = Join-Path $root "data\logs"
$outDir = Join-Path $derived "automation"
$outPath = Join-Path $outDir "latest-report-input-summary.json"

New-Item -ItemType Directory -Force -Path $outDir | Out-Null

function Read-JsonFile {
  param(
    [Parameter(Mandatory = $true)][string]$Path
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    return $null
  }

  try {
    return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
  } catch {
    return [pscustomobject]@{
      _readError = $_.Exception.Message
      _path = $Path
    }
  }
}

function First-ExistingProperty {
  param(
    [object]$Object,
    [string[]]$Names
  )

  if ($null -eq $Object) {
    return $null
  }

  foreach ($name in $Names) {
    if ($Object.PSObject.Properties.Name -contains $name) {
      return $Object.$name
    }
  }

  return $null
}

function Take-Array {
  param(
    [object]$Value,
    [int]$Count = 10
  )

  if ($null -eq $Value) {
    return @()
  }

  if ($Value -is [System.Array]) {
    return @($Value | Select-Object -First $Count)
  }

  return @($Value)
}

$briefing = Read-JsonFile (Join-Path $derived "report-briefing.json")
$fetchSummary = Read-JsonFile (Join-Path $logs "latest-fetch-summary.json")
$quality = Read-JsonFile (Join-Path $derived "data-quality.json")
$interesting = Read-JsonFile (Join-Path $derived "us-interesting-stocks.json")
$macro = Read-JsonFile (Join-Path $derived "macro-snapshot.json")
$news = Read-JsonFile (Join-Path $derived "news-digest.json")
$breadth = Read-JsonFile (Join-Path $derived "market-breadth.json")

$interestingItems = First-ExistingProperty $interesting @("selected", "stocks", "items", "top", "interestingStocks", "data")
$newsItems = First-ExistingProperty $news @("items", "articles", "news", "headlines", "data")
$themes = First-ExistingProperty $briefing @("themes", "keyThemes", "todayThemes", "summary")
$watchlist = First-ExistingProperty $briefing @("watchlist", "watchList", "stocks", "interestingStocks")

$summary = [pscustomobject]@{
  generatedAt = (Get-Date).ToString("o")
  purpose = "Compact report inputs for Codex daily finance automation"
  fetch = [pscustomobject]@{
    ok = if ($fetchSummary -and ($fetchSummary.PSObject.Properties.Name -contains "counts")) { $fetchSummary.counts.ok } else { First-ExistingProperty $fetchSummary @("ok", "okCount", "success") }
    err = if ($fetchSummary -and ($fetchSummary.PSObject.Properties.Name -contains "counts")) { $fetchSummary.counts.err } else { First-ExistingProperty $fetchSummary @("err", "errorCount", "errors") }
    skip = if ($fetchSummary -and ($fetchSummary.PSObject.Properties.Name -contains "counts")) { $fetchSummary.counts.skip } else { First-ExistingProperty $fetchSummary @("skip", "skipCount", "skipped") }
    providers = First-ExistingProperty $fetchSummary @("providers", "providerStatus")
    raw = $fetchSummary
  }
  dataQuality = [pscustomobject]@{
    status = First-ExistingProperty $quality @("status", "quality", "grade")
    issues = First-ExistingProperty $quality @("issues", "warnings", "problems")
    raw = $quality
  }
  briefing = [pscustomobject]@{
    conclusion = First-ExistingProperty $briefing @("conclusion", "oneLine", "headline", "title")
    themes = Take-Array $themes 8
    watchlist = Take-Array $watchlist 15
    raw = $briefing
  }
  macro = [pscustomobject]@{
    snapshot = $macro
  }
  marketBreadth = [pscustomobject]@{
    snapshot = $breadth
  }
  news = [pscustomobject]@{
    top = Take-Array $newsItems 12
  }
  interestingStocks = [pscustomobject]@{
    top = Take-Array $interestingItems 10
    raw = $interesting
  }
}

$json = $summary | ConvertTo-Json -Depth 20
Set-Content -LiteralPath $outPath -Value $json -Encoding UTF8

Write-Host ("REPORT_INPUT_SUMMARY_PATH={0}" -f $outPath)
Write-Host ("REPORT_INPUT_SUMMARY_STATUS={0}" -f $summary.dataQuality.status)
Write-Host ("REPORT_INPUT_SUMMARY_FETCH_OK={0} ERR={1} SKIP={2}" -f $summary.fetch.ok, $summary.fetch.err, $summary.fetch.skip)
