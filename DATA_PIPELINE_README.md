# 금융 리포트 데이터 파이프라인

이 폴더는 데일리 금융 리포트에 시장 데이터를 넣기 위한 기본 구조입니다.

## 폴더 구조

- `data/sources.json`: 무료 데이터 소스 목록
- `data/raw/fred/`: FRED CSV 저장 위치
- `data/raw/yahoo/`: Yahoo Finance JSON 저장 위치
- `data/raw/stooq/`: Stooq CSV 저장 위치
- `fetch-market-data.ps1`: 시장 데이터 다운로드 스크립트
- `select-interesting-stocks.ps1`: 미국 관심/변동성 상위 종목 선별 스크립트
- `build-macro-snapshot.ps1`: 금리, 유가, 달러, 금, 비트코인 등 매크로 요약 생성
- `build-news-digest.ps1`: 뉴스 원천 품질 점수화 및 핵심 헤드라인 요약
- `build-market-breadth.ps1`: ETF 상대강도 기반 시장 폭 요약
- `build-data-quality-report.ps1`: 데이터 품질 점수와 경고 생성
- `build-report-briefing.ps1`: 리포트 작성용 핵심 테마/뉴스/종목 브리핑 생성
- `update-report-index.ps1`: `reports/latest.md`, `reports/index.json` 생성
- `update-daily-reports.ps1`: 기존 md 리포트의 지수 표를 갱신하는 스크립트
- `.env.example`: 유료 API 키를 넣기 위한 예시 파일

## 1. 데이터 받기

PowerShell에서 아래처럼 실행합니다.

```powershell
cd "C:\Users\user\Documents\금융 리포트"
powershell -ExecutionPolicy Bypass -File .\fetch-market-data.ps1 -StartDate "2026-01-01" -EndDate "2026-06-02" -RequestTimeoutSec 20
```

받는 데이터:

- FRED: S&P 500, Nasdaq Composite, Dow, VIX, 미국 10년물 금리, WTI
- Yahoo Finance: KOSPI, Nikkei 225, Hang Seng, Shanghai Composite, STOXX Europe 600
- Stooq: S&P 500, Nasdaq, Dow 보조 데이터
- Polygon: 미국 주식 grouped daily 및 주요 관심 종목 일봉
- Finnhub: 미국 시장 뉴스, 관심 종목 quote/news
- Alpha Vantage: 상승/하락 상위 종목, 뉴스 sentiment, 주요 ETF 일봉
- Twelve Data: 미국 관심 종목, 비트코인, 금, 주요 환율 quote/time series
- NewsAPI: 시장 관련 주요 헤드라인
- 한국투자증권 Open API: 삼성전자, SK하이닉스 등 국내 대표 종목 조회

## 2. 리포트에 데이터 반영하기

```powershell
powershell -ExecutionPolicy Bypass -File .\update-daily-reports.ps1
```

이 스크립트는 `daily-reports-2026-01-01_2026-06-02` 폴더의 날짜별 md 파일에서 미국 주요 지수 표와 글로벌 참고 지수 표를 채웁니다.

## 제공처별로 나눠 받기

인터넷이 느리거나 특정 제공처가 막히면 하나씩 받을 수 있습니다.

```powershell
powershell -ExecutionPolicy Bypass -File .\fetch-market-data.ps1 -Providers stooq -StartDate "2026-01-01" -EndDate "2026-06-02" -RequestTimeoutSec 10
powershell -ExecutionPolicy Bypass -File .\fetch-market-data.ps1 -Providers yahoo -StartDate "2026-01-01" -EndDate "2026-06-02" -RequestTimeoutSec 10
powershell -ExecutionPolicy Bypass -File .\fetch-market-data.ps1 -Providers fred -StartDate "2026-01-01" -EndDate "2026-06-02" -RequestTimeoutSec 10
powershell -ExecutionPolicy Bypass -File .\fetch-market-data.ps1 -Providers polygon,finnhub,alphavantage,twelvedata,newsapi,kis -StartDate "2026-01-01" -EndDate "2026-06-02" -RequestTimeoutSec 20
```

