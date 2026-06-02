param(
  [string]$RawDataDir = "data\raw",
  [string]$SourcesPath = "data\sources.json",
  [string]$OutDir = "data\derived",
  [int]$TopCount = 10,
  [double]$MinPrice = 1.0,
  [double]$MinDollarVolume = 50000000
)

$ErrorActionPreference = "Continue"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $root) { $root = Get-Location }
Set-Location $root

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Convert-ToNumber {
  param($Value)
  if ($null -eq $Value) { return $null }
  $s = ([string]$Value).Trim().Replace("%", "")
  if ([string]::IsNullOrWhiteSpace($s)) { return $null }
  $n = 0.0
  if ([double]::TryParse($s, [Globalization.NumberStyles]::Any, [Globalization.CultureInfo]::InvariantCulture, [ref]$n)) {
    return $n
  }
  return $null
}

function Is-NoisyTicker {
  param([string]$Ticker)
  if ([string]::IsNullOrWhiteSpace($Ticker)) { return $true }
  $t = $Ticker.Trim().ToUpperInvariant()
  if ($t -match "[+.-]") { return $true }
  if ($t.Length -gt 5) { return $true }
  if ($t -match "(W|WS|WT|U|R)$" -and $t.Length -ge 5) { return $true }
  $excluded = @(
    "SOXL", "SOXS", "TQQQ", "SQQQ", "TNA", "TZA", "UVXY", "VXX", "SPXS", "SPXL",
    "BITO", "BOIL", "KOLD", "LABU", "LABD", "YANG", "YINN",
    "SPY", "QQQ", "DIA", "IWM", "RSP", "SMH", "XLF", "XLE", "XLV", "XLY", "XLP", "XLI", "XLU", "XLB", "XLRE"
  )
  return ($excluded -contains $t)
}

function Is-LowQualityNonCoreCandidate {
  param($Item)
  if ($null -eq $Item) { return $true }
  if ($Item.watchlist) { return $false }
  if ($Item.price -ge 10) { return $false }
  if ($Item.news_count -gt 0) { return $false }
  return $true
}

function Add-Candidate {
  param(
    [hashtable]$Map,
    [string]$Ticker,
    [string]$Source,
    [double]$Price,
    [double]$ChangePct,
    [double]$Volume,
    [string]$Reason
  )

  if (Is-NoisyTicker $Ticker) { return }
  if ($null -eq $Price -or $Price -lt $MinPrice) { return }
  if ($null -eq $Volume) { $Volume = 0 }
  $dollarVolume = $Price * $Volume
  if ($dollarVolume -lt $MinDollarVolume) { return }

  $t = $Ticker.Trim().ToUpperInvariant()
  if (-not $Map.ContainsKey($t)) {
    $Map[$t] = [pscustomobject]@{
      ticker = $t
      price = $Price
      change_pct = $ChangePct
      volume = $Volume
      dollar_volume = $dollarVolume
      sources = New-Object System.Collections.Generic.List[string]
      reasons = New-Object System.Collections.Generic.List[string]
      news_count = 0
      watchlist = $false
      score = 0.0
    }
  }

  $item = $Map[$t]
  if (-not $item.sources.Contains($Source)) { $item.sources.Add($Source) | Out-Null }
  if ($Reason -and -not $item.reasons.Contains($Reason)) { $item.reasons.Add($Reason) | Out-Null }
  if ($null -ne $ChangePct) { $item.change_pct = $ChangePct }
  if ($Price -gt 0) { $item.price = $Price }
  if ($Volume -gt $item.volume) {
    $item.volume = $Volume
    $item.dollar_volume = $dollarVolume
  }
}

