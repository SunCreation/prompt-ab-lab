# 프롬프트 A/B 테스트 랩 설치 스크립트 — Windows PowerShell
# 실행: PowerShell 에서  irm https://raw.githubusercontent.com/SunCreation/prompt-ab-lab/main/install.ps1 | iex
$ErrorActionPreference = "Stop"
$Repo    = if ($env:AB_LAB_REPO) { $env:AB_LAB_REPO } else { "SunCreation/prompt-ab-lab" }
$Dest    = Join-Path $HOME ".prompt-ab-lab"
$BinDir  = Join-Path $HOME ".local\bin"

function Say($m)  { Write-Host "[설치] " $m -ForegroundColor Cyan }
function Fail($m) { Write-Host "[실패] " $m -ForegroundColor Red; exit 1 }

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail "git이 없습니다. https://git-scm.com/downloads 에서 설치한 뒤 다시 실행해 주세요." }
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Fail "Node.js 가 없습니다. 바이브 코딩 모듈 1강의 개발 환경 설치(nvm-windows + Node.js LTS)를 먼저 마친 뒤 다시 실행해 주세요."
}
Say ("Node.js " + (node --version) + " 사용")

if (Test-Path (Join-Path $Dest ".git")) {
  Say "이전 설치를 최신으로 갱신합니다."
  git -C $Dest pull --ff-only 2>$null
  if ($LASTEXITCODE -ne 0) { Remove-Item -Recurse -Force $Dest }
}
if (-not (Test-Path (Join-Path $Dest ".git"))) {
  Say "도구를 내려받습니다."
  if (Test-Path $Dest) { Remove-Item -Recurse -Force $Dest }
  git clone --depth 1 "https://github.com/$Repo.git" $Dest 2>$null
  if ($LASTEXITCODE -ne 0) { Fail "내려받기에 실패했습니다. 인터넷 연결을 확인해 주세요." }
}
Say "필요한 패키지를 설치합니다. (잠시 걸립니다)"
Push-Location $Dest
npm install --no-audit --no-fund 2>$null
if ($LASTEXITCODE -ne 0) { Pop-Location; Fail "패키지 설치에 실패했습니다. '$Dest' 에서 npm install 을 다시 실행해 보세요." }
Pop-Location

New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
$wrapper = @"
@echo off
node "$Dest\ab_tester.mjs" --open %*
"@
Set-Content -Path (Join-Path $BinDir "ab-lab.cmd") -Value $wrapper -Encoding ASCII
Say "한 줄 명령 등록: $BinDir\ab-lab.cmd"

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$BinDir*") {
  [Environment]::SetEnvironmentVariable("Path", "$BinDir;$userPath", "User")
  Say "PATH 에 $BinDir 을 추가했습니다. (새 터미널부터 적용)"
}
if (Get-Command claude -ErrorAction SilentlyContinue) {
  $auth = claude auth status 2>$null | Out-String
  if ($auth -match '"loggedIn"\s*:\s*true') { Say "Claude Code 로그인 확인됨" }
  else { Write-Host "[확인] Claude Code 에 로그인되어 있지 않습니다. Claude 모드를 쓰려면 'claude' 를 실행해 로그인하세요. (vLLM 모드는 로그인 없이 됩니다)" -ForegroundColor Yellow }
} else {
  Write-Host "[확인] Claude Code CLI 를 찾지 못했습니다. Claude 모드만 영향이 있습니다." -ForegroundColor Yellow
}
Write-Host ""
Say "설치가 끝났습니다."
Write-Host "    새 PowerShell 창을 열고  ab-lab  을 입력하면 브라우저에 화면이 뜹니다."
