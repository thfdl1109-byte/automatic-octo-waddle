param(
  [string]$StartDate = "2026-01-01",
  [string]$EndDate = (Get-Date -Format "yyyy-MM-dd"),
  [string]$SourcesPath = "data\sources.json",
  [string[]]$Providers = @("fred", "yahoo", "stooq", "polygon", "finnhub", "alphavantage", "newsapi"),
  [int]$RequestTimeoutSec = 20,
  [int]$RateLimitDelaySec = 13,
  [int]$FinnhubDelayMs = 1100,
  [int]$MaxFinnhubQuoteTickers = 55,
  [int]$MaxFinnhubNewsTickers = 20,
  [int]$MaxPolygonDailyTickers = 20,
  [switch]$SkipDerived
)

$ErrorActionPreference = "Continue"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $root) { $root = Get-Location }
Set-Location $root

$envPath = Join-Path $root ".env"
if (Test-Path $envPath) {
  Get-Content $envPath | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
      $parts = $line.Split("=", 2)
      $name = $parts[0].Trim()
      $value = $parts[1].Trim().Trim('"').Trim("'")
      [Environment]::SetEnvironmentVariable($name, $value, "Process")
    }
  }
}

$sources = Get-Content -Raw -Encoding UTF8 $SourcesPath | ConvertFrom-Json
$fetchStartedAt = Get-Date
$fetchResults = New-Object System.Collections.Generic.List[object]

$rawDir = Join-Path $root "data\raw"
$fredDir = Join-Path $rawDir "fred"
$yahooDir = Join-Path $rawDir "yahoo"
$stooqDir = Join-Path $rawDir "stooq"
$polygonDir = Join-Path $rawDir "polygon"
$finnhubDir = Join-Path $rawDir "finnhub"
$alphaVantageDir = Join-Path $rawDir "alphavantage"
$twelveDataDir = Join-Path $rawDir "twelvedata"
$kisDir = Join-Path $rawDir "kis"
$newsApiDir = Join-Path $rawDir "newsapi"
$logDir = Join-Path $root "data\logs"

New-Item -ItemType Directory -Force -Path $fredDir, $yahooDir, $stooqDir, $polygonDir, $finnhubDir, $alphaVantageDir, $twelveDataDir, $kisDir, $newsApiDir, $logDir | Out-Null

function Write-Log {
  param([string]$Message)
  $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  "$stamp $Message" | Tee-Object -FilePath (Join-Path $logDir "fetch-market-data.log") -Append
}

function Add-FetchResult {
  param(
    [string]$Label,
    [string]$Status,
    [string]$Detail = "",
    [string]$OutFile = ""
  )
  $fetchResults.Add([pscustomobject]@{
    label = $Label
    status = $Status
    detail = $Detail
    file = $OutFile
  }) | Out-Null
}

function Has-Provider {
  param([string]$Name)
  $normalized = @()
  foreach ($provider in $Providers) {
    $normalized += ([string]$provider).Split(",") | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ }
  }
  return ($normalized -contains $Name.ToLowerInvariant() -or $normalized -contains "all")
}

function Get-EnvValue {
  param([string]$Name)
  $value = [Environment]::GetEnvironmentVariable($Name, "Process")
  if ([string]::IsNullOrWhiteSpace($value)) { return $null }
  return $value.Trim()
}

function Invoke-Download {
  param(
    [string]$Url,
    [string]$OutFile,
    [string]$Label,
    [hashtable]$Headers = $null,
    [string]$Method = "GET",
    [string]$Body = $null,
    [string]$ContentType = $null
  )

  Write-Log "GET $Label -> $OutFile"
  try {
    $params = @{
      Uri = $Url
      OutFile = $OutFile
      UseBasicParsing = $true
      TimeoutSec = $RequestTimeoutSec
      Method = $Method
    }
    if ($null -ne $Headers) { $params.Headers = $Headers }
    if (-not [string]::IsNullOrWhiteSpace($Body)) { $params.Body = $Body }
    if (-not [string]::IsNullOrWhiteSpace($ContentType)) { $params.ContentType = $ContentType }
    Invoke-WebRequest @params
    Write-Log "OK  $Label"
    Add-FetchResult -Label $Label -Status "OK" -OutFile $OutFile
  } catch {
    Write-Log "ERR $Label $($_.Exception.Message)"
    Add-FetchResult -Label $Label -Status "ERR" -Detail $_.Exception.Message -OutFile $OutFile
  }
}

