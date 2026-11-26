#!/usr/bin/env bash
# 프롬프트 A/B 테스트 랩 설치 스크립트 — macOS / 리눅스 / WSL / Git Bash
# 설치 후 "ab-lab" 한 명령으로 웹 화면을 띄웁니다.
set -euo pipefail

REPO="${AB_LAB_REPO:-SunCreation/prompt-ab-lab}"
DEST="${HOME}/.prompt-ab-lab"
NVM_VERSION="v0.40.8"

say()  { printf '\033[1;34m[설치]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[확인]\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31m[실패]\033[0m %s\n' "$*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || fail "git이 없습니다. https://git-scm.com/downloads 에서 설치한 뒤 다시 실행해 주세요."

# ---- Node.js 18 이상 확인 (nvm 으로 설치된 환경이라면 새 셸에서 로드) ----
load_nvm() {
  local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
  # shellcheck disable=SC1091
  [ -s "$nvm_dir/nvm.sh" ] && . "$nvm_dir/nvm.sh"
}
load_nvm

have_node() {
  command -v node >/dev/null 2>&1 || return 1
  local major
  major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
  [ "$major" -ge 18 ]
}

if ! have_node; then
  if [ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ] || [ -s "$HOME/.nvm/nvm.sh" ]; then
    say "nvm 으로 Node.js LTS 를 설치합니다."
    nvm install --lts >/dev/null
    nvm use --lts >/dev/null
  else
    say "Node.js LTS 를 nvm 으로 설치합니다. (공식 설치 스크립트)"
    curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
    load_nvm
    nvm install --lts >/dev/null
    nvm use --lts >/dev/null
  fi
fi
have_node || fail "Node.js 18 이상이 필요합니다. 바이브 코딩 모듈 1강의 개발 환경 설치를 먼저 마친 뒤 다시 실행해 주세요."
say "Node.js $(node --version) 사용"

# ---- 내려받고 의존성 설치 ----
if [ -d "$DEST/.git" ]; then
  say "이전 설치를 최신으로 갱신합니다."
  git -C "$DEST" pull --ff-only >/dev/null 2>&1 || { rm -rf "$DEST"; }
fi
if [ ! -d "$DEST/.git" ]; then
  say "도구를 내려받습니다."
  rm -rf "$DEST"
  mkdir -p "$DEST"
  git clone --depth 1 "https://github.com/${REPO}.git" "$DEST" >/dev/null 2>&1 || fail "내려받기에 실패했습니다. 인터넷 연결을 확인해 주세요."
fi
say "필요한 패키지를 설치합니다. (잠시 걸립니다)"
(cd "$DEST" && npm install --no-audit --no-fund >/dev/null 2>&1) || fail "패키지 설치에 실패했습니다. '$DEST' 에서 npm install 을 다시 실행해 보세요."

# ---- 한 줄 명령 등록 ----
BIN_DIR="${HOME}/.local/bin"
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/ab-lab" <<WRAP
#!/usr/bin/env bash
# 프롬프트 A/B 테스트 랩 실행기
export PATH="\${NVM_DIR:-\$HOME/.nvm}/versions/node/\$(ls -1 "\${NVM_DIR:-\$HOME/.nvm}/versions/node" 2>/dev/null | sort -V | tail -1)/bin:\$PATH"
exec node "$DEST/ab_tester.mjs" --open "\$@"
WRAP
chmod +x "$BIN_DIR/ab-lab" "$DEST/ab_tester.mjs"

# PATH 안내
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
      [ -f "$rc" ] || continue
      grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$rc" 2>/dev/null || printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
    done
    ;;
esac

# Claude Code 로그인 안내 (Claude 모드에만 필요)
if command -v claude >/dev/null 2>&1; then
  if claude auth status 2>/dev/null | grep -q '"loggedIn": *true'; then
    say "Claude Code 로그인 확인됨"
  else
    warn "Claude Code 에 로그인되어 있지 않습니다. Claude 모드를 쓰려면 터미널에서 'claude' 를 실행해 로그인하세요. (vLLM 모드는 로그인 없이 됩니다)"
  fi
else
  warn "Claude Code CLI 를 찾지 못했습니다. Claude 모드를 쓰려면 바이브 코딩 모듈에서 설치한 Claude Code 의 경로를 확인하세요. (vLLM 모드는 그냥 됩니다)"
fi

echo
say "설치가 끝났습니다."
echo "    새 터미널을 열고  ab-lab  을 입력하면 브라우저에 화면이 뜹니다."
echo "    이미 ab-lab 이 실행 중이라면  ab-lab --port=8001  처럼 다른 포트를 쓰세요."
