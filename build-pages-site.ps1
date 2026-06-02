param(
  [string]$ReportsIndexPath = "reports\index.json",
  [string]$OutDir = "docs",
  [int]$ArchiveLimit = 200
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

function Escape-Html {
  param([string]$Text)
  if ($null -eq $Text) { return "" }
  return [System.Net.WebUtility]::HtmlEncode($Text)
}

function Convert-InlineMarkdown {
  param([string]$Text)
  $out = Escape-Html $Text
  $out = [regex]::Replace($out, "\[([^\]]+)\]\(([^)]+)\)", {
    param($m)
    $label = $m.Groups[1].Value
    $url = $m.Groups[2].Value
    "<a href=""$url"">$label</a>"
  })
  $out = [regex]::Replace($out, "\*\*([^*]+)\*\*", "<strong>`$1</strong>")
  $out = [regex]::Replace($out, '`([^`]+)`', '<code>$1</code>')
  return $out
}

function Convert-MarkdownToHtml {
  param([string]$Markdown)

  $lines = $Markdown -split "`r?`n"
  $html = New-Object System.Collections.Generic.List[string]
  $i = 0
  while ($i -lt $lines.Count) {
    $line = $lines[$i]
    if ([string]::IsNullOrWhiteSpace($line)) {
      $i++
      continue
    }

    if ($line -match "^(#{1,4})\s+(.+)$") {
      $level = [Math]::Min($matches[1].Length, 4)
      $headingText = $matches[2]
      $html.Add("<h$level>$(Convert-InlineMarkdown $headingText)</h$level>") | Out-Null
      $i++
      continue
    }

    if ($line.Trim().StartsWith("|")) {
      $tableRows = New-Object System.Collections.Generic.List[string]
      while ($i -lt $lines.Count -and $lines[$i].Trim().StartsWith("|")) {
        $tableRows.Add($lines[$i]) | Out-Null
        $i++
      }
      if ($tableRows.Count -ge 2) {
        $html.Add("<div class=""table-wrap""><table>") | Out-Null
        for ($r = 0; $r -lt $tableRows.Count; $r++) {
          if ($r -eq 1 -and $tableRows[$r] -match "^\|\s*:?-{2,}") { continue }
          $cells = $tableRows[$r].Trim().Trim("|").Split("|") | ForEach-Object { $_.Trim() }
          $tag = if ($r -eq 0) { "th" } else { "td" }
          $html.Add("<tr>") | Out-Null
          foreach ($cell in $cells) {
            $html.Add("<$tag>$(Convert-InlineMarkdown $cell)</$tag>") | Out-Null
          }
          $html.Add("</tr>") | Out-Null
        }
        $html.Add("</table></div>") | Out-Null
      }
      continue
    }

    if ($line -match "^\s*[-*]\s+(.+)$") {
      $html.Add("<ul>") | Out-Null
      while ($i -lt $lines.Count -and $lines[$i] -match "^\s*[-*]\s+(.+)$") {
        $text = $matches[1]
        $html.Add("<li>$(Convert-InlineMarkdown $text)</li>") | Out-Null
        $i++
      }
      $html.Add("</ul>") | Out-Null
      continue
    }

    $paragraph = New-Object System.Collections.Generic.List[string]
    while ($i -lt $lines.Count -and -not [string]::IsNullOrWhiteSpace($lines[$i]) -and -not ($lines[$i] -match "^(#{1,4})\s+") -and -not $lines[$i].Trim().StartsWith("|") -and -not ($lines[$i] -match "^\s*[-*]\s+")) {
      $paragraph.Add($lines[$i].Trim()) | Out-Null
      $i++
    }
    $paragraphText = $paragraph -join " "
    $html.Add("<p>$(Convert-InlineMarkdown $paragraphText)</p>") | Out-Null
  }
  return ($html -join "`n")
}

function New-PageHtml {
  param(
    [string]$Title,
    [string]$BodyHtml,
    [string]$Subtitle = ""
  )
  $subtitleHtml = if ($Subtitle) { "<p class=""subtitle"">$(Escape-Html $Subtitle)</p>" } else { "" }
  return @"
<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$(Escape-Html $Title)</title>
  <style>
    :root { color-scheme: light; --ink:#1d252f; --muted:#667085; --line:#d9dee7; --panel:#f6f8fb; --accent:#0f766e; --accent2:#334155; }
    * { box-sizing: border-box; }
    body { margin:0; font-family: Arial, "Malgun Gothic", sans-serif; color:var(--ink); background:#ffffff; line-height:1.65; }
    header { border-bottom:1px solid var(--line); background:#f9fafb; }
    .wrap { max-width:1080px; margin:0 auto; padding:28px 20px; }
    nav { display:flex; gap:14px; flex-wrap:wrap; margin-bottom:18px; font-size:14px; }
    nav a { color:var(--accent); text-decoration:none; font-weight:700; }
    h1 { margin:0 0 8px; font-size:30px; line-height:1.25; letter-spacing:0; }
    h2 { margin-top:30px; padding-top:10px; border-top:1px solid var(--line); font-size:22px; }
    h3 { margin-top:24px; font-size:18px; }
    .subtitle, .meta { color:var(--muted); margin:0; }
    .panel { background:var(--panel); border:1px solid var(--line); border-radius:8px; padding:16px; margin:18px 0; }
    .grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(220px,1fr)); gap:12px; }
    .report-card { border:1px solid var(--line); border-radius:8px; padding:14px; background:white; }
    .report-card a { color:var(--accent2); text-decoration:none; font-weight:700; }
    .table-wrap { overflow-x:auto; margin:16px 0; border:1px solid var(--line); border-radius:8px; }
    table { width:100%; border-collapse:collapse; min-width:620px; background:white; }
    th, td { border-bottom:1px solid var(--line); padding:9px 10px; text-align:left; vertical-align:top; }
    th { background:#eef2f7; font-size:14px; }
    tr:last-child td { border-bottom:0; }
    code { background:#eef2f7; padding:2px 5px; border-radius:4px; }
    a { color:var(--accent); }
    footer { color:var(--muted); border-top:1px solid var(--line); margin-top:34px; padding-top:18px; font-size:13px; }
    @media (max-width:640px) { .wrap { padding:22px 14px; } h1 { font-size:24px; } table { min-width:520px; } }
  </style>
</head>
<body>
  <header>
    <div class="wrap">
      <nav><a href="./index.html">Home</a><a href="./latest.html">Latest Report</a><a href="https://github.com/thfdl1109-byte/automatic-octo-waddle">GitHub</a></nav>
      <h1>$(Escape-Html $Title)</h1>
      $subtitleHtml
    </div>
  </header>
  <main class="wrap">
    $BodyHtml
  <footer>Generated by the local finance-report automation.</footer>
  </main>
</body>
</html>
"@
}

$index = Read-JsonSafe $ReportsIndexPath
if (-not $index -or -not $index.reports) {
  Write-Error "Missing reports index: $ReportsIndexPath"
  exit 1
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$reportsOutDir = Join-Path $OutDir "reports"
New-Item -ItemType Directory -Force -Path $reportsOutDir | Out-Null
Get-ChildItem -Path $reportsOutDir -Filter "*.html" -File -ErrorAction SilentlyContinue |
  Remove-Item -Force
Set-Content -Path (Join-Path $OutDir ".nojekyll") -Value "" -Encoding UTF8

$reportLinks = New-Object System.Collections.Generic.List[object]
foreach ($report in (@($index.reports) | Select-Object -First $ArchiveLimit)) {
  if (-not (Test-Path $report.path)) { continue }
  $md = Get-Content -Raw -Encoding UTF8 $report.path
  $body = Convert-MarkdownToHtml $md
  $safeName = "$($report.date)-daily-global-finance-report.html"
  $outPath = Join-Path $reportsOutDir $safeName
  $page = New-PageHtml -Title "Daily Report $($report.date)" -Subtitle $report.updated_at -BodyHtml $body
  Set-Content -Path $outPath -Value $page -Encoding UTF8
  $reportLinks.Add([pscustomobject]@{
    date = $report.date
    href = "reports/$safeName"
    name = $report.name
    updated_at = $report.updated_at
  }) | Out-Null
}

$latest = $reportLinks | Select-Object -First 1
if ($latest) {
  Copy-Item -LiteralPath (Join-Path $reportsOutDir "$($latest.date)-daily-global-finance-report.html") -Destination (Join-Path $OutDir "latest.html") -Force
}

$cards = New-Object System.Collections.Generic.List[string]
foreach ($item in ($reportLinks | Select-Object -First 30)) {
  $cards.Add("<div class=""report-card""><a href=""$($item.href)"">$($item.date) Daily Report</a><p class=""meta"">$($item.updated_at)</p></div>") | Out-Null
}

$archiveRows = New-Object System.Collections.Generic.List[string]
foreach ($item in $reportLinks) {
  $archiveRows.Add("<tr><td>$($item.date)</td><td><a href=""$($item.href)"">$($item.name)</a></td><td>$($item.updated_at)</td></tr>") | Out-Null
}

$latestBlock = if ($latest) {
  "<section class=""panel""><h2>Latest</h2><p><a href=""latest.html"">$($latest.date) Latest Report</a></p></section>"
} else {
  "<section class=""panel""><h2>Latest</h2><p>No reports published yet.</p></section>"
}

$indexBody = @"
$latestBlock
<section>
  <h2>Recent Reports</h2>
  <div class="grid">
    $($cards -join "`n")
  </div>
</section>
<section>
  <h2>Archive</h2>
  <div class="table-wrap">
    <table>
      <tr><th>Date</th><th>Report</th><th>Updated</th></tr>
      $($archiveRows -join "`n")
    </table>
  </div>
</section>
"@

$homeHtml = New-PageHtml -Title "Daily Global Finance Report" -Subtitle "Automated investment report archive" -BodyHtml $indexBody
Set-Content -Path (Join-Path $OutDir "index.html") -Value $homeHtml -Encoding UTF8

Copy-Item -LiteralPath $ReportsIndexPath -Destination (Join-Path $OutDir "reports-index.json") -Force

Write-Host "Wrote GitHub Pages site to $OutDir"