function Invoke-Json {
  param(
    [string]$Url,
    [string]$OutFile,
    [string]$Label,
    [hashtable]$Headers = $null,
    [string]$Method = "GET",
    [object]$BodyObject = $null
  )

  Write-Log "GET $Label -> $OutFile"
  try {
    $params = @{
      Uri = $Url
      TimeoutSec = $RequestTimeoutSec
      Method = $Method
    }
    if ($null -ne $Headers) { $params.Headers = $Headers }
    if ($null -ne $BodyObject) {
      $params.Body = ($BodyObject | ConvertTo-Json -Depth 10)
      $params.ContentType = "application/json"
    }
    $response = Invoke-RestMethod @params
    $response | ConvertTo-Json -Depth 20 | Set-Content -Path $OutFile -Encoding UTF8
    Write-Log "OK  $Label"
    Add-FetchResult -Label $Label -Status "OK" -OutFile $OutFile
    return $response
  } catch {
    Write-Log "ERR $Label $($_.Exception.Message)"
    Add-FetchResult -Label $Label -Status "ERR" -Detail $_.Exception.Message -OutFile $OutFile
    return $null
  }
}

function Join-Symbols {
  param($Symbols)
  return ($Symbols | ForEach-Object { [uri]::EscapeDataString([string]$_) }) -join ","
}

function Get-PriorityNewsTickers {
  param($Watchlist, [int]$Limit)
  $priority = @(
    "NVDA", "AMD", "MSFT", "AAPL", "TSLA", "MU", "DELL", "SMCI", "HPE", "VRT", "ANET", "AVGO", "META", "GOOGL", "AMZN",
    "INTC", "QCOM", "MRVL", "ARM", "ORCL", "IBM", "NOW", "CRM",
    "JPM", "BAC", "GS", "MS", "XOM", "CVX", "COP", "LLY", "UNH",
    "NOC", "RTX", "LMT", "BA", "WMT", "COST", "HD", "DIS", "DAL", "FDX",
    "V", "MA", "COIN", "HOOD"
  )
  $ordered = New-Object System.Collections.Generic.List[string]
  foreach ($ticker in $priority) {
    if ($Watchlist -contains $ticker -and -not $ordered.Contains($ticker)) { $ordered.Add($ticker) | Out-Null }
  }
  foreach ($ticker in $Watchlist) {
    $t = ([string]$ticker).ToUpperInvariant()
    if (-not $ordered.Contains($t)) { $ordered.Add($t) | Out-Null }
  }
  return $ordered | Select-Object -First $Limit
}

function Get-PriorityDailyTickers {
  param($Watchlist, [int]$Limit)
  $priority = @(
    "SPY", "QQQ", "DIA", "IWM", "RSP", "SMH",
    "NVDA", "AMD", "MSFT", "AAPL", "TSLA", "MU", "DELL", "SMCI", "HPE", "VRT", "ANET", "AVGO", "META", "GOOGL", "AMZN",
    "JPM", "XOM", "LLY"
  )
  $ordered = New-Object System.Collections.Generic.List[string]
  foreach ($ticker in $priority) {
    if ($Watchlist -contains $ticker -and -not $ordered.Contains($ticker)) { $ordered.Add($ticker) | Out-Null }
  }
  foreach ($ticker in $Watchlist) {
    $t = ([string]$ticker).ToUpperInvariant()
    if (-not $ordered.Contains($t)) { $ordered.Add($t) | Out-Null }
  }
  return $ordered | Select-Object -First $Limit
}

