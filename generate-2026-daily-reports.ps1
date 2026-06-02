$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$outDir = Join-Path $root "daily-reports-2026-01-01_2026-06-02"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$start = [datetime]"2026-01-01"
$end = [datetime]"2026-06-02"

$holidayMap = @{
  "2026-01-01" = "미국 New Year's Day 휴장"
  "2026-01-19" = "미국 Martin Luther King Jr. Day 휴장"
  "2026-02-16" = "미국 Presidents' Day 휴장"
  "2026-04-03" = "미국 Good Friday 휴장"
  "2026-05-25" = "미국 Memorial Day 휴장"
}

$eventMap = @{
  "2026-01-13" = @{
    Title = "물가 지표가 대체로 예상에 부합하며 S&P 500과 Dow가 기록권 부근에서 출발한 날"
    Market = "Reuters 보도 기준, 1월 13일 미국 증시는 대체로 예상에 부합한 인플레이션 지표와 혼재된 실적을 소화했다. S&P 500과 Dow는 기록권 부근에서 움직였고, Nasdaq도 기술주 기대를 유지했다."
    Tone = "위험선호 유지, 금리 인하 기대 점검"
    Watch = "CPI/PPI 이후 금리 기대, 대형 은행 실적, AI 대형주 수급"
  }
  "2026-01-20" = @{
    Title = "관세 위협과 정책 불확실성으로 변동성이 커진 날"
    Market = "1월 20일은 정책·관세 리스크가 시장 심리를 흔든 날로 분류한다. 이 날은 정확한 지수 수치를 별도 확인해야 하지만, 자동화 리포트에서는 '정책 헤드라인이 기술주 밸류에이션보다 우위에 선 날'로 태깅한다."
    Tone = "정책 리스크 확대, 변동성 상승"
    Watch = "관세 관련 후속 발언, 달러/금리 반응, 반도체 수출 규제"
  }
  "2026-01-29" = @{
    Title = "빅테크 AI 투자비 부담이 S&P 500과 Nasdaq을 압박한 날"
    Market = "Reuters 보도 기준, 1월 29일 S&P 500과 Nasdaq은 빅테크 실적 발표 이후 AI 지출이 실제 이익으로 전환될 수 있는지에 대한 의구심으로 약세를 보였다. Dow는 소폭 상승으로 마감했다."
    Tone = "AI CAPEX 검증, 대형 기술주 부담"
    Watch = "클라우드 CAPEX, 마진 가이던스, 반도체 주문 전망"
  }
  "2026-03-02" = @{
    Title = "이란 전쟁과 유가 급등이 글로벌 위험선호를 흔든 날"
    Market = "중동 리스크와 에너지 가격 상승이 물가 우려를 키우며 주식시장에 부담을 준 날로 분류한다. 정확한 종가 수치는 확인 필요다."
    Tone = "유가 충격, 인플레이션 재점화"
    Watch = "Brent/WTI, 10년물 금리, 방산/에너지주 상대강도"
  }
  "2026-03-13" = @{
    Title = "이란 전쟁 여파와 유가 상승으로 Wall Street 손실이 깊어진 날"
    Market = "AP 보도 기준, 3월 13일 미국 증시는 이란 전쟁 여파와 유가 상승이 인플레이션 압력을 높이며 하락했다. S&P 500은 약세였고, 시장은 전쟁 장기화와 연준의 물가 대응을 다시 가격에 반영했다."
    Tone = "지정학 리스크, 유가발 물가 우려"
    Watch = "유가 추세, 기대인플레이션, Fed 발언"
  }
  "2026-03-20" = @{
    Title = "이란 전쟁 장기화와 에너지 가격 상승이 핵심 변수로 떠오른 날"
    Market = "Reuters 보도 기준, 3월 20일 전후 시장은 이란 전쟁 장기화와 40% 이상 오른 유가를 주시했다. 금리 인하 기대는 약화됐고, S&P 500은 연속 주간 약세 흐름에 있었다."
    Tone = "전쟁 장기화, 금리 인하 기대 후퇴"
    Watch = "FedWatch 금리 기대, 원유 공급, 성장주 밸류에이션"
  }
  "2026-03-26" = @{
    Title = "Nasdaq이 고점 대비 10% 안팎으로 밀리며 조정 우려가 커진 날"
    Market = "AP 보도 기준, 3월 26일 미국 증시는 이란 전쟁 종식 기대가 약해지고 유가가 오르며 크게 하락했다. S&P 500은 1.7% 하락했고 Nasdaq은 기존 고점 대비 약 10% 아래로 밀렸다."
    Tone = "기술주 조정, 리스크오프"
    Watch = "Nasdaq 회복 여부, 유가 재상승, VIX"
  }
  "2026-03-31" = @{
    Title = "중동 긴장 완화 기대에도 월간 손실 부담이 남은 날"
    Market = "Reuters 보도 기준, 3월 31일 미국 주식선물은 중동 긴장 완화 기대에 반등했지만, S&P 500과 Dow는 큰 월간 하락을 앞둔 상태였다. 전쟁과 유가가 3월 전체를 지배했다."
    Tone = "월말 반등 시도, 추세 복구 확인 필요"
    Watch = "4월 실적 시즌, 유가 안정, 지수 50일선 회복"
  }
  "2026-04-15" = @{
    Title = "Nasdaq과 S&P 500이 기술주 회복과 중동 낙관론으로 기록을 세운 날"
    Market = "Reuters 보도 기준, 4월 15일 Nasdaq은 10월 이후 처음으로 기록권을 회복했고, S&P 500도 사상 최고권에 진입했다. 시장은 중동 리스크 완화와 기술주 실적 기대를 동시에 반영했다."
    Tone = "위험선호 회복, AI 기술주 재평가"
    Watch = "빅테크 실적, AI 투자 수익성, 중동 휴전 뉴스"
  }
  "2026-04-16" = @{
    Title = "S&P 500과 Nasdaq이 2거래일 연속 기록권을 이어간 날"
    Market = "Reuters 보도 기준, 4월 16일 S&P 500과 Nasdaq은 중동 긴장 완화 기대와 1분기 실적 시즌 초반 기대 속에 소폭 상승하며 기록권 흐름을 유지했다."
    Tone = "실적장세 진입, 낙관론 유지"
    Watch = "기업 이익 성장률, 소프트웨어주, 반도체주"
  }
  "2026-05-06" = @{
    Title = "AMD 실적과 AI 낙관론으로 S&P 500과 Nasdaq이 기록을 세운 날"
    Market = "Reuters 보도 기준, 5월 6일 S&P 500과 Nasdaq은 AMD 실적과 AI 관련주 강세, 중동 평화 기대에 힘입어 기록적 마감 흐름을 보였다."
    Tone = "AI 반도체 재가속, 위험선호 강화"
    Watch = "AMD/Nvidia/Micron, 반도체 지수, 고용지표"
  }
  "2026-05-15" = @{
    Title = "유가와 장기금리 상승이 AI 랠리를 흔든 날"
    Market = "AP 보도 기준, S&P 500은 7,408.50으로 1.2% 하락, Dow는 49,526.17로 1.1% 하락, Nasdaq은 26,225.14로 1.5% 하락, Russell 2000은 2,793.30으로 2.4% 하락했다. 유가 상승과 장기금리 부담이 AI 주도주 차익실현을 유발했다."
    Tone = "리스크오프, AI 고밸류 부담"
    Watch = "유가, 30년물 금리, Nvidia 등 AI 대표주"
  }
  "2026-05-18" = @{
    Title = "전쟁과 유가 뉴스에 시장이 흔들린 날"
    Market = "AP 보도 기준, S&P 500은 7,403.05로 0.1% 하락, Dow는 49,686.12로 0.3% 상승, Nasdaq은 26,090.73으로 0.5% 하락했다. 유가와 이란 전쟁 뉴스가 시장 방향성을 좌우했다."
    Tone = "혼조, 유가 민감"
    Watch = "유가 장중 방향, 기술주 반등 여부"
  }
  "2026-05-19" = @{
    Title = "기록권 이후 3거래일 연속 조정이 이어진 날"
    Market = "AP 보도 기준, S&P 500은 7,353.61로 0.7% 하락, Dow는 49,363.88로 0.6% 하락, Nasdaq은 25,870.71로 0.8% 하락했다. 기술주와 중소형주가 함께 압박받았다."
    Tone = "조정 연장, 금리 부담"
    Watch = "시장 폭, 10년물 금리, 성장주 수급"
  }
  "2026-05-20" = @{
    Title = "유가와 금리 완화로 미국 증시가 반등한 날"
    Market = "AP 보도 기준, S&P 500은 7,432.97로 1.1% 상승, Dow는 50,009.35로 1.3% 상승, Nasdaq은 26,270.36으로 1.5% 상승했다. Brent 유가 하락과 10년물 금리 안정이 반등의 핵심이었다."
    Tone = "리스크온 회복, 유가 안정"
    Watch = "Brent, 10년물 4.60%선, Russell 2000"
  }
  "2026-05-21" = @{
    Title = "유가 하락 반전이 매수 심리를 지지한 날"
    Market = "AP 보도 기준, S&P 500은 7,445.72로 0.2% 상승, Dow는 50,285.66으로 0.6% 상승, Nasdaq은 26,293.10으로 0.1% 상승했다. 장중 약세를 되돌린 점이 중요했다."
    Tone = "완만한 위험선호, 매수 대기 확인"
    Watch = "유가 안정 지속, 장중 저점 방어"
  }
  "2026-05-22" = @{
    Title = "실적이 소비심리 악화를 누르고 8주 연속 상승을 만든 날"
    Market = "AP 보도 기준, S&P 500은 7,473.47로 0.4% 상승, Dow는 50,579.70으로 0.6% 상승, Nasdaq은 26,343.97로 0.2% 상승했다. 미국 증시는 8주 연속 상승했다."
    Tone = "실적 지지, 소비심리 괴리"
    Watch = "미시간대 소비심리, 유가, 기업 실적"
  }
  "2026-05-26" = @{
    Title = "중동 협상 기대와 AI 낙관론으로 Nasdaq이 최고치를 경신한 날"
    Market = "AP 보도 기준, S&P 500은 7,519.12로 0.6% 상승, Dow는 50,461.68로 0.2% 하락, Nasdaq은 26,656.18로 1.2% 상승했다. 기술주 중심의 위험선호가 강했다."
    Tone = "기술주 주도, Dow 부진"
    Watch = "Nasdaq 신고가 지속성, 반도체주, 중동 뉴스"
  }
  "2026-05-27" = @{
    Title = "미국 AI 랠리가 한국 메모리 반도체로 강하게 전이된 날"
    Market = "AP 보도 기준, S&P 500은 0.6%, Dow는 0.4%, Nasdaq은 0.1% 상승했다. Korea JoongAng Daily 기준 KOSPI는 8,228.70으로 사상 최고 마감했고 SK하이닉스가 9.31% 급등했다."
    Tone = "AI 메모리 랠리, 한국 베타 확대"
    Watch = "삼성전자, SK하이닉스, HBM 수요"
  }
  "2026-05-28" = @{
    Title = "휴전 연장 기대와 기업 실적 호조로 미국 지수가 기록을 이어간 날"
    Market = "AP 보도 기준, S&P 500은 7,563.63으로 0.6% 상승, Dow는 50,668.97로 소폭 상승, Nasdaq은 26,917.47로 0.9% 상승했다. Treasury yield도 완화됐다."
    Tone = "기록권 유지, 실적장세"
    Watch = "Dell 실적, Snowflake 등 소프트웨어, 휴전 헤드라인"
  }
  "2026-05-29" = @{
    Title = "S&P 500 9주 연속 상승과 Dell AI 서버 랠리가 부각된 날"
    Market = "AP 보도 기준, S&P 500은 7,580.06으로 0.2% 상승, Dow는 51,032.46으로 0.7% 상승, Nasdaq은 26,972.62로 0.2% 상승했다. Dell은 AI 서버 수요로 급등했고 KOSPI는 8,476.15로 마감했다."
    Tone = "AI 인프라 확장, 랠리 지속"
    Watch = "Dell, Nvidia, KOSPI 시장 폭, Russell 2000"
  }
  "2026-06-02" = @{
    Title = "AI PC와 한국 CPI, 유가·금리 부담을 함께 본 날"
    Market = "기존 2026-06-02 리포트 기준, AI 관련 기술주 모멘텀이 유지되는 가운데 유가와 금리 부담, 한국 CPI와 KOSPI 사상 최고권 움직임을 함께 점검해야 하는 날이다."
    Tone = "AI 모멘텀 유지, 과열 점검"
    Watch = "Nvidia Computex, 한국 CPI, 유가, Russell 2000"
  }
}

