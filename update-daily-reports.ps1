param(
  [string]$ReportsDir = "daily-reports-2026-01-01_2026-06-02",
  [string]$RawDataDir = "data\raw",
  [string]$StartDate = "2026-01-01",
  [string]$EndDate = "2026-06-02"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $root) { $root = Get-Location }
Set-Location $root

function Convert-ToNumber {
  param($Value)
  if ($null -eq $Value) { return $null }
  $s = [string]$Value
  if ([string]::IsNullOrWhiteSpace($s) -or $s -eq ".") { return $null }
  $n = 0.0
  if ([double]::TryParse($s, [Globalization.NumberStyles]::Any, [Globalization.CultureInfo]::InvariantCulture, [ref]$n)) {
    return $n
  }
  return $null
}

function Read-FredSeries {
  param([string]$Path)
  $map = @{}
  if (-not (Test-Path $Path)) { return $map }
  $rows = Import-Csv $Path
  foreach ($r in $rows) {
    $props = $r.PSObject.Properties.Name
    if ($props.Count -lt 2) { continue }
    $date = [string]$r.($props[0])
    $value = Convert-ToNumber $r.($props[1])
    if ($date -match "^\d{4}-\d{2}-\d{2}$") {
      $map[$date] = $value
    }
  }
  return $map
}

function Read-StooqSeries {
  param([string]$Path)
  $map = @{}
  if (-not (Test-Path $Path)) { return $map }
  $rows = Import-Csv $Path
  foreach ($r in $rows) {
    $date = [string]$r.Date
    $value = Convert-ToNumber $r.Close
    if ($date -match "^\d{4}-\d{2}-\d{2}$") {
      $map[$date] = $value
    }
  }
  return $map
}

function Read-YahooSeries {
  param([string]$Path)
  $map = @{}
  if (-not (Test-Path $Path)) { return $map }
  $json = Get-Content -Raw -Encoding UTF8 $Path | ConvertFrom-Json
  $result = $json.chart.result[0]
  if ($null -eq $result) { return $map }
  $timestamps = $result.timestamp
  $closes = $result.indicators.quote[0].close
  if ($null -eq $timestamps -or $null -eq $closes) { return $map }

  for ($i = 0; $i -lt $timestamps.Count; $i++) {
    $date = ([DateTimeOffset]::FromUnixTimeSeconds([int64]$timestamps[$i])).UtcDateTime.ToString("yyyy-MM-dd")
    $value = Convert-ToNumber $closes[$i]
    $map[$date] = $value
  }
  return $map
}

function Merge-Series {
  param($Primary, $Fallback)
  $out = @{}
  foreach ($k in $Fallback.Keys) { $out[$k] = $Fallback[$k] }
  foreach ($k in $Primary.Keys) { $out[$k] = $Primary[$k] }
  return $out
}

function Add-ChangePct {
  param($Series)
  $dates = $Series.Keys | Sort-Object
  $prev = $null
  $out = @{}
  foreach ($d in $dates) {
    $v = $Series[$d]
    $chg = $null
    if ($null -ne $v -and $null -ne $prev -and $prev -ne 0) {
      $chg = (($v - $prev) / $prev) * 100.0
    }
    $out[$d] = @{ value = $v; change = $chg }
    if ($null -ne $v) { $prev = $v }
  }
  return $out
}

function Format-Value {
  param($Value, [int]$Decimals = 2)
  if ($null -eq $Value) { return "N/A" }
  return $Value.ToString("N$Decimals", [Globalization.CultureInfo]::InvariantCulture)
}

function Format-Change {
  param($Value)
  if ($null -eq $Value) { return "N/A" }
  if ($Value -ge 0) {
    return "+" + $Value.ToString("N2", [Globalization.CultureInfo]::InvariantCulture) + "%"
  }
  return $Value.ToString("N2", [Globalization.CultureInfo]::InvariantCulture) + "%"
}

function Row {
  param([string]$Name, $Series, [string]$Date)
  $entry = $Series[$Date]
  if ($null -eq $entry) {
    return "$Name | N/A | N/A"
  }
  return "$Name | $(Format-Change $entry.change) | $(Format-Value $entry.value)"
}