## 3. 실시간/준실시간 확장

무료 소스는 보통 지연 데이터입니다. 실시간성이 필요하면 아래 중 하나를 추천합니다.

- 미국 주식/지수: Polygon, Finnhub, Twelve Data, Alpha Vantage, Tiingo
- 한국 시장: 한국투자증권 API, 증권사 OpenAPI, KRX 데이터, 네이버금융 비공식 수집

실제 키는 `.env.example`을 복사해 `.env` 파일을 만들고 넣으면 됩니다.

```powershell
Copy-Item .env.example .env
notepad .env
```

키는 반드시 `C:\Users\user\Documents\금융 리포트\.env`에 저장합니다. `.env.example`은 예시 파일이므로 실제 키를 넣지 않습니다.

## 4. 사용 흐름

1. `fetch-market-data.ps1` 실행
2. `data/logs/latest-fetch-summary.json`에서 성공/실패/스킵 원천 확인
3. `update-daily-reports.ps1` 실행
4. 새 데이터가 들어간 md 파일을 Codex에게 읽히기
5. `이 데이터 기준으로 리포트 다시 요약해줘`라고 요청

`fetch-market-data.ps1`는 실행 후 최신 수집 요약을 `data/logs/latest-fetch-summary.json`에 저장합니다. 자동화 리포트는 이 파일을 먼저 확인해 성공한 원천을 우선 사용하고, 실패한 API는 다른 원천으로 대체합니다.

또한 `fetch-market-data.ps1`는 기본적으로 `select-interesting-stocks.ps1`를 실행해 `data/derived/us-interesting-stocks.json`와 `data/derived/us-interesting-stocks.md`를 생성합니다. 이 파일은 미국 관심/변동성 상위 10종목 섹션의 1차 후보군입니다.

추가 파생 산출물:

- `data/derived/macro-snapshot.json`: 매크로 변수 섹션의 1차 자료
- `data/derived/news-digest.json`: 시장 해석과 이벤트 섹션의 뉴스 후보
- `data/derived/market-breadth.json`: 시장 폭, 중소형주, 섹터 상대강도 판단 자료
- `data/derived/data-quality.json`: 데이터 신뢰도 점수와 경고
- `data/derived/report-briefing.json`: 리포트 작성 전 읽는 핵심 브리핑
- `reports/latest.md`: 최신 리포트 복사본
- `reports/index.json`: 날짜별 리포트 목록과 파생 산출물 경로

자동화가 새 리포트를 작성하면 날짜별 Markdown 파일로 저장하고 `update-report-index.ps1`를 실행해 `reports/latest.md`와 `reports/index.json`을 갱신합니다. 날짜별 파일명은 `YYYY-MM-DD-daily-global-finance-report.md` 형식을 사용합니다.

## 5. 주의

- 데이터가 비어 있거나 API가 막히면 해당 값은 `N/A`로 남습니다.
- 무료 Yahoo Finance API는 공식 보장 API가 아니라 가끔 막힐 수 있습니다.
- FRED는 미국 지수·금리·유가의 안정적인 기준 소스로 쓰고, Stooq는 보조 검증용으로 쓰는 구성이 좋습니다.
- Polygon grouped daily는 무료 플랜에서 막힐 수 있어 기본 비활성화합니다. 필요하면 `.env`에 `POLYGON_ENABLE_GROUPED=true`를 넣습니다.
- 관심 종목 선별은 저가주, 워런트, 권리, 레버리지 ETF, 거래대금이 작은 후보를 줄이고, 거래대금·등락률·뉴스 수·핵심 watchlist 여부를 함께 반영합니다.
- Twelve Data는 호출 제한이 잦아 기본 자동 수집에서는 제외하고, 필요 시 `-Providers twelvedata`로 보조 확인에만 사용합니다.