function Get-PriorityQuoteTickers {
  param($Watchlist, [int]$Limit)
  $priority = @(
    "SPY", "QQQ", "DIA", "IWM", "RSP", "SMH", "XLF", "XLE", "XLV", "XLY", "XLP", "XLI", "XLU",
    "NVDA", "AMD", "MSFT", "AAPL", "TSLA", "MU", "DELL", "SMCI", "HPE", "VRT", "ANET", "ETN", "CEG", "GEV", "PWR", "AVGO", "META", "GOOGL", "AMZN",
    "INTC", "QCOM", "MRVL", "ARM", "ORCL", "IBM", "NOW", "CRM",
    "JPM", "BAC", "GS", "MS", "C", "BRK.B",
    "XOM", "CVX", "COP", "SLB", "OXY",
    "LLY", "UNH", "JNJ", "PFE", "MRK", "ABBV",
    "NOC", "RTX", "LMT", "GD", "BA",
    "WMT", "COST", "HD", "MCD"
  )
  $ordered = New-Object System.Collections.Generic.List[string]
  foreach ($ticker in $priority) {
    if ($Watchlist -contains $ticker -and -not $ordered.Contains($ticker)) { $ordered.Add($ticker) | Out-Null }
  }
  foreach ($ticker in $Watchlist) {
    $t = ([string]$ticker).ToUpperInvariant()
    if (-not $ordered.Contains($t)) { $ordered.Add($t) | Out-Null }
  }
  return $ordered | Select-Object -First $Limit
}

$start = [datetime]::Parse($StartDate)
$end = [datetime]::Parse($EndDate)
$epoch = [datetime]"1970-01-01T00:00:00Z"
$period1 = [int][Math]::Floor(($start.ToUniversalTime() - $epoch).TotalSeconds)
$period2 = [int][Math]::Floor(($end.AddDays(1).ToUniversalTime() - $epoch).TotalSeconds)
$d1 = $start.ToString("yyyyMMdd")
$d2 = $end.ToString("yyyyMMdd")
$isoEnd = $end.ToString("yyyy-MM-dd")
$newsStart = $end.AddDays(-3).ToString("yyyy-MM-dd")

if (Has-Provider "fred") {
  $fredKey = Get-EnvValue "FRED_API_KEY"
  if ($fredKey) {
    foreach ($item in $sources.fred) {
      $url = "https://api.stlouisfed.org/fred/series/observations?series_id=$($item.id)&api_key=$fredKey&file_type=json&observation_start=$StartDate&observation_end=$EndDate"
      $out = Join-Path $fredDir ($item.file -replace "\.csv$", ".json")
      Invoke-Download -Url $url -OutFile $out -Label "FRED_API:$($item.id)"
      Start-Sleep -Seconds $RateLimitDelaySec
    }
  } else {
    Write-Log "SKIP FRED_API missing FRED_API_KEY; using CSV fallback"
    Add-FetchResult -Label "FRED_API" -Status "SKIP" -Detail "missing FRED_API_KEY"
    foreach ($item in $sources.fred) {
      $url = "https://fred.stlouisfed.org/graph/fredgraph.csv?id=$($item.id)&cosd=$StartDate&coed=$EndDate"
      $out = Join-Path $fredDir $item.file
      Invoke-Download -Url $url -OutFile $out -Label "FRED:$($item.id)"
    }
  }
}

if (Has-Provider "yahoo") {
  foreach ($item in $sources.yahoo) {
    $symbol = [uri]::EscapeDataString($item.symbol)
    $url = "https://query1.finance.yahoo.com/v8/finance/chart/$symbol" +
           "?period1=$period1&period2=$period2&interval=1d&events=history"
    $out = Join-Path $yahooDir $item.file
    Invoke-Download -Url $url -OutFile $out -Label "YAHOO:$($item.symbol)"
  }
}

if (Has-Provider "stooq") {
  foreach ($item in $sources.stooq) {
    $symbol = [uri]::EscapeDataString($item.symbol)
    $url = "https://stooq.com/q/d/l/?s=$symbol&i=d&d1=$d1&d2=$d2"
    $out = Join-Path $stooqDir $item.file
    Invoke-Download -Url $url -OutFile $out -Label "STOOQ:$($item.symbol)"
  }
}

