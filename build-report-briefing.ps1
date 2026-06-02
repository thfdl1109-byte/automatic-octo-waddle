param(
  [string]$DerivedDir = "data\derived"
)

$ErrorActionPreference = "Continue"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $root) { $root = Get-Location }
Set-Location $root

function Read-JsonSafe {
  param([string]$Path)
  if (-not (Test-Path $Path)) { return $null }
  try { return Get-Content -Raw -Encoding UTF8 $Path | ConvertFrom-Json } catch { return $null }
}

$stocks = Read-JsonSafe (Join-Path $DerivedDir "us-interesting-stocks.json")
$macro = Read-JsonSafe (Join-Path $DerivedDir "macro-snapshot.json")
$news = Read-JsonSafe (Join-Path $DerivedDir "news-digest.json")
$breadth = Read-JsonSafe (Join-Path $DerivedDir "market-breadth.json")
$quality = Read-JsonSafe (Join-Path $DerivedDir "data-quality.json")

$topStocks = if ($stocks) { @($stocks.selected) | Select-Object -First 10 } else { @() }
$topNews = if ($news) { @($news.selected) | Select-Object -First 8 } else { @() }
$macroItems = if ($macro) { @($macro.items) } else { @() }
$breadthSignals = if ($breadth) { @($breadth.signals) } else { @() }

$themes = New-Object System.Collections.Generic.List[string]
if ($topStocks | Where-Object { $_.sector -eq "semiconductors" -or $_.ticker -in @("NVDA", "MU", "AVGO", "MRVL", "AMD") }) {
  $themes.Add("AI / semiconductor leadership or volatility") | Out-Null
}
if ($macroItems | Where-Object { $_.key -match "wti|brent|oil" -and ([Math]::Abs([double]($_.change_pct -as [double])) -gt 1) }) {
  $themes.Add("oil price sensitivity") | Out-Null
}
if ($breadthSignals -contains "small caps lag" -or $breadthSignals -contains "narrow mega-cap leadership") {
  $themes.Add("market breadth risk") | Out-Null
}
if ($topNews | Where-Object { $_.event -eq "Rates / Fed / inflation" }) {
  $themes.Add("rates / inflation watch") | Out-Null
}
if ($themes.Count -eq 0) { $themes.Add("balanced market check") | Out-Null }

$out = [pscustomobject]@{
  generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  quality = if ($quality) { [pscustomobject]@{ status = $quality.status; score = $quality.score; warnings = $quality.warnings } } else { $null }
  suggested_themes = @($themes.ToArray())
  breadth_signals = @($breadthSignals)
  top_stocks = @($topStocks)
  macro_items = @($macroItems)
  top_news = @($topNews)
}

$jsonPath = Join-Path $DerivedDir "report-briefing.json"
$mdPath = Join-Path $DerivedDir "report-briefing.md"
$out | ConvertTo-Json -Depth 12 | Set-Content -Path $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Report Briefing") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("Generated at: $($out.generated_at)") | Out-Null
if ($out.quality) { $lines.Add("Quality: $($out.quality.status) / $($out.quality.score)") | Out-Null }
$lines.Add("") | Out-Null
$lines.Add("Suggested themes: $($out.suggested_themes -join ', ')") | Out-Null
$lines.Add("Breadth signals: $($out.breadth_signals -join ', ')") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("## Top Stocks") | Out-Null
foreach ($s in $out.top_stocks) {
  $lines.Add("- $($s.ticker) [$($s.sector)]: $($s.change_pct)% score=$($s.score)") | Out-Null
}
$lines.Add("") | Out-Null
$lines.Add("## Top News") | Out-Null
foreach ($n in $out.top_news) {
  $lines.Add("- [$($n.event)] $($n.title)") | Out-Null
}
$lines | Set-Content -Path $mdPath -Encoding UTF8

Write-Host "Wrote $jsonPath and $mdPath"
