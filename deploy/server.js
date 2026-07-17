// EE COMBAT — Railway front: static web-export host + WebSocket proxy + Godot supervisor.
// Zero npm dependencies (node core only).
const http = require("http");
const net = require("net");
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");
const { spawn } = require("child_process");

const PORT = parseInt(process.env.PORT || "8080", 10);
const GODOT_PORT = 9801;
const WEB_ROOT = path.join(__dirname, "web");
const DATA_DIR = process.env.EE2_DATA_DIR || "/data";

// ---------- Godot dedicated server (child process, auto-restart) ----------
let godot = null;
let backoff = 1000;
let shuttingDown = false;

function startGodot() {
  if (shuttingDown) return;
  try {
    fs.mkdirSync(DATA_DIR, { recursive: true });
  } catch (e) {}
  const bin = path.join(__dirname, "server", "ee2_server.x86_64");
  try {
    fs.chmodSync(bin, 0o755); // tarballs from Windows lose the exec bit; no RUN steps in the Dockerfile
  } catch (e) {}
  godot = spawn(bin, ["--headless", "--", "--server", "--port", String(GODOT_PORT)], {
    cwd: path.join(__dirname, "server"),
    stdio: ["ignore", "inherit", "inherit"],
    env: { ...process.env, EE2_DATA_DIR: DATA_DIR },
  });
  console.log(`[supervisor] godot server started pid=${godot.pid} ws-port=${GODOT_PORT}`);
  godot.on("exit", (code, sig) => {
    if (shuttingDown) return;
    console.log(`[supervisor] godot exited code=${code} sig=${sig} — restart in ${backoff}ms`);
    setTimeout(startGodot, backoff);
    backoff = Math.min(backoff * 2, 15000);
  });
  setTimeout(() => (backoff = 1000), 30000);
}
startGodot();

// ---------- static cache (pre-gzipped in memory at boot) ----------
const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript",
  ".wasm": "application/wasm",
  ".pck": "application/octet-stream",
  ".png": "image/png",
  ".ico": "image/x-icon",
  ".json": "application/json",
  ".svg": "image/svg+xml",
};
const cache = new Map(); // url -> {buf, gz, type}
for (const f of fs.readdirSync(WEB_ROOT)) {
  if (f.endsWith(".import")) continue;
  const full = path.join(WEB_ROOT, f);
  if (!fs.statSync(full).isFile()) continue;
  const buf = fs.readFileSync(full);
  const entry = { buf, type: MIME[path.extname(f)] || "application/octet-stream", gz: null };
  if (buf.length > 8192) entry.gz = zlib.gzipSync(buf, { level: 6 });
  cache.set("/" + f, entry);
}
cache.set("/", cache.get("/index.html"));
console.log(`[web] cached ${cache.size} files from ${WEB_ROOT}`);

const server = http.createServer((req, res) => {
  const url = (req.url || "/").split("?")[0];
  if (url === "/healthz") {
    const up = godot && godot.exitCode === null;
    res.writeHead(up ? 200 : 503, { "Content-Type": "text/plain" });
    res.end(up ? "ok" : "godot-down");
    return;
  }
  const e = cache.get(url);
  if (!e) {
    res.writeHead(404, { "Content-Type": "text/plain" });
    res.end("not found");
    return;
  }
  const headers = {
    "Content-Type": e.type,
    "Cache-Control": url === "/" || url.endsWith(".html") ? "no-cache" : "public, max-age=3600",
  };
  const acceptGz = /\bgzip\b/.test(req.headers["accept-encoding"] || "");
  if (e.gz && acceptGz) {
    headers["Content-Encoding"] = "gzip";
    headers["Content-Length"] = e.gz.length;
    res.writeHead(200, headers);
    res.end(e.gz);
  } else {
    headers["Content-Length"] = e.buf.length;
    res.writeHead(200, headers);
    res.end(e.buf);
  }
});

// ---------- WebSocket proxy: /ws -> godot (raw TCP splice, handshake replayed) ----------
server.on("upgrade", (req, socket, head) => {
  const url = (req.url || "/").split("?")[0];
  if (url !== "/ws") {
    socket.write("HTTP/1.1 404 Not Found\r\n\r\n");
    socket.destroy();
    return;
  }
  const backend = net.connect(GODOT_PORT, "127.0.0.1");
  const kill = () => {
    socket.destroy();
    backend.destroy();
  };
  backend.on("connect", () => {
    let raw = "GET / HTTP/1.1\r\n";
    for (let i = 0; i < req.rawHeaders.length; i += 2) {
      raw += req.rawHeaders[i] + ": " + req.rawHeaders[i + 1] + "\r\n";
    }
    raw += "\r\n";
    backend.write(raw);
    if (head && head.length) backend.write(head);
    socket.pipe(backend);
    backend.pipe(socket);
  });
  backend.on("error", kill);
  socket.on("error", kill);
  socket.setNoDelay(true);
  backend.setNoDelay(true);
});

server.listen(PORT, "0.0.0.0", () => console.log(`[web] EE COMBAT listening on :${PORT}`));

process.on("SIGTERM", () => {
  shuttingDown = true;
  console.log("[supervisor] SIGTERM — stopping godot");
  try {
    if (godot) godot.kill("SIGTERM");
  } catch (e) {}
  setTimeout(() => process.exit(0), 2000);
});