function Get-Regime($date) {
  if ($date -le [datetime]"2026-01-31") {
    return @{
      Name = "1월: 금리 인하 기대와 AI 실적 검증"
      Market = "1월 시장은 인플레이션 지표와 4분기 실적, 빅테크 AI 투자비를 동시에 확인하는 구간이었다. 월중에는 기록권 접근이 있었지만, 정책·관세 리스크와 AI CAPEX 부담이 변동성을 키웠다."
      Watch = "CPI/PPI, 은행 실적, 빅테크 CAPEX, 관세/정책 뉴스"
    }
  }
  if ($date -le [datetime]"2026-02-28") {
    return @{
      Name = "2월: AI 사이클 유지와 금리 기대 정체"
      Market = "2월은 AI 인프라 기대가 유지됐지만, 금리 인하 기대는 크게 개선되지 않은 구간이다. 시장은 대형 기술주 실적의 질과 중소형주 확산 여부를 확인했다."
      Watch = "연준 발언, AI 소프트웨어 실적, 반도체 주문, 시장 폭"
    }
  }
  if ($date -le [datetime]"2026-03-31") {
    return @{
      Name = "3월: 이란 전쟁, 유가 충격, 기술주 조정"
      Market = "3월 시장은 이란 전쟁과 에너지 가격 급등이 지배했다. 유가 상승은 물가와 금리 기대를 자극했고, Nasdaq과 고밸류 기술주는 조정 압력을 받았다."
      Watch = "Brent/WTI, 기대인플레이션, 10년물 금리, VIX, 중동 헤드라인"
    }
  }
  if ($date -le [datetime]"2026-04-30") {
    return @{
      Name = "4월: 중동 완화 기대와 실적 시즌 반등"
      Market = "4월은 3월 조정 이후 중동 긴장 완화 기대와 1분기 실적 시즌이 맞물리며 기술주 위험선호가 회복된 구간이다. S&P 500과 Nasdaq은 기록권으로 복귀했다."
      Watch = "빅테크 실적, AI 투자 수익성, 중동 휴전, 유가 안정"
    }
  }
  if ($date -le [datetime]"2026-05-31") {
    return @{
      Name = "5월: AI 랠리 재가속과 유가·금리 민감도"
      Market = "5월은 AI 반도체와 서버 인프라 수요가 강하게 확인된 반면, 유가와 장기금리가 오르면 고밸류 기술주가 즉시 흔들리는 구간이었다. 한국 KOSPI는 AI 메모리 사이클의 고베타 지표로 움직였다."
      Watch = "Nvidia/AMD/Micron, Dell, KOSPI, 유가, 장기금리, 시장 폭"
    }
  }
  return @{
    Name = "6월 초: AI PC와 월말 랠리 이후 과열 점검"
    Market = "6월 초는 5월 말 강한 랠리 이후 AI PC, 반도체 수출 규제, 한국 물가와 KOSPI 과열을 동시에 점검하는 구간이다."
    Watch = "Nvidia Computex, AI PC, 한국 CPI, 반도체 수출 규제"
  }
}

