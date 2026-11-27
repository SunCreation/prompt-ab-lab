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
    $keptOld = $false
    if (-not $ready) {
      Say "도구를 내려받습니다."
      # 옆 폴더에 먼저 받고, 받기에 성공했을 때만 기존 폴더와 바꾼다.
      # 인터넷이 끊긴 채 다시 실행해도 잘 돌던 설치를 지우지 않기 위해서다.
      $tmp = "$Dest.new"
      if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
      $r = Run $git @("clone", "--depth", "1", "--quiet", "https://github.com/$Repo.git", $tmp)
      if ($r.Code -ne 0) {
        if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
        if (-not (Test-Path (Join-Path $Dest "ab_tester.mjs"))) { Fail "내려받기에 실패했습니다. 인터넷 연결을 확인해 주세요." $r.Output }
        Write-Host "[확인] 최신 버전을 받지 못해 이미 설치된 버전을 그대로 씁니다. 인터넷 연결을 확인해 주세요." -ForegroundColor Yellow
        $keptOld = $true
      } else {
        # 받아 둔 패키지는 새 폴더로 옮겨 다시 내려받지 않게 하고, 폴더 이름만 바꿔 갈아 끼운다.
        # 기존 폴더를 먼저 지우지 않으므로, 패키지 설치가 실패해도 도구가 통째로 사라지지 않는다.
        $old = "$Dest.old"
        if (Test-Path $Dest) {
          try {
            $mods = Join-Path $Dest "node_modules"
            if (Test-Path $mods) { Move-Item -LiteralPath $mods -Destination (Join-Path $tmp "node_modules") }
            if (Test-Path $old) { Remove-Item -Recurse -Force $old }
            Rename-Item -LiteralPath $Dest -NewName (Split-Path $old -Leaf)
          } catch { Fail "이전 설치 폴더를 옮기지 못했습니다. 실행 중인 ab-lab 창을 모두 닫고 다시 실행해 주세요." $_.Exception.Message }
        }
        Rename-Item -LiteralPath $tmp -NewName (Split-Path $Dest -Leaf)
        if (Test-Path $old) { Remove-Item -Recurse -Force $old -ErrorAction SilentlyContinue }
      }
    }

    if ($keptOld -and (Test-Path (Join-Path $Dest "node_modules\@anthropic-ai\claude-agent-sdk\package.json"))) {
      Say "패키지는 이미 설치된 것을 그대로 씁니다."
    } else {
      Say "필요한 패키지(약 190MB)를 설치합니다. 1~5분 걸릴 수 있으니 창을 닫지 마세요."
      Push-Location $Dest
      try { $r = Run $npm @("install", "--no-audit", "--no-fund") } finally { Pop-Location }
      if ($r.Code -ne 0) { Fail "패키지 설치에 실패했습니다. 인터넷 연결을 확인한 뒤 설치 명령을 다시 실행해 주세요." $r.Output }
    }

    # ab-lab.cmd 에는 사용자 폴더 경로를 직접 적지 않는다. 이 파일이 있는 폴더(%~dp0, 곧 <홈>\.local\bin)를
    # 기준으로 <홈>\.prompt-ab-lab 을 찾으므로, 사용자 이름이 한글이어도 파일에는 ASCII 만 들어간다.
    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
    $wrapper = "@echo off`r`n" + 'node "%~dp0..\..\.prompt-ab-lab\ab_tester.mjs" --open %*'
    Set-Content -Path (Join-Path $BinDir "ab-lab.cmd") -Value $wrapper -Encoding ASCII
    Say "한 줄 명령 등록: $BinDir\ab-lab.cmd"

    # 사용자 PATH 는 레지스트리 값을 펼치지 않은 채(%NVM_HOME% 같은 항목 그대로) 읽고 REG_EXPAND_SZ 로 다시 쓴다.
    # [Environment] 의 Get/Set 은 %VAR% 를 펼친 값을 REG_SZ 로 써 버려 nvm-windows 같은 항목이 굳는다.
    # 관리되는 학교 PC(Constrained Language Mode)에서는 이 단계가 막힐 수 있어 실패해도 설치는 끝까지 간다.
    try {
      $rawPath = (Get-Item 'HKCU:\Environment').GetValue('Path', '', 'DoNotExpandEnvironmentNames')
      if (($rawPath -split ';') -notcontains $BinDir) {
        $newPath = if ($rawPath) { "$BinDir;$rawPath" } else { $BinDir }
        Set-ItemProperty -Path 'HKCU:\Environment' -Name Path -Value $newPath -Type ExpandString
        # 새로 여는 창이 바뀐 PATH 를 읽도록 설정 변경 알림을 보낸다.
        try {
          [Environment]::SetEnvironmentVariable('AB_LAB_PATH_REFRESH', '1', 'User')
          [Environment]::SetEnvironmentVariable('AB_LAB_PATH_REFRESH', $null, 'User')
        } catch {}
        Say "PATH 에 $BinDir 을 추가했습니다."
      }
    } catch {
      Write-Host "[확인] PATH 에 등록하지 못했습니다. 새 창에서는  & `"$BinDir\ab-lab.cmd`"  로 실행하세요." -ForegroundColor Yellow
    }
    # 지금 이 창에서도 바로 ab-lab 을 쓸 수 있게 한다.
    if (($env:Path -split ';') -notcontains $BinDir) { $env:Path = "$BinDir;$env:Path" }

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
    Write-Host "    다른 창(VS Code 터미널 등)에서 안 되면 그 창을 닫았다가 다시 여세요."
  } catch {
    Write-Host ""
    Write-Host "[실패] " $_.Exception.Message -ForegroundColor Red
    Write-Host "    이 창의 내용을 강사에게 보여 주세요." -ForegroundColor Red
  }
}
