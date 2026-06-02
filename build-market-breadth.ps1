param(
  [string]$RawDataDir = "data\raw",
  [string]$OutDir = "data\derived"
)

$ErrorActionPreference = "Continue"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $root) { $root = Get-Location }
Set-Location $root

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Convert-ToNumber {
  param($Value)
  if ($null -eq $Value) { return $null }
  $n = 0.0
  if ([double]::TryParse(([string]$Value), [Globalization.NumberStyles]::Any, [Globalization.CultureInfo]::InvariantCulture, [ref]$n)) {
    return $n
  }
  return $null
}

function Read-FinnhubQuote {
  param([string]$Ticker)
  $path = Join-Path $RawDataDir "finnhub\$Ticker-quote.json"
  if (-not (Test-Path $path)) { return $null }
  try {
    $j = Get-Content -Raw -Encoding UTF8 $path | ConvertFrom-Json
    return [pscustomobject]@{
      ticker = $Ticker
      current = Convert-ToNumber $j.c
      change_pct = Convert-ToNumber $j.dp
      previous = Convert-ToNumber $j.pc
    }
  } catch { return $null }
}

function Read-YahooLatest {
  param([string]$Ticker, [string]$File)
  $path = Join-Path $RawDataDir "yahoo\$File"
  if (-not (Test-Path $path)) { return $null }
  try {
    $j = Get-Content -Raw -Encoding UTF8 $path | ConvertFrom-Json
    $result = $j.chart.result[0]
    $timestamps = $result.timestamp
    $closes = $result.indicators.quote[0].close
    $rows = @()
    for ($i = 0; $i -lt $timestamps.Count; $i++) {
      $value = Convert-ToNumber $closes[$i]
      if ($null -ne $value) { $rows += $value }
    }
    if ($rows.Count -lt 2) { return $null }
    $last = $rows | Select-Object -Last 1
    $prev = $rows[$rows.Count - 2]
    $changePct = (($last - $prev) / $prev) * 100.0
    return [pscustomobject]@{
      ticker = $Ticker
      current = $last
      change_pct = [Math]::Round($changePct, 4)
      previous = $prev
    }
  } catch { return $null }
}

$quotes = @{}
foreach ($ticker in @("SPY", "QQQ", "IWM", "RSP", "SMH", "XLF", "XLE", "XLV", "XLY", "XLP", "XLI", "XLU")) {
  $q = Read-FinnhubQuote $ticker
  if ($q) { $quotes[$ticker] = $q }
}

$yahooFallbacks = @{
  "SPY" = "sp500.json"
  "QQQ" = "nasdaq.json"
  "IWM" = "russell2000.json"
}
foreach ($ticker in $yahooFallbacks.Keys) {
  if (-not $quotes.ContainsKey($ticker)) {
    $q = Read-YahooLatest -Ticker $ticker -File $yahooFallbacks[$ticker]
    if ($q) { $quotes[$ticker] = $q }
  }
}

function Relative-Row {
  param([string]$Name, [string]$A, [string]$B)
  if (-not $quotes.ContainsKey($A) -or -not $quotes.ContainsKey($B)) { return $null }
  $qa = $quotes[$A]
  $qb = $quotes[$B]
  return [pscustomobject]@{
    name = $Name
    a = $A
    b = $B
    a_change_pct = $qa.change_pct
    b_change_pct = $qb.change_pct
    relative_pct = [Math]::Round($qa.change_pct - $qb.change_pct, 4)
  }
}

$relative = @(
  (Relative-Row "Equal weight vs cap weight" "RSP" "SPY"),
  (Relative-Row "Small caps vs S&P 500" "IWM" "SPY"),
  (Relative-Row "Nasdaq 100 vs S&P 500" "QQQ" "SPY"),
  (Relative-Row "Semiconductors vs S&P 500" "SMH" "SPY"),
  (Relative-Row "Financials vs S&P 500" "XLF" "SPY"),
  (Relative-Row "Energy vs S&P 500" "XLE" "SPY"),
  (Relative-Row "Healthcare vs S&P 500" "XLV" "SPY"),
  (Relative-Row "Consumer discretionary vs S&P 500" "XLY" "SPY"),
  (Relative-Row "Consumer staples vs S&P 500" "XLP" "SPY"),
  (Relative-Row "Industrials vs S&P 500" "XLI" "SPY"),
  (Relative-Row "Utilities vs S&P 500" "XLU" "SPY")
) | Where-Object { $null -ne $_ }

$signals = New-Object System.Collections.Generic.List[string]
$iwm = $relative | Where-Object { $_.name -eq "Small caps vs S&P 500" } | Select-Object -First 1
$rsp = $relative | Where-Object { $_.name -eq "Equal weight vs cap weight" } | Select-Object -First 1
$smh = $relative | Where-Object { $_.name -eq "Semiconductors vs S&P 500" } | Select-Object -First 1
if ($iwm -and $iwm.relative_pct -lt -0.5) { $signals.Add("small caps lag") | Out-Null }
if ($rsp -and $rsp.relative_pct -lt -0.3) { $signals.Add("narrow mega-cap leadership") | Out-Null }
if ($smh -and $smh.relative_pct -gt 0.5) { $signals.Add("semiconductor leadership") | Out-Null }
if ($signals.Count -eq 0) { $signals.Add("breadth neutral / needs confirmation") | Out-Null }

$out = [pscustomobject]@{
  generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  available_quotes = $quotes.Count
  signals = @($signals)
  relative = @($relative)
}

$jsonPath = Join-Path $OutDir "market-breadth.json"
$mdPath = Join-Path $OutDir "market-breadth.md"
$out | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Market Breadth Snapshot") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("Generated at: $($out.generated_at)") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("Signals: $($out.signals -join ', ')") | Out-Null
$lines.Add("Available quotes: $($out.available_quotes)") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Metric | A | B | A change | B change | Relative |") | Out-Null
$lines.Add("| --- | --- | --- | ---: | ---: | ---: |") | Out-Null
foreach ($r in $out.relative) {
  $lines.Add("| $($r.name) | $($r.a) | $($r.b) | $($r.a_change_pct)% | $($r.b_change_pct)% | $($r.relative_pct)% |") | Out-Null
}
$lines | Set-Content -Path $mdPath -Encoding UTF8

Write-Host "Wrote $jsonPath and $mdPath"