function Is-Weekend($date) {
  return ($date.DayOfWeek -eq [System.DayOfWeek]::Saturday -or $date.DayOfWeek -eq [System.DayOfWeek]::Sunday)
}

$indexRows = @()

for ($d = $start; $d -le $end; $d = $d.AddDays(1)) {
  $key = $d.ToString("yyyy-MM-dd")
  $file = Join-Path $outDir "$key-daily-global-finance-report.md"
  $regime = Get-Regime $d
  $isWeekend = Is-Weekend $d
  $holiday = $holidayMap[$key]
  $event = $eventMap[$key]

  if ($event) {
    $title = $event.Title
    $market = $event.Market
    $tone = $event.Tone
    $watch = $event.Watch
    $dataStatus = "일부 핵심 수치 확인됨. 나머지 글로벌 지수와 세부 종목 수치는 추가 확인 필요."
  } elseif ($isWeekend -or $holiday) {
    $title = if ($holiday) { $holiday } else { "주말 휴장 및 다음 거래일 준비" }
    $market = "미국 정규장은 휴장 또는 주말이다. 당일 리포트는 거래 가격보다 전일 마감, 지정학 뉴스, 유가와 금리 선물, 다음 거래일 갭 리스크를 점검하는 용도로 작성한다."
    $tone = "휴장 점검"
    $watch = $regime.Watch
    $dataStatus = "휴장/주말. 신규 미국 정규장 종가 없음."
  } else {
    $title = $regime.Name
    $market = $regime.Market
    $tone = "정규 거래일 요약. 정밀 지수 종가 확인 필요."
    $watch = $regime.Watch
    $dataStatus = "FRED/Yahoo 직접 다운로드가 현재 환경에서 실패하여 일별 종가 자동 채움 보류. 숫자는 추후 원천 데이터로 보강 필요."
  }

  $content = @"
# $key 데일리 글로벌 금융 리포트

작성 기준: $key KST  
학습 태그: 자동화 리포트, 글로벌 증시, AI, 유가, 금리  
데이터 상태: $dataStatus

## 1) 오늘의 한 줄 결론

$title

## 2) 시장 요약

$market

## 3) 미국 주요 지수

지수 | 등락 | 마감
--- | ---: | ---:
S&P 500 | 확인 필요 | 확인 필요
Nasdaq Composite | 확인 필요 | 확인 필요
Dow Jones Industrial Average | 확인 필요 | 확인 필요
Russell 2000 | 확인 필요 | 확인 필요
VIX | 확인 필요 | 확인 필요

## 4) 글로벌 참고 지수

지수 | 지역 | 등락 | 마감
--- | --- | ---: | ---:
KOSPI | 한국 | 확인 필요 | 확인 필요
Nikkei 225 | 일본 | 확인 필요 | 확인 필요
Shanghai Composite | 중국 | 확인 필요 | 확인 필요
Hang Seng | 홍콩 | 확인 필요 | 확인 필요
STOXX Europe 600 | 유럽 | 확인 필요 | 확인 필요

## 5) 해석 프레임

- 시장 톤: $tone
- 기간 국면: $($regime.Name)
- 핵심 변수: AI 투자 사이클, 유가, 장기금리, 지정학 리스크, 시장 폭
- 자동화 판단: 지수 상승 여부만 보지 말고 Russell 2000, 시장 폭, 금리와 유가를 함께 비교한다.

## 6) 주요 종목/섹터

- AI 반도체: Nvidia, AMD, Micron, 삼성전자, SK하이닉스의 방향성을 우선 점검한다.
- AI 인프라: 서버, 스토리지, 네트워크, 전력 인프라 관련 실적과 수주를 확인한다.
- 에너지: 이란 전쟁과 중동 긴장이 유가를 통해 물가 기대를 자극하는지 본다.
- 소비/운송: 유가와 금리 상승이 마진과 수요에 주는 부담을 점검한다.

## 7) 리스크 체크

- AI 주도주 상승이 지수 전체로 확산됐는가?
- Russell 2000이 S&P 500과 같은 방향으로 움직였는가?
- 유가가 물가 기대를 다시 자극했는가?
- 10년물 또는 30년물 금리가 성장주 밸류에이션을 압박했는가?
- 한국 KOSPI의 반도체 쏠림이 완화됐는가?
- 지정학 헤드라인이 다음 거래일 갭 리스크를 만들 수 있는가?

## 8) 다음 거래일 관찰 포인트

$watch

## 9) 학습 메모

이 파일은 자동화가 매일 같은 구조로 시장을 읽도록 만드는 학습용 샘플이다. 정밀 지수 데이터가 없는 날은 수치를 임의 생성하지 않고 `확인 필요`로 남긴다. 이후 원천 데이터가 연결되면 `미국 주요 지수`와 `글로벌 참고 지수` 표만 교체하면 된다.

"@

  Set-Content -Path $file -Value $content -Encoding utf8
  $indexRows += "| $key | $title | $dataStatus | [파일](daily-reports-2026-01-01_2026-06-02/$key-daily-global-finance-report.md) |"
}

