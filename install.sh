#!/usr/bin/env bash
# 프롬프트 A/B 테스트 랩 설치 스크립트 — macOS / 리눅스 / WSL / Git Bash
# 설치 후 "ab-lab" 한 명령으로 웹 화면을 띄웁니다.
#
# curl | bash 로 실행되므로 전체를 main 함수에 담아 맨 끝 줄에서 부른다.
# 내려받기가 중간에 끊겨도 반쯤 받은 스크립트가 실행되지 않고, 중간에 표준 입력을 읽는 명령이 있어도 스크립트가 잘리지 않는다.
set -euo pipefail

REPO="${AB_LAB_REPO:-SunCreation/prompt-ab-lab}"
DEST="${HOME}/.prompt-ab-lab"
BIN_DIR="${HOME}/.local/bin"
NVM_VERSION="v0.40.8"
LOG="$(mktemp "${TMPDIR:-/tmp}/ab-lab-install.XXXXXX")"

say()  { printf '\033[1;34m[설치]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[확인]\033[0m %s\n' "$*" >&2; }
fail() {
  printf '\033[1;31m[실패]\033[0m %s\n' "$*" >&2
  printf '    이 창의 내용을 강사에게 보여 주세요.\n' >&2
  exit 1
}
# git·npm·nvm 출력은 로그에 모아 두었다가, 실패했을 때만 끝부분을 보여 준다.
run() { "$@" >>"$LOG" 2>&1; }
show_log() {
  printf -- '----- 마지막 출력 (%s) -----\n' "$LOG" >&2
  tail -n 20 "$LOG" >&2
}

# nvm 은 set -e / set -u 와 함께 쓰면 중간에 멈출 수 있어, nvm 을 부르는 동안만 끈다.
load_nvm() {
  local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
  [ -s "$nvm_dir/nvm.sh" ] || return 0
  set +eu
  . "$nvm_dir/nvm.sh"
  set -eu
  return 0
}
nvm_lts() {
  local rc
  set +eu
  nvm install --lts >>"$LOG" 2>&1 && nvm use --lts >>"$LOG" 2>&1
  rc=$?
  set -eu
  return "$rc"
}

have_node() {
  command -v node >/dev/null 2>&1 || return 1
  local major
  major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
  [ "$major" -ge 18 ]
}