function Get-Sector {
  param([string]$Ticker)
  $t = $Ticker.ToUpperInvariant()
  $map = @{
    "SPY" = "index"; "QQQ" = "index"; "DIA" = "index"; "IWM" = "index"; "RSP" = "index"
    "SMH" = "semiconductors"; "NVDA" = "semiconductors"; "AMD" = "semiconductors"; "MU" = "semiconductors"; "AVGO" = "semiconductors"; "INTC" = "semiconductors"; "QCOM" = "semiconductors"; "MRVL" = "semiconductors"; "ARM" = "semiconductors"
    "DELL" = "AI infrastructure"; "SMCI" = "AI infrastructure"; "HPE" = "AI infrastructure"; "VRT" = "AI power/cooling"; "ANET" = "AI networking"; "ETN" = "AI power/cooling"; "CEG" = "AI power"; "GEV" = "AI power"; "PWR" = "AI power/grid"
    "MSFT" = "software"; "ORCL" = "software"; "IBM" = "software"; "NOW" = "software"; "CRM" = "software"
    "AAPL" = "mega-cap tech"; "META" = "mega-cap tech"; "GOOGL" = "mega-cap tech"; "AMZN" = "mega-cap tech"; "TSLA" = "consumer growth"
    "XLF" = "financials"; "JPM" = "financials"; "BAC" = "financials"; "GS" = "financials"; "MS" = "financials"; "C" = "financials"; "BRK.B" = "financials"; "V" = "payments"; "MA" = "payments"; "PYPL" = "payments"; "COIN" = "crypto"; "HOOD" = "brokerage"
    "XLE" = "energy"; "XOM" = "energy"; "CVX" = "energy"; "COP" = "energy"; "SLB" = "energy"; "OXY" = "energy"
    "XLV" = "healthcare"; "LLY" = "healthcare"; "UNH" = "healthcare"; "JNJ" = "healthcare"; "PFE" = "healthcare"; "MRK" = "healthcare"; "ABBV" = "healthcare"
    "NOC" = "defense"; "RTX" = "defense"; "LMT" = "defense"; "GD" = "defense"; "BA" = "industrials"
    "XLY" = "consumer discretionary"; "WMT" = "consumer staples"; "COST" = "consumer staples"; "HD" = "consumer discretionary"; "MCD" = "consumer discretionary"; "NKE" = "consumer discretionary"; "SBUX" = "consumer discretionary"; "DIS" = "media"
    "DAL" = "transport"; "UAL" = "transport"; "FDX" = "transport"; "UPS" = "transport"; "UNP" = "transport"
    "XLU" = "utilities"; "NEE" = "utilities"; "DUK" = "utilities"; "SO" = "utilities"
    "XLP" = "consumer staples"; "XLI" = "industrials"; "XLB" = "materials"; "XLRE" = "real estate"
  }
  if ($map.ContainsKey($t)) { return $map[$t] }
  return "other"
}

$sources = Get-Content -Raw -Encoding UTF8 $SourcesPath | ConvertFrom-Json
$candidates = @{}

$avPath = Join-Path $RawDataDir "alphavantage\top-gainers-losers.json"
if (Test-Path $avPath) {
  $av = Get-Content -Raw -Encoding UTF8 $avPath | ConvertFrom-Json
  foreach ($row in @($av.most_actively_traded)) {
    Add-Candidate -Map $candidates -Ticker $row.ticker -Source "AlphaVantage:active" `
      -Price (Convert-ToNumber $row.price) `
      -ChangePct (Convert-ToNumber $row.change_percentage) `
      -Volume (Convert-ToNumber $row.volume) `
      -Reason "high volume"
  }
  foreach ($row in @($av.top_gainers)) {
    Add-Candidate -Map $candidates -Ticker $row.ticker -Source "AlphaVantage:gainer" `
      -Price (Convert-ToNumber $row.price) `
      -ChangePct (Convert-ToNumber $row.change_percentage) `
      -Volume (Convert-ToNumber $row.volume) `
      -Reason "top gainer"
  }
  foreach ($row in @($av.top_losers)) {
    Add-Candidate -Map $candidates -Ticker $row.ticker -Source "AlphaVantage:loser" `
      -Price (Convert-ToNumber $row.price) `
      -ChangePct (Convert-ToNumber $row.change_percentage) `
      -Volume (Convert-ToNumber $row.volume) `
      -Reason "top loser"
  }
}

foreach ($ticker in $sources.us_watchlist) {
  $t = ([string]$ticker).ToUpperInvariant()
  $quotePath = Join-Path $RawDataDir "finnhub\$t-quote.json"
  if (-not (Test-Path $quotePath)) { continue }
  $q = Get-Content -Raw -Encoding UTF8 $quotePath | ConvertFrom-Json
  $price = Convert-ToNumber $q.c
  $changePct = Convert-ToNumber $q.dp
  $volume = 0
  $polygonPath = Join-Path $RawDataDir "polygon\$t-daily.json"
  if (Test-Path $polygonPath) {
    try {
      $p = Get-Content -Raw -Encoding UTF8 $polygonPath | ConvertFrom-Json
      $last = @($p.results) | Select-Object -Last 1
      if ($last) { $volume = Convert-ToNumber $last.v }
    } catch {}
  }
  if ($volume -le 0) { $volume = 50000000 }
  Add-Candidate -Map $candidates -Ticker $t -Source "Finnhub:watchlist" `
    -Price $price `
    -ChangePct $changePct `
    -Volume $volume `
    -Reason "core watchlist"
  if ($candidates.ContainsKey($t)) {
    $candidates[$t].watchlist = $true
  }
}