if (Has-Provider "polygon") {
  $polygonKey = Get-EnvValue "POLYGON_API_KEY"
  if ($polygonKey) {
    $polygonGrouped = Get-EnvValue "POLYGON_ENABLE_GROUPED"
    if ($polygonGrouped -and $polygonGrouped.ToLowerInvariant() -in @("1", "true", "yes")) {
      $groupedUrl = "https://api.polygon.io/v2/aggs/grouped/locale/us/market/stocks/$isoEnd" +
                    "?adjusted=true&include_otc=false&apiKey=$polygonKey"
      Invoke-Download -Url $groupedUrl -OutFile (Join-Path $polygonDir "us-stocks-grouped-$isoEnd.json") -Label "POLYGON:US_GROUPED:$isoEnd"
      Start-Sleep -Seconds $RateLimitDelaySec
    } else {
      Write-Log "SKIP POLYGON:US_GROUPED disabled; set POLYGON_ENABLE_GROUPED=true to enable"
      Add-FetchResult -Label "POLYGON:US_GROUPED" -Status "SKIP" -Detail "disabled by default"
    }

    foreach ($symbol in (Get-PriorityDailyTickers -Watchlist $sources.us_watchlist -Limit $MaxPolygonDailyTickers)) {
      $s = [uri]::EscapeDataString([string]$symbol)
      $url = "https://api.polygon.io/v2/aggs/ticker/$s/range/1/day/$StartDate/$EndDate" +
             "?adjusted=true&sort=asc&limit=50000&apiKey=$polygonKey"
      Invoke-Download -Url $url -OutFile (Join-Path $polygonDir "$symbol-daily.json") -Label "POLYGON:DAILY:$symbol"
      Start-Sleep -Seconds $RateLimitDelaySec
    }
  } else {
    Write-Log "SKIP POLYGON missing POLYGON_API_KEY"
  }
}

if (Has-Provider "finnhub") {
  $finnhubKey = Get-EnvValue "FINNHUB_API_KEY"
  if ($finnhubKey) {
    Invoke-Download -Url "https://finnhub.io/api/v1/news?category=general&token=$finnhubKey" -OutFile (Join-Path $finnhubDir "market-news.json") -Label "FINNHUB:MARKET_NEWS"
    Start-Sleep -Milliseconds $FinnhubDelayMs

    foreach ($symbol in (Get-PriorityQuoteTickers -Watchlist $sources.us_watchlist -Limit $MaxFinnhubQuoteTickers)) {
      $s = [uri]::EscapeDataString([string]$symbol)
      Invoke-Download -Url "https://finnhub.io/api/v1/quote?symbol=$s&token=$finnhubKey" -OutFile (Join-Path $finnhubDir "$symbol-quote.json") -Label "FINNHUB:QUOTE:$symbol"
      Start-Sleep -Milliseconds $FinnhubDelayMs
    }

    foreach ($symbol in (Get-PriorityNewsTickers -Watchlist $sources.us_watchlist -Limit $MaxFinnhubNewsTickers)) {
      $s = [uri]::EscapeDataString([string]$symbol)
      Invoke-Download -Url "https://finnhub.io/api/v1/company-news?symbol=$s&from=$newsStart&to=$isoEnd&token=$finnhubKey" -OutFile (Join-Path $finnhubDir "$symbol-news.json") -Label "FINNHUB:NEWS:$symbol"
      Start-Sleep -Milliseconds $FinnhubDelayMs
    }
  } else {
    Write-Log "SKIP FINNHUB missing FINNHUB_API_KEY"
  }
}

if (Has-Provider "alphavantage") {
  $alphaKey = Get-EnvValue "ALPHA_VANTAGE_API_KEY"
  if ($alphaKey) {
    Invoke-Download -Url "https://www.alphavantage.co/query?function=TOP_GAINERS_LOSERS&apikey=$alphaKey" -OutFile (Join-Path $alphaVantageDir "top-gainers-losers.json") -Label "ALPHAVANTAGE:TOP_GAINERS_LOSERS"
    Invoke-Download -Url "https://www.alphavantage.co/query?function=NEWS_SENTIMENT&topics=financial_markets,economy_macro,technology&apikey=$alphaKey" -OutFile (Join-Path $alphaVantageDir "news-sentiment.json") -Label "ALPHAVANTAGE:NEWS_SENTIMENT"

    foreach ($symbol in @("SPY", "QQQ", "DIA", "IWM")) {
      Invoke-Download -Url "https://www.alphavantage.co/query?function=TIME_SERIES_DAILY&symbol=$symbol&outputsize=compact&apikey=$alphaKey" -OutFile (Join-Path $alphaVantageDir "$symbol-daily.json") -Label "ALPHAVANTAGE:DAILY:$symbol"
    }
  } else {
    Write-Log "SKIP ALPHAVANTAGE missing ALPHA_VANTAGE_API_KEY"
  }
}