$index = @"
# 2026-01-01~2026-06-02 데일리 금융 리포트 학습 인덱스

작성 기준: 2026-06-02 KST  
범위: 2026-01-01부터 2026-06-02까지  
파일 수: $($indexRows.Count)개

## 사용법

- `daily-reports-2026-01-01_2026-06-02/` 폴더에 날짜별 데일리 리포트를 저장했다.
- 확인된 주요 이벤트 일자는 본문에 구체 수치와 출처 기반 해석을 넣었다.
- 원천 데이터 자동 다운로드가 막힌 날은 숫자를 임의 작성하지 않고 `확인 필요`로 표기했다.
- 자동화 학습에는 구조, 체크리스트, 시장 국면 태그, 해석 문장을 우선 사용한다.

## 기간별 큰 흐름

1. 1월: 금리 인하 기대, 물가 지표, 빅테크 AI 투자비 검증
2. 2월: AI 사이클 유지, 금리 기대 정체, 시장 폭 점검
3. 3월: 이란 전쟁과 유가 급등, 기술주 조정
4. 4월: 중동 완화 기대와 실적 시즌 반등, S&P 500/Nasdaq 기록권 복귀
5. 5월: AI 반도체·서버 랠리 재가속, KOSPI 고베타 상승, 유가·금리 민감도 확대
6. 6월 초: AI PC, 반도체 규제, 한국 CPI와 과열 점검