foreach ($ticker in @($candidates.Keys)) {
  $item = $candidates[$ticker]
  $newsPath = Join-Path $RawDataDir "finnhub\$ticker-news.json"
  if (Test-Path $newsPath) {
    try {
      $news = Get-Content -Raw -Encoding UTF8 $newsPath | ConvertFrom-Json
      $item.news_count = @($news).Count
      if ($item.news_count -gt 0 -and -not $item.reasons.Contains("news coverage")) {
        $item.reasons.Add("news coverage") | Out-Null
      }
    } catch {}
  }

  $absChange = [Math]::Abs((Convert-ToNumber $item.change_pct))
  $liquidityScore = if ($item.dollar_volume -gt 0) { [Math]::Min(40.0, [Math]::Log10($item.dollar_volume) * 4.0) } else { 0 }
  $moveScore = [Math]::Min(35.0, $absChange * 3.0)
  $newsScore = [Math]::Min(15.0, $item.news_count / 5.0)
  $watchlistScore = if ($item.watchlist) { 20.0 } else { 0.0 }
  $multiSourceScore = [Math]::Min(10.0, $item.sources.Count * 2.0)
  $item.score = [Math]::Round($liquidityScore + $moveScore + $newsScore + $watchlistScore + $multiSourceScore, 2)
  if (Is-LowQualityNonCoreCandidate $item) {
    $item.score = [Math]::Round($item.score - 100.0, 2)
    if (-not $item.reasons.Contains("low-price non-core penalty")) {
      $item.reasons.Add("low-price non-core penalty") | Out-Null
    }
  }
}

$ranked = $candidates.Values |
  Where-Object { -not (Is-LowQualityNonCoreCandidate $_) } |
  Sort-Object @{Expression = "score"; Descending = $true}, @{Expression = "dollar_volume"; Descending = $true}

$selectedList = New-Object System.Collections.Generic.List[object]
$sectorCounts = @{}
foreach ($item in $ranked) {
  $sector = Get-Sector $item.ticker
  if (-not $sectorCounts.ContainsKey($sector)) { $sectorCounts[$sector] = 0 }
  $sectorLimit = if ($sector -in @("semiconductors", "mega-cap tech", "software")) { 3 } else { 2 }
  if ($sectorCounts[$sector] -ge $sectorLimit) { continue }
  $item | Add-Member -NotePropertyName sector -NotePropertyValue $sector -Force
  $selectedList.Add($item) | Out-Null
  $sectorCounts[$sector]++
  if ($selectedList.Count -ge $TopCount) { break }
}

if ($selectedList.Count -lt $TopCount) {
  foreach ($item in $ranked) {
    if ($selectedList | Where-Object { $_.ticker -eq $item.ticker }) { continue }
    $sector = Get-Sector $item.ticker
    $item | Add-Member -NotePropertyName sector -NotePropertyValue $sector -Force
    $selectedList.Add($item) | Out-Null
    if ($selectedList.Count -ge $TopCount) { break }
  }
}

$selected = @($selectedList.ToArray())

$out = [pscustomobject]@{
  generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  rules = [pscustomobject]@{
    min_price = $MinPrice
    min_dollar_volume = $MinDollarVolume
    excluded = "warrants/rights/leveraged ETFs/index-sector ETFs/no-news low-price non-core tickers"
  }
  selected = $selected | ForEach-Object {
    [pscustomobject]@{
      ticker = $_.ticker
      sector = $_.sector
      score = $_.score
      price = [Math]::Round($_.price, 4)
      change_pct = [Math]::Round($_.change_pct, 4)
      volume = [int64]$_.volume
      dollar_volume = [Math]::Round($_.dollar_volume, 2)
      news_count = $_.news_count
      watchlist = $_.watchlist
      sources = @($_.sources)
      reasons = @($_.reasons)
    }
  }
}

$jsonPath = Join-Path $OutDir "us-interesting-stocks.json"
$mdPath = Join-Path $OutDir "us-interesting-stocks.md"
$out | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# US Interesting / Volatile Stocks") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("Generated at: $($out.generated_at)") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Rank | Ticker | Sector | Score | Change | Price | Dollar volume | Reasons |") | Out-Null
$lines.Add("| ---: | --- | --- | ---: | ---: | ---: | ---: | --- |") | Out-Null
$rank = 1
foreach ($item in $out.selected) {
  $reason = ($item.reasons -join ", ")
  $lines.Add("| $rank | $($item.ticker) | $($item.sector) | $($item.score) | $($item.change_pct)% | $($item.price) | $([Math]::Round($item.dollar_volume / 1000000, 1))M | $reason |") | Out-Null
  $rank++
}
$lines | Set-Content -Path $mdPath -Encoding UTF8

Write-Host "Wrote $jsonPath and $mdPath"