main() {
  # macOS 의 /usr/bin/git 은 Xcode 명령줄 도구가 없으면 설치 안내만 띄우는 껍데기라, 실제로 돌려 본다.
  if ! command -v git >/dev/null 2>&1 || ! git --version >/dev/null 2>&1; then
    if [ "$(uname -s)" = "Darwin" ]; then
      fail "git 을 쓸 수 없습니다. 터미널에서  xcode-select --install  을 실행해 명령줄 도구를 설치한 뒤 다시 실행해 주세요."
    fi
    fail "git이 없습니다. https://git-scm.com/downloads 에서 설치한 뒤 다시 실행해 주세요."
  fi

  # ---- Node.js 18 이상 확인 (nvm 으로 설치된 환경이라면 그 Node 를 쓴다) ----
  load_nvm
  if ! have_node; then
    if ! command -v nvm >/dev/null 2>&1; then
      say "Node.js LTS 를 nvm 으로 설치합니다. (공식 설치 스크립트)"
      run bash -c "curl -fsSL 'https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh' | bash" \
        || { show_log; fail "nvm 설치에 실패했습니다. 인터넷 연결을 확인해 주세요."; }
      load_nvm
    fi
    say "nvm 으로 Node.js LTS 를 설치합니다."
    nvm_lts || { show_log; fail "Node.js 설치에 실패했습니다."; }
  fi
  have_node || fail "Node.js 18 이상이 필요합니다. 바이브 코딩 모듈 1강의 개발 환경 설치를 먼저 마친 뒤 다시 실행해 주세요."
  say "Node.js $(node --version) 사용"

  # ---- 내려받기 ----
  # 이전 설치가 있으면 최신으로 맞춘다. 중간에 끊긴 설치도 reset 으로 되살린다.
  local ready=0 kept_old=0
  if [ -d "$DEST/.git" ]; then
    say "이전 설치를 최신으로 갱신합니다."
    if run git -C "$DEST" fetch --depth 1 --quiet origin HEAD \
      && run git -C "$DEST" reset --hard --quiet FETCH_HEAD \
      && [ -f "$DEST/ab_tester.mjs" ]; then
      ready=1
    fi
  fi
  if [ "$ready" -eq 0 ]; then
    say "도구를 내려받습니다."
    # 옆 폴더에 먼저 받고, 받기에 성공했을 때만 기존 폴더와 바꾼다.
    # 인터넷이 끊긴 채 다시 실행해도 잘 돌던 설치를 지우지 않기 위해서다.
    local tmp="$DEST.new"
    rm -rf "$tmp"
    if run git clone --depth 1 --quiet "https://github.com/${REPO}.git" "$tmp"; then
      # 받아 둔 패키지는 새 폴더로 옮겨 다시 내려받지 않게 하고, 폴더 이름만 바꿔 갈아 끼운다.
      if [ -d "$DEST/node_modules" ]; then mv "$DEST/node_modules" "$tmp/node_modules"; fi
      rm -rf "$DEST.old"
      if [ -e "$DEST" ]; then mv "$DEST" "$DEST.old"; fi
      mv "$tmp" "$DEST"
      rm -rf "$DEST.old"
    else
      rm -rf "$tmp"
      if [ ! -f "$DEST/ab_tester.mjs" ]; then
        show_log
        fail "내려받기에 실패했습니다. 인터넷 연결을 확인해 주세요."
      fi
      warn "최신 버전을 받지 못해 이미 설치된 버전을 그대로 씁니다. 인터넷 연결을 확인해 주세요."
      kept_old=1
    fi
  fi

  # ---- 패키지 설치 ----
  if [ "$kept_old" -eq 1 ] && [ -f "$DEST/node_modules/@anthropic-ai/claude-agent-sdk/package.json" ]; then
    say "패키지는 이미 설치된 것을 그대로 씁니다."
  else
    say "필요한 패키지(약 200MB)를 설치합니다. 1~5분 걸릴 수 있으니 창을 닫지 마세요."
    (cd "$DEST" && run npm install --no-audit --no-fund) \
      || { show_log; fail "패키지 설치에 실패했습니다. 인터넷 연결을 확인한 뒤 설치 명령을 다시 실행해 주세요."; }
  fi

  # ---- 한 줄 명령 등록 ----
  mkdir -p "$BIN_DIR"
  cat > "$BIN_DIR/ab-lab" <<WRAP
#!/usr/bin/env bash
# 프롬프트 A/B 테스트 랩 실행기
export PATH="\${NVM_DIR:-\$HOME/.nvm}/versions/node/\$(ls -1 "\${NVM_DIR:-\$HOME/.nvm}/versions/node" 2>/dev/null | sort -V | tail -1)/bin:\$PATH"
exec node "$DEST/ab_tester.mjs" --open "\$@"
WRAP
  chmod +x "$BIN_DIR/ab-lab" "$DEST/ab_tester.mjs"

  # ---- PATH 등록 ----
  # 새 터미널이 ab-lab 을 찾도록 셸 설정 파일에 PATH 를 적는다.
  # 지금 쓰는 셸의 설정 파일은 없으면 만든다. (새 Mac 에는 ~/.zshrc 가 없을 수 있다)
  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
      local line='export PATH="$HOME/.local/bin:$PATH"'
      local rcs=() rc
      case "$(basename "${SHELL:-}")" in
        zsh) rcs+=("$HOME/.zshrc") ;;
        bash) if [ "$(uname -s)" = "Darwin" ]; then rcs+=("$HOME/.bash_profile"); else rcs+=("$HOME/.bashrc"); fi ;;
      esac
      for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
        if [ -f "$rc" ]; then rcs+=("$rc"); fi
      done
      for rc in ${rcs[@]+"${rcs[@]}"}; do
        grep -qF "$line" "$rc" 2>/dev/null || printf '\n%s\n' "$line" >> "$rc"
      done
      ;;
  esac

  # Claude Code 로그인 안내 (Claude 모드에만 필요)
  if command -v claude >/dev/null 2>&1; then
    if claude auth status 2>/dev/null </dev/null | grep -q '"loggedIn": *true'; then
      say "Claude Code 로그인 확인됨"
    else
      warn "Claude Code 에 로그인되어 있지 않습니다. Claude 모드를 쓰려면 터미널에서 'claude' 를 실행해 로그인하세요. (vLLM 모드는 로그인 없이 됩니다)"
    fi
  else
    warn "Claude Code CLI 를 찾지 못했습니다. Claude 모드를 쓰려면 바이브 코딩 모듈에서 설치한 Claude Code 의 경로를 확인하세요. (vLLM 모드는 그냥 됩니다)"
  fi

  rm -f "$LOG"
  echo
  say "설치가 끝났습니다."
  echo "    새 터미널을 열고  ab-lab  을 입력하면 브라우저에 화면이 뜹니다."
  echo "    새 터미널에서도 ab-lab 을 못 찾으면  ~/.local/bin/ab-lab  으로 실행하세요."
  echo "    이미 ab-lab 이 실행 중이라면  ab-lab --port=8001  처럼 다른 포트를 쓰세요."
}

main "$@"
