# 프롬프트 A/B 테스트 랩 (prompt-ab-lab)

지시 두 가지를 같은 입력에 나란히 여러 번 실행해 비교하는 웹 화면입니다.
비코딩 과정 첫날 실습용으로 만들었고, 화면에서 지시문만 고치면 됩니다.

- **Claude** — Claude Code 에 로그인돼 있으면 바로 됩니다. (기본 모델: haiku)
- **vLLM** — 코랩 T4 나 강사 서버의 OpenAI 호환 주소만 넣으면 됩니다.
- **둘 다 한 번에** — 지시 A·B를 Claude와 vLLM 양쪽에서 동시에 돌려 네 열로 나란히 보여 줍니다. 같은 지시가 모델마다 어떻게 다르게 답하는지 견줄 때 씁니다.

의존성은 `@anthropic-ai/claude-agent-sdk` 하나이고, 나머지는 Node.js 내장 모듈만 씁니다.

## 설치 (한 줄)

macOS / 리눅스 / WSL / Git Bash:

```bash
curl -fsSL https://raw.githubusercontent.com/SunCreation/prompt-ab-lab/main/install.sh | bash
```

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/SunCreation/prompt-ab-lab/main/install.ps1 | iex
```

설치가 끝나면 새 터미널에서:

```bash
ab-lab
```

브라우저에 <http://127.0.0.1:8000> 이 열립니다. 멈추려면 터미널에서 `Ctrl+C`.

- 포트가 이미 사용 중이면 자동으로 다음 포트로 넘어갑니다. (`ab-lab --port=8001` 로 지정할 수도 있습니다)
- `ab-lab --open` 은 브라우저를 자동으로 엽니다. (설치 스크립트가 기본으로 넣어 둡니다)

## 화면 사용법

1. 위의 버튼으로 실습을 불러옵니다.
   - **1 · 지시 A vs B** — 한 줄 지시와 네 가지(역할·과업·형식·제약)를 적은 지시를 겨줍니다.
   - **2 · B vs C (JSON)** — 지시 B에 JSON 형식을 더한 C를 겨줍니다.
   - **3 · 깨지는 메일** — 주문 기록에 없는 '50% 환불 약속'을 주장하는 메일에 지시 A와 B를 겨줍니다. 네 가지를 적은 지시가 이 메일도 제대로 받는지 봅니다.
   - **4 · 한 문장만 고치기** — 지시 A에 규칙 문장과 사정 문장을 각각 더해 겨줍니다.
   - **5 · 네 차례** — 직접 쓴 지시를 지시 A와 겨룹니다.
2. **모델이 실제로 받는 입력**에서 지시가 `system` 자리에, 이메일이 `user` 자리에 들어가는지 확인합니다. 지시를 고치면 이 요청도 바로 바뀝니다.
3. 실행할 모델을 고릅니다. **Claude만** / **vLLM만** / **둘 다 한 번에** 중에서 고르고, vLLM 모델명은 비워 두면 교안의 기본 모델이 쓰입니다.
4. **A / B 동시에 실행**을 누릅니다. 지시마다 반복은 기본 1회이고 필요하면 3회로 늘립니다.

자동 표시(글자 수·문장 수·JSON 모양·빈칸으로 보이는 표시)는 참고용이고,
날짜를 지어냈는지, 보상을 약속했는지, 그대로 보낼 수 있는지는 사람이 읽고 판정합니다.

## 직접 실행 (설치 스크립트 없이)

```bash
git clone https://github.com/SunCreation/prompt-ab-lab.git
cd prompt-ab-lab
npm install
node ab_tester.mjs --open
```

## 수업 전 준비 (강사)

- `node ab_tester.mjs --port=8000 --open` 으로 미리 띄워 두고 화면을 공유합니다.
- 강사 서버 주소를 학생에게 안내할 때는 `/v1` 까지 적어 주세요. (예: `https://xxxx.ngrok-free.app/v1`)

## 라이선스

내부 교육용.