if (Has-Provider "twelvedata") {
  $twelveKey = Get-EnvValue "TWELVE_DATA_API_KEY"
  if ($twelveKey) {
    $symbols = Join-Symbols $sources.twelve_data
    Invoke-Download -Url "https://api.twelvedata.com/quote?symbol=$symbols&apikey=$twelveKey" -OutFile (Join-Path $twelveDataDir "quotes.json") -Label "TWELVEDATA:QUOTES"
    Start-Sleep -Seconds $RateLimitDelaySec
    Invoke-Download -Url "https://api.twelvedata.com/time_series?symbol=$symbols&interval=1day&start_date=$StartDate&end_date=$EndDate&apikey=$twelveKey" -OutFile (Join-Path $twelveDataDir "daily-time-series.json") -Label "TWELVEDATA:DAILY"
  } else {
    Write-Log "SKIP TWELVEDATA missing TWELVE_DATA_API_KEY"
  }
}

if (Has-Provider "newsapi") {
  $newsApiKey = Get-EnvValue "NEWS_API_KEY"
  if ($newsApiKey) {
    $query = [uri]::EscapeDataString('(stock market OR Federal Reserve OR Nvidia OR oil OR inflation OR bonds)')
    $url = "https://newsapi.org/v2/everything?q=$query&language=en&sortBy=publishedAt&pageSize=50&from=$newsStart&apiKey=$newsApiKey"
    Invoke-Download -Url $url -OutFile (Join-Path $newsApiDir "market-headlines.json") -Label "NEWSAPI:MARKET_HEADLINES"
  } else {
    Write-Log "SKIP NEWSAPI missing NEWS_API_KEY"
  }
}

if (Has-Provider "kis") {
  $kisKey = Get-EnvValue "KOREA_INVESTMENT_APP_KEY"
  $kisSecret = Get-EnvValue "KOREA_INVESTMENT_APP_SECRET"
  $kisBase = Get-EnvValue "KOREA_INVESTMENT_BASE_URL"
  if (-not $kisBase) { $kisBase = "https://openapi.koreainvestment.com:9443" }

  if ($kisKey -and $kisSecret) {
    $token = $null
    Write-Log "GET KIS:TOKEN -> memory-only"
    try {
      $token = Invoke-RestMethod -Uri "$kisBase/oauth2/tokenP" `
        -TimeoutSec $RequestTimeoutSec `
        -Method "POST" `
        -ContentType "application/json" `
        -Body (@{ grant_type = "client_credentials"; appkey = $kisKey; appsecret = $kisSecret } | ConvertTo-Json -Depth 10)
      Write-Log "OK  KIS:TOKEN"
    } catch {
      Write-Log "ERR KIS:TOKEN $($_.Exception.Message)"
    }

    if ($null -ne $token -and $token.access_token) {
      $headers = @{
        "authorization" = "Bearer $($token.access_token)"
        "appkey" = $kisKey
        "appsecret" = $kisSecret
        "tr_id" = "FHKST01010100"
        "custtype" = "P"
      }
      foreach ($item in $sources.kis_domestic_stocks) {
        $url = "$kisBase/uapi/domestic-stock/v1/quotations/inquire-price?FID_COND_MRKT_DIV_CODE=J&FID_INPUT_ISCD=$($item.symbol)"
        Invoke-Download -Url $url -OutFile (Join-Path $kisDir $item.file) -Label "KIS:DOMESTIC_QUOTE:$($item.symbol)" -Headers $headers
      }
    } else {
      Write-Log "SKIP KIS quotes because token request did not return access_token"
    }
  } else {
    Write-Log "SKIP KIS missing KOREA_INVESTMENT_APP_KEY or KOREA_INVESTMENT_APP_SECRET"
    Add-FetchResult -Label "KIS" -Status "SKIP" -Detail "missing KOREA_INVESTMENT_APP_KEY or KOREA_INVESTMENT_APP_SECRET"
  }
}

