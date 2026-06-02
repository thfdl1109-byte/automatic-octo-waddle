param(
  [string]$RawDataDir = "data\raw",
  [string]$OutDir = "data\derived",
  [int]$TopCount = 20,
  [int]$MaxNewsPerTicker = 25,
  [int]$MaxTickerFiles = 40
)

$ErrorActionPreference = "Continue"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $root) { $root = Get-Location }
Set-Location $root

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$trustedSources = @(
  "Reuters", "Associated Press", "AP", "CNBC", "MarketWatch", "The Wall Street Journal",
  "Barrons", "Bloomberg", "Financial Times", "Investing.com", "Benzinga"
)
$lowSignalPatterns = @(
  "millionaire", "buy and hold forever", "prediction:", "better buy", "is it a buy",
  "3 stocks", "under \\$20", "motley fool", "zacks", "wallstreetbets",
  "we're giving", "our position", "price target on another", "how we navigate",
  "crash the market", "eerily similar", "forum:", "worry me more", "illusion of"
)
$marketKeywords = @(
  "Federal Reserve", "inflation", "oil", "Treasury", "yield", "Nvidia", "AI",
  "semiconductor", "earnings", "guidance", "downgrade", "upgrade", "Middle East",
  "dollar", "jobs", "CPI", "PCE", "GDP"
)
$eventRules = @(
  @{ event = "AI / semiconductors"; patterns = @("\\bnvidia\\b", "\\bai\\b", "artificial intelligence", "semiconductor", "\\bchip\\b", "\\bchips\\b", "\\bmemory\\b", "data center", "blackwell", "\\bhbm\\b") },
  @{ event = "Rates / Fed / inflation"; patterns = @("federal reserve", "\\bfed\\b", "inflation", "treasury", "\\byield\\b", "\\byields\\b", "\\brate\\b", "\\brates\\b", "\\bcpi\\b", "\\bpce\\b") },
  @{ event = "Oil / geopolitics"; patterns = @("\\boil\\b", "\\bcrude\\b", "\\biran\\b", "middle east", "hormuz", "geopolitical") },
  @{ event = "Earnings / guidance"; patterns = @("earnings", "guidance", "revenue", "profit", "\\beps\\b", "forecast") },
  @{ event = "M&A / corporate action"; patterns = @("\\bdeal\\b", "merger", "acquisition", "spinoff", "spin-off", "\\bipo\\b") },
  @{ event = "Consumer / transport"; patterns = @("consumer", "retail", "airline", "freight", "shipping", "fedex", "\\bups\\b") },
  @{ event = "Crypto"; patterns = @("bitcoin", "crypto", "stablecoin", "coinbase") }
)

function Get-EventName {
  param([string]$Text)
  $lower = if ($Text) { $Text.ToLowerInvariant() } else { "" }
  foreach ($rule in $eventRules) {
    foreach ($pattern in $rule.patterns) {
      if ($lower -match $pattern) { return $rule.event }
    }
  }
  return "Other"
}

function Add-NewsItem {
  param(
    [System.Collections.Generic.List[object]]$List,
    [string]$Source,
    [string]$Title,
    [string]$Summary,
    [string]$Url,
    [object]$PublishedAt,
    [string]$Ticker = ""
  )
  if ([string]::IsNullOrWhiteSpace($Title)) { return }
  $normalizedTitle = $Title.Trim()
  $score = 0
  foreach ($src in $trustedSources) {
    if ($Source -and $Source.ToLowerInvariant().Contains($src.ToLowerInvariant())) { $score += 25; break }
  }
  foreach ($kw in $marketKeywords) {
    if ($normalizedTitle.ToLowerInvariant().Contains($kw.ToLowerInvariant()) -or ($Summary -and $Summary.ToLowerInvariant().Contains($kw.ToLowerInvariant()))) {
      $score += 8
    }
  }
  foreach ($pattern in $lowSignalPatterns) {
    if ($normalizedTitle.ToLowerInvariant() -match $pattern) { $score -= 20 }
  }
  if ($Source -and $Source.ToLowerInvariant().Contains("seekingalpha")) { $score -= 15 }
  if ($Source -and $Source.ToLowerInvariant().Contains("benzinga")) { $score -= 5 }
  if ($Source -and $Source.ToLowerInvariant().Contains("yahoo") -and -not ($Url -and $Url.Contains("finance.yahoo"))) { $score -= 5 }
  if ($Ticker) { $score += 8 }
  if ($Url -and ($Url.Contains("reuters") -or $Url.Contains("cnbc") -or $Url.Contains("apnews") -or $Url.Contains("marketwatch"))) { $score += 10 }
  $event = Get-EventName "$normalizedTitle $Summary"
  if ($event -ne "Other") { $score += 10 }
  if ($event -in @("Rates / Fed / inflation", "Oil / geopolitics", "AI / semiconductors")) { $score += 10 }
  if ($event -eq "M&A / corporate action" -and -not $Ticker) { $score -= 12 }
  if ($Ticker -eq "market" -and $event -eq "M&A / corporate action") { $score -= 12 }
  if ($Ticker -eq "market" -and $event -in @("M&A / corporate action", "Consumer / transport")) { $score -= 20 }

  $List.Add([pscustomobject]@{
    score = $score
    event = $event
    source = $Source
    ticker = $Ticker
    title = $normalizedTitle
    summary = $Summary
    url = $Url
    published_at = [string]$PublishedAt
  }) | Out-Null
}