function GlobalRow {
  param([string]$Name, [string]$Region, $Series, [string]$Date)
  $entry = $Series[$Date]
  if ($null -eq $entry) {
    return "$Name | $Region | N/A | N/A"
  }
  return "$Name | $Region | $(Format-Change $entry.change) | $(Format-Value $entry.value)"
}

$fred = Join-Path $RawDataDir "fred"
$yahoo = Join-Path $RawDataDir "yahoo"
$stooq = Join-Path $RawDataDir "stooq"

$sp500 = Add-ChangePct (Merge-Series (Read-YahooSeries (Join-Path $yahoo "sp500.json")) (Merge-Series (Read-FredSeries (Join-Path $fred "sp500.csv")) (Read-StooqSeries (Join-Path $stooq "sp500.csv"))))
$nasdaq = Add-ChangePct (Merge-Series (Read-YahooSeries (Join-Path $yahoo "nasdaq.json")) (Merge-Series (Read-FredSeries (Join-Path $fred "nasdaq.csv")) (Read-StooqSeries (Join-Path $stooq "nasdaq.csv"))))
$dow = Add-ChangePct (Merge-Series (Read-YahooSeries (Join-Path $yahoo "dow.json")) (Merge-Series (Read-FredSeries (Join-Path $fred "dow.csv")) (Read-StooqSeries (Join-Path $stooq "dow.csv"))))
$russell2000 = Add-ChangePct (Read-YahooSeries (Join-Path $yahoo "russell2000.json"))
$vix = Add-ChangePct (Merge-Series (Read-YahooSeries (Join-Path $yahoo "vix.json")) (Read-FredSeries (Join-Path $fred "vix.csv")))
$kospi = Add-ChangePct (Read-YahooSeries (Join-Path $yahoo "kospi.json"))
$nikkei = Add-ChangePct (Read-YahooSeries (Join-Path $yahoo "nikkei225.json"))
$hangseng = Add-ChangePct (Read-YahooSeries (Join-Path $yahoo "hangseng.json"))
$shanghai = Add-ChangePct (Read-YahooSeries (Join-Path $yahoo "shanghai.json"))
$stoxx = Add-ChangePct (Read-YahooSeries (Join-Path $yahoo "stoxx600.json"))

$start = [datetime]::Parse($StartDate)
$end = [datetime]::Parse($EndDate)
$updated = 0

for ($d = $start; $d -le $end; $d = $d.AddDays(1)) {
  $key = $d.ToString("yyyy-MM-dd")
  $path = Join-Path $ReportsDir "$key-daily-global-finance-report.md"
  if (-not (Test-Path $path)) { continue }

  $text = Get-Content -Raw -Encoding UTF8 $path

  $usTable = @"
지수 | 등락 | 마감
--- | ---: | ---:
$(Row "S&P 500" $sp500 $key)
$(Row "Nasdaq Composite" $nasdaq $key)
$(Row "Dow Jones Industrial Average" $dow $key)
$(Row "Russell 2000" $russell2000 $key)
$(Row "VIX" $vix $key)

"@

$globalTable = @"
지수 | 지역 | 등락 | 마감
--- | --- | ---: | ---:
$(GlobalRow "KOSPI" "Korea" $kospi $key)
$(GlobalRow "Nikkei 225" "Japan" $nikkei $key)
$(GlobalRow "Shanghai Composite" "China" $shanghai $key)
$(GlobalRow "Hang Seng" "Hong Kong" $hangseng $key)
$(GlobalRow "STOXX Europe 600" "Europe" $stoxx $key)

"@

  $text = [regex]::Replace($text, "(?s)(## 3\)[^\r\n]*\r?\n\r?\n).*?(?=\r?\n## 4\))", "`$1$usTable")
  $text = [regex]::Replace($text, "(?s)(## 4\)[^\r\n]*\r?\n\r?\n).*?(?=\r?\n## 5\))", "`$1$globalTable")

  Set-Content -Path $path -Value $text -Encoding UTF8
  $updated++
}

Write-Host "Updated $updated report files from local market data."




