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
  $s = ([string]$Value).Trim()
  if ([string]::IsNullOrWhiteSpace($s) -or $s -eq ".") { return $null }
  $n = 0.0
  if ([double]::TryParse($s, [Globalization.NumberStyles]::Any, [Globalization.CultureInfo]::InvariantCulture, [ref]$n)) {
    return $n
  }
  return $null
}

function Read-FredJsonLatest {
  param([string]$Path)
  if (-not (Test-Path $Path)) { return $null }
  try {
    $j = Get-Content -Raw -Encoding UTF8 $Path | ConvertFrom-Json
    $rows = @($j.observations) | Where-Object { $null -ne (Convert-ToNumber $_.value) }
    if ($rows.Count -eq 0) { return $null }
    $last = $rows | Select-Object -Last 1
    $prev = if ($rows.Count -gt 1) { $rows[$rows.Count - 2] } else { $null }
    $value = Convert-ToNumber $last.value
    $prevValue = if ($prev) { Convert-ToNumber $prev.value } else { $null }
    $change = if ($null -ne $prevValue) { $value - $prevValue } else { $null }
    return [pscustomobject]@{ date = $last.date; value = $value; change = $change; source = "FRED" }
  } catch { return $null }
}

function Read-YahooJsonLatest {
  param([string]$Path)
  if (-not (Test-Path $Path)) { return $null }
  try {
    $j = Get-Content -Raw -Encoding UTF8 $Path | ConvertFrom-Json
    $result = $j.chart.result[0]
    $timestamps = $result.timestamp
    $closes = $result.indicators.quote[0].close
    $rows = @()
    for ($i = 0; $i -lt $timestamps.Count; $i++) {
      $value = Convert-ToNumber $closes[$i]
      if ($null -ne $value) {
        $date = ([DateTimeOffset]::FromUnixTimeSeconds([int64]$timestamps[$i])).UtcDateTime.ToString("yyyy-MM-dd")
        $rows += [pscustomobject]@{ date = $date; value = $value }
      }
    }
    if ($rows.Count -eq 0) { return $null }
    $last = $rows | Select-Object -Last 1
    $prev = if ($rows.Count -gt 1) { $rows[$rows.Count - 2] } else { $null }
    $changePct = if ($prev -and $prev.value -ne 0) { (($last.value - $prev.value) / $prev.value) * 100.0 } else { $null }
    return [pscustomobject]@{ date = $last.date; value = $last.value; change_pct = $changePct; source = "Yahoo" }
  } catch { return $null }
}

$fredDir = Join-Path $RawDataDir "fred"
$yahooDir = Join-Path $RawDataDir "yahoo"

$items = @(
  @{ key = "us_2y"; label = "US 2Y yield"; kind = "yield"; data = (Read-FredJsonLatest (Join-Path $fredDir "us2y.json")) },
  @{ key = "us_10y"; label = "US 10Y yield"; kind = "yield"; data = (Read-FredJsonLatest (Join-Path $fredDir "us10y.json")) },
  @{ key = "us_30y"; label = "US 30Y yield"; kind = "yield"; data = (Read-FredJsonLatest (Join-Path $fredDir "us30y.json")) },
  @{ key = "wti_fred"; label = "WTI crude"; kind = "commodity"; data = (Read-FredJsonLatest (Join-Path $fredDir "wti.json")) },
  @{ key = "dollar_fred"; label = "Trade-weighted dollar"; kind = "fx"; data = (Read-FredJsonLatest (Join-Path $fredDir "dollar-index.json")) },
  @{ key = "hy_spread"; label = "High-yield spread"; kind = "credit"; data = (Read-FredJsonLatest (Join-Path $fredDir "high-yield-spread.json")) },
  @{ key = "dxy"; label = "DXY"; kind = "fx"; data = (Read-YahooJsonLatest (Join-Path $yahooDir "dxy.json")) },
  @{ key = "gold"; label = "Gold"; kind = "commodity"; data = (Read-YahooJsonLatest (Join-Path $yahooDir "gold.json")) },
  @{ key = "wti_futures"; label = "WTI futures"; kind = "commodity"; data = (Read-YahooJsonLatest (Join-Path $yahooDir "wti-futures.json")) },
  @{ key = "brent_futures"; label = "Brent futures"; kind = "commodity"; data = (Read-YahooJsonLatest (Join-Path $yahooDir "brent-futures.json")) },
  @{ key = "bitcoin"; label = "Bitcoin"; kind = "crypto"; data = (Read-YahooJsonLatest (Join-Path $yahooDir "bitcoin.json")) },
  @{ key = "usd_jpy"; label = "USD/JPY"; kind = "fx"; data = (Read-YahooJsonLatest (Join-Path $yahooDir "usd-jpy.json")) },
  @{ key = "usd_krw"; label = "USD/KRW"; kind = "fx"; data = (Read-YahooJsonLatest (Join-Path $yahooDir "usd-krw.json")) }
)

$snapshotItems = foreach ($item in $items) {
  $d = $item.data
  if ($null -eq $d) { continue }
  $ageDays = $null
  try {
    $ageDays = [int]((Get-Date).Date - ([datetime]::Parse($d.date)).Date).TotalDays
  } catch {}
  [pscustomobject]@{
    key = $item.key
    label = $item.label
    kind = $item.kind
    date = $d.date
    age_days = $ageDays
    stale = ($null -ne $ageDays -and $ageDays -gt 7)
    value = [Math]::Round($d.value, 4)
    change = if ($null -ne $d.change) { [Math]::Round($d.change, 4) } else { $null }
    change_pct = if ($null -ne $d.change_pct) { [Math]::Round($d.change_pct, 4) } else { $null }
    source = $d.source
  }
}

$out = [pscustomobject]@{
  generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  counts = [pscustomobject]@{
    total = @($snapshotItems).Count
    stale = @($snapshotItems | Where-Object { $_.stale }).Count
  }
  items = @($snapshotItems)
}

$jsonPath = Join-Path $OutDir "macro-snapshot.json"
$mdPath = Join-Path $OutDir "macro-snapshot.md"
$out | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Macro Snapshot") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("Generated at: $($out.generated_at)") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("Items: $($out.counts.total), stale: $($out.counts.stale)") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Key | Value | Change | Source | Date | Age | Stale |") | Out-Null
$lines.Add("| --- | ---: | ---: | --- | --- | ---: | --- |") | Out-Null
foreach ($item in $out.items) {
  $change = if ($null -ne $item.change_pct) { "$($item.change_pct)%" } elseif ($null -ne $item.change) { "$($item.change)" } else { "" }
  $lines.Add("| $($item.label) | $($item.value) | $change | $($item.source) | $($item.date) | $($item.age_days) | $($item.stale) |") | Out-Null
}
$lines | Set-Content -Path $mdPath -Encoding UTF8

Write-Host "Wrote $jsonPath and $mdPath"
