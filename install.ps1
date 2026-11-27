# 프롬프트 A/B 테스트 랩 설치 스크립트 — Windows PowerShell 5.1 / PowerShell 7
# 실행: PowerShell 에서  irm https://raw.githubusercontent.com/SunCreation/prompt-ab-lab/main/install.ps1 | iex
#
# irm | iex 는 사용자의 셸 안에서 그대로 실행된다. 그래서 전체를 & { } 로 감싸 변수·설정이 셸에 남지 않게 하고,
# 실패해도 exit 대신 메시지만 보여 PowerShell 창이 닫히지 않게 한다.
& {
  $ErrorActionPreference = "Stop"
  $Repo   = if ($env:AB_LAB_REPO) { $env:AB_LAB_REPO } else { "SunCreation/prompt-ab-lab" }
  $Dest   = Join-Path $HOME ".prompt-ab-lab"
  $BinDir = Join-Path $HOME ".local\bin"

  function Say($m) { Write-Host "[설치] " $m -ForegroundColor Cyan }
  function Fail($m, $detail) {
    if ($detail) { Write-Host $detail -ForegroundColor DarkGray }
    throw $m
  }

  # PATH 에서 .cmd / .exe 만 찾는다. npm.ps1 같은 .ps1 은 Windows 기본 실행 정책에서 막히므로 고르지 않는다.
  function Find-App($name) {
    $c = Get-Command "$name.cmd", "$name.exe" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { $c.Source } else { $null }
  }

  # 외부 프로그램 실행. git·npm 은 정상 진행 안내("Cloning into ...", "npm warn ...")도 stderr 로 내보낸다.
  # Windows PowerShell 5.1 은 그 줄을 오류로 바꿔 "Stop" 설정에서 설치를 멈추므로, 여기서만 "Continue" 로 두고
  # 출력은 모아 두었다가 실패했을 때만 보여 준다. 성패는 종료 코드로만 판단한다.
  function Run([string]$exe, [string[]]$argv) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
      $out = (& $exe @argv 2>&1 | ForEach-Object { "$_" }) -join "`n"
      $code = $LASTEXITCODE
    } finally {
      $ErrorActionPreference = $prev
    }
    [pscustomobject]@{ Code = $code; Output = $out }
  }

  try {
    $git = Find-App git
    if (-not $git) { Fail "git이 없습니다. https://git-scm.com/downloads 에서 설치한 뒤 다시 실행해 주세요." }
    $node = Find-App node
    if (-not $node) { Fail "Node.js 가 없습니다. 바이브 코딩 모듈 1강의 개발 환경 설치(nvm-windows + Node.js LTS)를 먼저 마친 뒤 다시 실행해 주세요." }
    $npm = Find-App npm
    if (-not $npm) { Fail "npm 을 찾지 못했습니다. Node.js 를 다시 설치한 뒤 실행해 주세요." }
    Say ("Node.js " + (& $node --version) + " 사용")

    # 이전 설치가 있으면 최신으로 맞춘다. 중간에 끊긴 설치(파일 일부만 있는 폴더)도 reset 으로 되살리고,
    # 그래도 안 되면 지우고 새로 내려받는다.
    $ready = $false
    if (Test-Path (Join-Path $Dest ".git")) {
      Say "이전 설치를 최신으로 갱신합니다."
      $r = Run $git @("-C", $Dest, "fetch", "--depth", "1", "--quiet", "origin", "HEAD")
      if ($r.Code -eq 0) { $r = Run $git @("-C", $Dest, "reset", "--hard", "--quiet", "FETCH_HEAD") }
      $ready = ($r.Code -eq 0) -and (Test-Path (Join-Path $Dest "ab_tester.mjs"))
    }
    if (-not $ready) {
      Say "도구를 내려받습니다."
      if (Test-Path $Dest) { Remove-Item -Recurse -Force $Dest }
      $r = Run $git @("clone", "--depth", "1", "--quiet", "https://github.com/$Repo.git", $Dest)
      if ($r.Code -ne 0) { Fail "내려받기에 실패했습니다. 인터넷 연결을 확인해 주세요." $r.Output }
    }

    Say "필요한 패키지를 설치합니다. (잠시 걸립니다)"
    Push-Location $Dest
    try { $r = Run $npm @("install", "--no-audit", "--no-fund") } finally { Pop-Location }
    if ($r.Code -ne 0) { Fail "패키지 설치에 실패했습니다. '$Dest' 에서 npm install 을 다시 실행해 보세요." $r.Output }

    # ab-lab.cmd 에는 사용자 폴더 경로를 직접 적지 않는다. 이 파일이 있는 폴더(%~dp0, 곧 <홈>\.local\bin)를
    # 기준으로 <홈>\.prompt-ab-lab 을 찾으므로, 사용자 이름이 한글이어도 파일에는 ASCII 만 들어간다.
    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
    $wrapper = "@echo off`r`n" + 'node "%~dp0..\..\.prompt-ab-lab\ab_tester.mjs" --open %*'
    Set-Content -Path (Join-Path $BinDir "ab-lab.cmd") -Value $wrapper -Encoding ASCII
    Say "한 줄 명령 등록: $BinDir\ab-lab.cmd"

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$BinDir*") {
      [Environment]::SetEnvironmentVariable("Path", "$BinDir;$userPath", "User")
      Say "PATH 에 $BinDir 을 추가했습니다."
    }
    # 지금 이 창에서도 바로 ab-lab 을 쓸 수 있게 한다.
    if ($env:Path -notlike "*$BinDir*") { $env:Path = "$BinDir;$env:Path" }

    $claude = Find-App claude
    if ($claude) {
      $r = Run $claude @("auth", "status")
      if ($r.Output -match '"loggedIn"\s*:\s*true') { Say "Claude Code 로그인 확인됨" }
      else { Write-Host "[확인] Claude Code 에 로그인되어 있지 않습니다. Claude 모드를 쓰려면 'claude' 를 실행해 로그인하세요. (vLLM 모드는 로그인 없이 됩니다)" -ForegroundColor Yellow }
    } else {
      Write-Host "[확인] Claude Code CLI 를 찾지 못했습니다. Claude 모드만 영향이 있습니다." -ForegroundColor Yellow
    }
    Write-Host ""
    Say "설치가 끝났습니다."
    Write-Host "    ab-lab  을 입력하면 브라우저에 화면이 뜹니다."
  } catch {
    Write-Host ""
    Write-Host "[실패] " $_.Exception.Message -ForegroundColor Red
    Write-Host "    이 창의 내용을 강사에게 보여 주세요." -ForegroundColor Red
  }
}