if (-not $SkipDerived) {
  $selector = Join-Path $root "select-interesting-stocks.ps1"
  if (Test-Path $selector) {
    Write-Log "DERIVED select-interesting-stocks"
    try {
      & powershell -ExecutionPolicy Bypass -File $selector | Out-Null
      Add-FetchResult -Label "DERIVED:US_INTERESTING_STOCKS" -Status "OK" -OutFile (Join-Path $root "data\derived\us-interesting-stocks.json")
      Write-Log "OK  DERIVED:US_INTERESTING_STOCKS"
    } catch {
      Add-FetchResult -Label "DERIVED:US_INTERESTING_STOCKS" -Status "ERR" -Detail $_.Exception.Message
      Write-Log "ERR DERIVED:US_INTERESTING_STOCKS $($_.Exception.Message)"
    }
  }
  $macroBuilder = Join-Path $root "build-macro-snapshot.ps1"
  if (Test-Path $macroBuilder) {
    Write-Log "DERIVED build-macro-snapshot"
    try {
      & powershell -ExecutionPolicy Bypass -File $macroBuilder | Out-Null
      Add-FetchResult -Label "DERIVED:MACRO_SNAPSHOT" -Status "OK" -OutFile (Join-Path $root "data\derived\macro-snapshot.json")
      Write-Log "OK  DERIVED:MACRO_SNAPSHOT"
    } catch {
      Add-FetchResult -Label "DERIVED:MACRO_SNAPSHOT" -Status "ERR" -Detail $_.Exception.Message
      Write-Log "ERR DERIVED:MACRO_SNAPSHOT $($_.Exception.Message)"
    }
  }
  $newsDigest = Join-Path $root "build-news-digest.ps1"
  if (Test-Path $newsDigest) {
    Write-Log "DERIVED build-news-digest"
    try {
      & powershell -ExecutionPolicy Bypass -File $newsDigest | Out-Null
      Add-FetchResult -Label "DERIVED:NEWS_DIGEST" -Status "OK" -OutFile (Join-Path $root "data\derived\news-digest.json")
      Write-Log "OK  DERIVED:NEWS_DIGEST"
    } catch {
      Add-FetchResult -Label "DERIVED:NEWS_DIGEST" -Status "ERR" -Detail $_.Exception.Message
      Write-Log "ERR DERIVED:NEWS_DIGEST $($_.Exception.Message)"
    }
  }
  $breadthBuilder = Join-Path $root "build-market-breadth.ps1"
  if (Test-Path $breadthBuilder) {
    Write-Log "DERIVED build-market-breadth"
    try {
      & powershell -ExecutionPolicy Bypass -File $breadthBuilder | Out-Null
      Add-FetchResult -Label "DERIVED:MARKET_BREADTH" -Status "OK" -OutFile (Join-Path $root "data\derived\market-breadth.json")
      Write-Log "OK  DERIVED:MARKET_BREADTH"
    } catch {
      Add-FetchResult -Label "DERIVED:MARKET_BREADTH" -Status "ERR" -Detail $_.Exception.Message
      Write-Log "ERR DERIVED:MARKET_BREADTH $($_.Exception.Message)"
    }
  }
  $indexBuilder = Join-Path $root "update-report-index.ps1"
  if (Test-Path $indexBuilder) {
    Write-Log "DERIVED update-report-index"
    try {
      & powershell -ExecutionPolicy Bypass -File $indexBuilder | Out-Null
      Add-FetchResult -Label "DERIVED:REPORT_INDEX" -Status "OK" -OutFile (Join-Path $root "reports\index.json")
      Write-Log "OK  DERIVED:REPORT_INDEX"
    } catch {
      Add-FetchResult -Label "DERIVED:REPORT_INDEX" -Status "ERR" -Detail $_.Exception.Message
      Write-Log "ERR DERIVED:REPORT_INDEX $($_.Exception.Message)"
    }
  }
}