$items = New-Object System.Collections.Generic.List[object]

$newsApiPath = Join-Path $RawDataDir "newsapi\market-headlines.json"
if (Test-Path $newsApiPath) {
  try {
    $j = Get-Content -Raw -Encoding UTF8 $newsApiPath | ConvertFrom-Json
    foreach ($a in @($j.articles)) {
      Add-NewsItem -List $items -Source $a.source.name -Title $a.title -Summary $a.description -Url $a.url -PublishedAt $a.publishedAt
    }
  } catch {}
}

$finnhubDir = Join-Path $RawDataDir "finnhub"
if (Test-Path $finnhubDir) {
  Get-ChildItem -Path $finnhubDir -Filter "*-news.json" | Select-Object -First $MaxTickerFiles | ForEach-Object {
    $ticker = $_.BaseName -replace "-news$", ""
    try {
      $rows = Get-Content -Raw -Encoding UTF8 $_.FullName | ConvertFrom-Json
      foreach ($a in (@($rows) | Select-Object -First $MaxNewsPerTicker)) {
        Add-NewsItem -List $items -Source $a.source -Title $a.headline -Summary $a.summary -Url $a.url -PublishedAt $a.datetime -Ticker $ticker
      }
    } catch {}
  }
}

$dedup = @{}
foreach ($item in $items) {
  $key = ($item.title.ToLowerInvariant() -replace "[^a-z0-9]", "")
  if ([string]::IsNullOrWhiteSpace($key)) { continue }
  if (-not $dedup.ContainsKey($key) -or $item.score -gt $dedup[$key].score) {
    $dedup[$key] = $item
  }
}

$ranked = $dedup.Values |
  Where-Object { $_.score -ge 20 } |
  Sort-Object @{Expression = "score"; Descending = $true}

$selectedList = New-Object System.Collections.Generic.List[object]
$eventCounts = @{}
$sourceCounts = @{}
foreach ($item in $ranked) {
  $eventKey = [string]$item.event
  $sourceKey = if ($item.source) { [string]$item.source } else { "unknown" }
  if (-not $eventCounts.ContainsKey($eventKey)) { $eventCounts[$eventKey] = 0 }
  if (-not $sourceCounts.ContainsKey($sourceKey)) { $sourceCounts[$sourceKey] = 0 }
  if ($eventCounts[$eventKey] -ge 5) { continue }
  if ($sourceCounts[$sourceKey] -ge 6) { continue }
  $selectedList.Add($item) | Out-Null
  $eventCounts[$eventKey]++
  $sourceCounts[$sourceKey]++
  if ($selectedList.Count -ge $TopCount) { break }
}
$selected = @($selectedList.ToArray())

$out = [pscustomobject]@{
  generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  selected = @($selected)
}

$jsonPath = Join-Path $OutDir "news-digest.json"
$mdPath = Join-Path $OutDir "news-digest.md"
$out | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# News Digest") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("Generated at: $($out.generated_at)") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Score | Source | Ticker | Headline |") | Out-Null
$lines.Add("| ---: | --- | --- | --- |") | Out-Null
foreach ($item in $out.selected) {
  if ($null -eq $item -or [string]::IsNullOrWhiteSpace($item.title)) { continue }
  $headline = $item.title.Replace("|", "-")
  $lines.Add("| $($item.score) | $($item.source) | $($item.ticker) | [$($item.event)] $headline |") | Out-Null
}
$lines | Set-Content -Path $mdPath -Encoding UTF8

Write-Host "Wrote $jsonPath and $mdPath"
