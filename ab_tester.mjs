// 프롬프트 A/B 테스트 랩 — 지시 두 가지를 나란히 여러 번 실행해 비교합니다.
// 의존성은 @anthropic-ai/claude-agent-sdk 하나이고, 나머지는 Node.js 내장 모듈만 씁니다.
import http from "node:http";
import { readFileSync } from "node:fs";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { query } from "@anthropic-ai/claude-agent-sdk";

const HERE = dirname(fileURLToPath(import.meta.url));
const DEFAULT_PORT = 8000;

async function callVllm({ vllm_url, vllm_model, system_prompt, user_input }) {
  const base = String(vllm_url || "").trim().replace(/\/+$/, "");
  const DEFAULT_VLLM_MODEL = "cyankiwi/Qwen3.5-4B-AWQ-4bit"; // 교안의 코랩 T4 모델. 모델명이 비면 이 값이 쓰입니다.
  const model = String(vllm_model || "").trim() || DEFAULT_VLLM_MODEL;
  if (!base) throw new Error("vLLM 서버 주소를 적어 주세요.");
  const response = await fetch(base.replace(/\/chat\/completions$/, "") + "/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: "Bearer EMPTY",
      // ngrok 무료 터널은 브라우저 경고 페이지를 끼워 넣습니다. 이 헤더로 건너뜁니다.
      "ngrok-skip-browser-warning": "true",
    },
    body: JSON.stringify({
      model,
      temperature: 0.3,
      messages: [
        { role: "system", content: system_prompt },
        { role: "user", content: user_input },
      ],
      chat_template_kwargs: { enable_thinking: false },
    }),
    signal: AbortSignal.timeout(120_000),
  });
  const raw = await response.text();
  if (!response.ok) {
    throw new Error(`vLLM 서버가 응답하지 못했습니다 (HTTP ${response.status}) — ${raw.slice(0, 200)}`);
  }
  let data;
  try {
    data = JSON.parse(raw);
  } catch {
    throw new Error("vLLM 응답이 JSON이 아닙니다. 주소가 /v1 로 끝나는지, 서버가 켜져 있는지 확인해 주세요.");
  }
  const text = data?.choices?.[0]?.message?.content ?? "";
  const reason = data?.choices?.[0]?.finish_reason;
  return { text: String(text), note: reason && reason !== "stop" ? `finish_reason=${reason}` : "" };
}

async function callClaude({ claude_model, system_prompt, user_input }) {
  let text = "";
  for await (const event of query({
    prompt: user_input,
    options: {
      model: String(claude_model || "haiku").trim(),
      systemPrompt: system_prompt,
      tools: [],
      maxTurns: 1,
      // 사용자 컴퓨터의 Claude Code 설정(CLAUDE.md 등)이 입력에 섞이지 않게 합니다.
      settingSources: [],
    },
  })) {
    if (event.type === "assistant" && event.message?.content) {
      for (const block of event.message.content) if (block.type === "text") text += block.text;
    }
  }
  return { text, note: "" };
}

async function handleRun(req, res) {
  let body = "";
  for await (const chunk of req) body += chunk;
  try {
    const { provider, system_prompt, user_input, vllm_url, vllm_model, claude_model } = JSON.parse(body);
    if (!system_prompt || !user_input) throw new Error("지시와 입력을 모두 적어 주세요.");
    let out;
    if (provider === "vllm") out = await callVllm({ vllm_url, vllm_model, system_prompt, user_input });
    else if (provider === "claude") out = await callClaude({ claude_model, system_prompt, user_input });
    else throw new Error("지원하지 않는 모드입니다.");
    res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify(out));
  } catch (err) {
    res.writeHead(500, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ detail: err?.message || String(err) }));
  }
}

function openBrowser(url) {
  const [cmd, args] = process.platform === "darwin" ? ["open", [url]]
    : process.platform === "win32" ? ["cmd", ["/c", "start", "", url]]
    : ["xdg-open", [url]];
  try {
    // 명령이 없으면(예: xdg-open 이 없는 WSL) spawn 은 던지지 않고 'error' 이벤트를 낸다. 받지 않으면 서버가 죽는다.
    spawn(cmd, args, { stdio: "ignore", detached: true }).on("error", () => {}).unref();
  } catch {
    // 브라우저를 열지 못해도 서버는 계속 실행됩니다. 주소는 터미널에 출력됩니다.
  }
}

function listen(port, triesLeft) {
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, "http://localhost");
    if (req.method === "GET" && url.pathname === "/") {
      res.writeHead(200, { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" });
      res.end(readFileSync(join(HERE, "index.html"), "utf8"));
    } else if (req.method === "GET" && url.pathname === "/healthz") {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ ok: true }));
    } else if (req.method === "POST" && url.pathname === "/api/run") {
      handleRun(req, res);
    } else {
      res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
      res.end("Not Found");
    }
  });
  server.on("error", (err) => {
    if (err.code === "EADDRINUSE" && triesLeft > 0) {
      console.log(`포트 ${port}는 이미 사용 중입니다. ${port + 1}포트로 다시 시도합니다.`);
      listen(port + 1, triesLeft - 1);
    } else {
      console.error("서버를 시작하지 못했습니다:", err.message);
      process.exit(1);
    }
  });
  server.listen(port, "127.0.0.1", () => {
    const url = `http://127.0.0.1:${port}`;
    console.log("프롬프트 A/B 테스트 랩이 실행 중입니다.");
    console.log(`브라우저에서 ${url} 을 여세요.  (멈추려면 Ctrl+C)`);
    if (process.argv.includes("--open")) openBrowser(url);
  });
}

const argPort = Number((process.argv.find((a) => a.startsWith("--port=")) || "").split("=")[1]);
listen(Number.isInteger(argPort) && argPort > 0 ? argPort : DEFAULT_PORT, 10);