$fetchEndedAt = Get-Date
$summary = [pscustomobject]@{
  started_at = $fetchStartedAt.ToString("yyyy-MM-dd HH:mm:ss")
  ended_at = $fetchEndedAt.ToString("yyyy-MM-dd HH:mm:ss")
  range = "$StartDate..$EndDate"
  providers = ($Providers -join ",")
  counts = [pscustomobject]@{
    ok = @($fetchResults | Where-Object { $_.status -eq "OK" }).Count
    err = @($fetchResults | Where-Object { $_.status -eq "ERR" }).Count
    skip = @($fetchResults | Where-Object { $_.status -eq "SKIP" }).Count
  }
  results = $fetchResults
}
$summaryPath = Join-Path $logDir "latest-fetch-summary.json"
$summary | ConvertTo-Json -Depth 10 | Set-Content -Path $summaryPath -Encoding UTF8
Write-Log "SUMMARY $summaryPath ok=$($summary.counts.ok) err=$($summary.counts.err) skip=$($summary.counts.skip)"

if (-not $SkipDerived) {
  $qualityBuilder = Join-Path $root "build-data-quality-report.ps1"
  if (Test-Path $qualityBuilder) {
    Write-Log "DERIVED build-data-quality-report"
    try {
      & powershell -ExecutionPolicy Bypass -File $qualityBuilder | Out-Null
      Add-FetchResult -Label "DERIVED:DATA_QUALITY" -Status "OK" -OutFile (Join-Path $root "data\derived\data-quality.json")
      Write-Log "OK  DERIVED:DATA_QUALITY"
    } catch {
      Add-FetchResult -Label "DERIVED:DATA_QUALITY" -Status "ERR" -Detail $_.Exception.Message
      Write-Log "ERR DERIVED:DATA_QUALITY $($_.Exception.Message)"
    }
    $fetchEndedAt = Get-Date
    $summary = [pscustomobject]@{
      started_at = $fetchStartedAt.ToString("yyyy-MM-dd HH:mm:ss")
      ended_at = $fetchEndedAt.ToString("yyyy-MM-dd HH:mm:ss")
      range = "$StartDate..$EndDate"
      providers = ($Providers -join ",")
      counts = [pscustomobject]@{
        ok = @($fetchResults | Where-Object { $_.status -eq "OK" }).Count
        err = @($fetchResults | Where-Object { $_.status -eq "ERR" }).Count
        skip = @($fetchResults | Where-Object { $_.status -eq "SKIP" }).Count
      }
      results = $fetchResults
    }
    $summary | ConvertTo-Json -Depth 10 | Set-Content -Path $summaryPath -Encoding UTF8
    Write-Log "SUMMARY $summaryPath ok=$($summary.counts.ok) err=$($summary.counts.err) skip=$($summary.counts.skip)"
  }
  $briefingBuilder = Join-Path $root "build-report-briefing.ps1"
  if (Test-Path $briefingBuilder) {
    Write-Log "DERIVED build-report-briefing"
    try {
      & powershell -ExecutionPolicy Bypass -File $briefingBuilder | Out-Null
      Add-FetchResult -Label "DERIVED:REPORT_BRIEFING" -Status "OK" -OutFile (Join-Path $root "data\derived\report-briefing.json")
      Write-Log "OK  DERIVED:REPORT_BRIEFING"
    } catch {
      Add-FetchResult -Label "DERIVED:REPORT_BRIEFING" -Status "ERR" -Detail $_.Exception.Message
      Write-Log "ERR DERIVED:REPORT_BRIEFING $($_.Exception.Message)"
    }
    $fetchEndedAt = Get-Date
    $summary = [pscustomobject]@{
      started_at = $fetchStartedAt.ToString("yyyy-MM-dd HH:mm:ss")
      ended_at = $fetchEndedAt.ToString("yyyy-MM-dd HH:mm:ss")
      range = "$StartDate..$EndDate"
      providers = ($Providers -join ",")
      counts = [pscustomobject]@{
        ok = @($fetchResults | Where-Object { $_.status -eq "OK" }).Count
        err = @($fetchResults | Where-Object { $_.status -eq "ERR" }).Count
        skip = @($fetchResults | Where-Object { $_.status -eq "SKIP" }).Count
      }
      results = $fetchResults
    }
    $summary | ConvertTo-Json -Depth 10 | Set-Content -Path $summaryPath -Encoding UTF8
    Write-Log "SUMMARY $summaryPath ok=$($summary.counts.ok) err=$($summary.counts.err) skip=$($summary.counts.skip)"
  }
}
Write-Log "DONE providers=$($Providers -join ',') range=$StartDate..$EndDate"