## 파일 목록

날짜 | 핵심 제목 | 데이터 상태 | 링크
--- | --- | --- | ---
$($indexRows -join "`n")

## 출처 메모

- FRED S&P 500 페이지: https://fred.stlouisfed.org/series/SP500
- Reuters/Investing.com 2026-01-13: https://www.investing.com/news/stock-market-news/sp-500-dow-open-near-record-highs-after-mixed-earnings-inflation-data-4444986
- Reuters/Investing.com 2026-01-29: https://www.investing.com/news/stock-market-news/us-stock-index-futures-edge-up-as-markets-digest-big-tech-earnings-4472320
- Reuters/Investing.com 2026-03-20: https://www.investing.com/news/economy-news/persistent-iran-war-energy-price-surge-set-to-loom-over-stocks-4573502
- AP 2026-03-13: https://apnews.com/article/fbaf44c8ea236a7e966bfcddef305ac3
- AP 2026-03-26: https://apnews.com/article/8118f58d75859b9fc74ab133fa9e8c3e
- Reuters/Investing.com 2026-03-31: https://www.investing.com/news/stock-market-news/wall-st-futures-rise-on-iran-war-deescalation-hopes-indexes-set-for-monthly-drops-4589611
- Reuters/Investing.com 2026-04-15: https://www.investing.com/news/stock-market-news/nasdaq-sets-record-highs-as-investors-return-to-tech-stocks-4616614
- Reuters/Investing.com 2026-04-16: https://www.investing.com/news/stock-market-news/wall-st-futures-edge-higher-on-mideast-diplomacy-hopes-strong-earnings-4617346
- Reuters/Investing.com 2026-05-06: https://www.investing.com/news/stock-market-news/us-stock-index-futures-rise-on-middle-east-peace-hopes-ai-optimism-4662015
- AP 2026-05-15: https://apnews.com/article/4a572b9feeed6af2986be7e7a22c651a
- AP 2026-05-18: https://apnews.com/article/ea02a38eb60bd7d29444b845a6467472
- AP 2026-05-19: https://apnews.com/article/e47b04bcb52eda2411691e062ce60a72
- AP 2026-05-20: https://apnews.com/article/0a2d8550772c20a7e44c982145a22278
- AP 2026-05-21: https://apnews.com/article/0709cb2203785c5af55d2786af1f9e12
- AP 2026-05-22: https://apnews.com/article/2129e0beebf47c8a223dbafa00d8a7ed
- AP 2026-05-26: https://apnews.com/article/b2fb9ef30834ed73768f2afd65ec7de0
- AP 2026-05-27: https://apnews.com/article/6b22ac4e7e8ab54dde3d3499e6643f28
- AP 2026-05-28: https://apnews.com/article/69f6b6c8b2bf904c69087af415812d4c
- AP 2026-05-29: https://apnews.com/article/82c0b13a9b0bec79cc907cc122cac328
- Korea JoongAng Daily 2026-05-27: https://koreajoongangdaily.joins.com/news/2026-05-27/business/finance/Kospi-closes-at-another-new-peak-thanks-to-extended-chip-rally/2602209
- Korea JoongAng Daily 2026-05-30: https://koreajoongangdaily.joins.com/news/2026-05-30/business/finance/Kospi-rises-nearly-30-in-May-but-all-sectors-save-for-AI-lag-behind-gains/2604735

"@

Set-Content -Path (Join-Path $root "2026-01-01_2026-06-02-daily-report-learning-index.md") -Value $index -Encoding utf8

Write-Host "Generated $($indexRows.Count) daily report files in $outDir"

