import { DurableObject } from "cloudflare:workers";

const json = (value, status = 200) => Response.json(value, { status, headers: { "Cache-Control": "no-store" } });
const validHash = value => typeof value === "string" && /^[0-9a-f]{64}$/.test(value);
const digest = async value => Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value))), b => b.toString(16).padStart(2, "0")).join("");

export default {
  async fetch(request, env) {
    const path = new URL(request.url).pathname;
    if (path === "/health") return json({ service: "RoomGuard", protocol: 1, permanent: true });
    if (!["/v1/live", "/v1/publish", "/v1/status", "/v1/pairing/reset"].includes(path)) return json({ error: "Not found" }, 404);
    if (request.headers.has("Origin")) return json({ error: "Native clients only" }, 403);
    return env.CAMERA.get(env.CAMERA.idFromName("camera")).fetch(request);
  }
};

export class CameraRelay extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.ctx = ctx;
    this.auth = null;
    ctx.blockConcurrencyWhile(async () => {
      this.auth = await ctx.storage.get("auth") || {
        publisherHash: env.PUBLISHER_HASH, viewerHash: env.VIEWER_HASH, generation: "initial"
      };
    });
  }
  sockets(role) { return this.ctx.getWebSockets(role).filter(ws => ws.readyState === 1); }
  send(ws, data) { try { ws.send(data); } catch { try { ws.close(1011, "Connection failed"); } catch {} } }
  notifyPublisher() {
    const notice = JSON.stringify({ viewers: this.sockets("viewer").length });
    this.sockets("publisher").forEach(ws => this.send(ws, notice));
  }
  offline() {
    this.sockets("viewer").forEach(ws => this.send(ws, JSON.stringify({ live: false, status: "PC offline. Waiting for reconnection…" })));
  }
  async fetch(request) {
    const path = new URL(request.url).pathname;
    const role = path === "/v1/publish" || path === "/v1/pairing/reset" ? "publisher" : "viewer";
    const token = request.headers.get("Authorization") || "";
    if (!/^Bearer [0-9a-f]{64}$/.test(token)) return json({ error: "Pairing required" }, 401);
    const hash = await digest(token.slice(7));
    if (!validHash(this.auth[role + "Hash"]) || hash !== this.auth[role + "Hash"]) return json({ error: "Pairing required" }, 401);
    if (path === "/v1/status") {
      return json({ connected: this.sockets("publisher").length > 0, encrypted: true, permanent: true });
    }
    if (path === "/v1/pairing/reset") {
      if (request.method !== "POST") return json({ error: "POST required" }, 405);
      if (Number(request.headers.get("Content-Length")) > 1024) return json({ error: "Too large" }, 413);
      let next;
      try {
        const body = await request.text();
        if (body.length > 1024) return json({ error: "Too large" }, 413);
        next = JSON.parse(body);
      } catch { return json({ error: "Invalid request" }, 400); }
      if (!validHash(next.publisherHash) || !validHash(next.viewerHash)) return json({ error: "Invalid hashes" }, 400);
      // Authentication may have changed while the request body was arriving.
      if (hash !== this.auth.publisherHash) return json({ error: "Pairing changed" }, 401);
      const replacement = { publisherHash: next.publisherHash, viewerHash: next.viewerHash, generation: crypto.randomUUID() };
      await this.ctx.blockConcurrencyWhile(async () => {
        await this.ctx.storage.put("auth", replacement);
        this.auth = replacement;
        this.ctx.getWebSockets().forEach(ws => { try { ws.close(1008, "Pairing reset"); } catch {} });
      });
      return json({ reset: true });
    }
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket" || request.method !== "GET") return json({ error: "WebSocket required" }, 426);
    if (role === "viewer" && this.sockets("viewer").length >= 2) return json({ error: "Two viewers already connected" }, 429);
    if (role === "publisher") this.sockets("publisher").forEach(ws => ws.close(1000, "PC reconnected"));
    const [client, server] = Object.values(new WebSocketPair());
    this.ctx.acceptWebSocket(server, [role]);
    server.serializeAttachment({ role, generation: this.auth.generation, inFlight: 0 });
    if (role === "viewer") this.send(server, JSON.stringify({ live: false, status: this.sockets("publisher").length ? "Waiting for camera…" : "PC offline. Waiting for reconnection…" }));
    this.notifyPublisher();
    return new Response(null, { status: 101, webSocket: client, headers: { "Cache-Control": "no-store" } });
  }
  async webSocketMessage(ws, message) {
    const attachment = ws.deserializeAttachment();
    if (attachment?.generation !== this.auth.generation) {
      ws.close(1008, "Publish access required"); return;
    }
    if (attachment.role === "viewer") {
      if (message === "ack") { ws.serializeAttachment({ ...attachment, inFlight: Math.max(0, (attachment.inFlight || 0) - 1) }); return; }
      ws.close(1008, "Invalid viewer message"); return;
    }
    if (typeof message === "string") {
      if (message.length > 512) { ws.close(1009, "Too large"); return; }
      let value;
      try { value = JSON.parse(message); } catch { ws.close(1008, "Invalid status"); return; }
      if (value.live !== false || typeof value.status !== "string") { ws.close(1008, "Invalid status"); return; }
      message = JSON.stringify({ live: false, status: value.status.slice(0, 100) });
    } else if (message.byteLength < 37 || message.byteLength > 2_000_000) {
      ws.close(1009, "Invalid frame size"); return;
    }
    // Only ciphertext is forwarded. No frame, plaintext, or encryption key is stored.
    this.sockets("viewer").forEach(viewer => {
      const state = viewer.deserializeAttachment();
      // Four frames cover normal mobile latency without an unbounded outgoing queue.
      if (typeof message !== "string") {
        if ((state.inFlight || 0) >= 4) return;
        viewer.serializeAttachment({ ...state, inFlight: (state.inFlight || 0) + 1 });
      }
      this.send(viewer, message);
    });
  }
  async webSocketClose(ws, code, reason) {
    try { ws.close(code === 1005 || code === 1006 ? 1000 : code, reason); } catch {}
    if (ws.deserializeAttachment()?.role === "publisher" && this.sockets("publisher").length === 0) this.offline();
    this.notifyPublisher();
  }
  async webSocketError(ws) {
    try { ws.close(1011, "Connection failed"); } catch {}
    if (ws.deserializeAttachment()?.role === "publisher" && this.sockets("publisher").length === 0) this.offline();
    this.notifyPublisher();
  }
}
