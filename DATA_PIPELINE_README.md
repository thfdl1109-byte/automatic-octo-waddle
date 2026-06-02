# Finance Report Automation

이 폴더는 매일 글로벌 금융 리포트를 생성하고 GitHub Pages에 게시하기 위한 로컬 자동화 작업공간입니다.

## 운영 파일

- `fetch-market-data.ps1`: API/웹 원천 데이터를 수집하고 파생 산출물을 생성합니다.
- `select-interesting-stocks.ps1`: 미국 관심/변동성 상위 종목을 선별합니다.
- `build-macro-snapshot.ps1`: 금리, 유가, 달러, 금, 비트코인 등 매크로 요약을 생성합니다.
- `build-news-digest.ps1`: 뉴스 원천을 점수화하고 핵심 헤드라인을 정리합니다.
- `build-market-breadth.ps1`: ETF 상대강도 기반 시장 폭을 계산합니다.
- `build-data-quality-report.ps1`: 데이터 품질 점수와 경고를 생성합니다.
- `build-report-briefing.ps1`: 리포트 작성 전 읽는 핵심 브리핑을 생성합니다.
- `update-report-index.ps1`: 날짜별 리포트 목록과 최신 리포트 복사본을 갱신합니다.
- `build-pages-site.ps1`: `daily-reports`의 Markdown 리포트를 GitHub Pages용 HTML로 변환합니다.
- `publish-report-to-github.ps1`: 인덱스/Pages 파일을 갱신하고 변경사항을 커밋 후 `origin/main`으로 push합니다.
- `data/sources.json`: 수집 대상 지수, ETF, 종목, API 원천 목록입니다.
- `.env.example`: 실제 API 키 없이 구조만 보여주는 예시 파일입니다.

## 생성되는 파일

아래 파일은 자동 생성 산출물입니다. 로컬 자동화에는 필요하지만 GitHub 버전관리 대상에서는 제외합니다.

- `data/raw/`
- `data/derived/`
- `data/logs/`
- `reports/`

GitHub Pages에 공개되는 파일은 `docs/`에 생성됩니다.

## 리포트 저장 위치

운영 리포트 Markdown은 아래 폴더에 저장합니다.

```text
daily-reports/
```

파일명은 다음 형식을 사용합니다.

```text
YYYY-MM-DD-daily-global-finance-report.md
```

현재 운영 시작 기준은 `2026-06-01`입니다. 과거 1월~5월 학습용 리포트는 삭제했고, 필요한 경우 Git 커밋 기록에서만 복구합니다.

## 수동 실행

데이터 수집과 파생 산출물 생성:

```powershell
powershell -ExecutionPolicy Bypass -File .\fetch-market-data.ps1
```

리포트 인덱스, GitHub Pages HTML, 커밋/push:

```powershell
powershell -ExecutionPolicy Bypass -File .\publish-report-to-github.ps1
```

## GitHub Pages

Pages 소스는 다음 설정을 사용합니다.

```text
Branch: main
Folder: /docs
```

웹 주소:

```text
https://thfdl1109-byte.github.io/automatic-octo-waddle/
```

## API 키

실제 키는 `.env`에만 저장합니다. `.env`는 GitHub에 올라가지 않습니다.

```powershell
Copy-Item .env.example .env
notepad .env
```

## 주의

- 무료 API는 호출 제한이 있으므로 `fetch-market-data.ps1`는 지연 시간을 둡니다.
- Polygon grouped daily는 무료 플랜 제한 때문에 기본 비활성화합니다.
- Twelve Data는 호출 제한이 잦아 기본 자동 수집에서는 제외하고, 필요할 때만 수동 provider로 사용합니다.
- 한국투자증권 API는 키가 준비된 뒤 별도 provider로 활성화합니다.
