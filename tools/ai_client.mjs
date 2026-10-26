#!/usr/bin/env node
/**
 * EVE 自走棋 —— AI 操作客户端（tools/ai_client.mjs）
 *
 * 一行一个 JSON 连上游戏里的 AI 桥（127.0.0.1:9081）。
 *
 *   node tools/ai_client.mjs ping
 *   node tools/ai_client.mjs state
 *   node tools/ai_client.mjs buy 0
 *   node tools/ai_client.mjs deploy 0 3 2      # 备战席0 → 第3行第2列
 *   node tools/ai_client.mjs start            # 开战
 *   node tools/ai_client.mjs wait 8
 *   node tools/ai_client.mjs shot prep        # 截图
 *   node tools/ai_client.mjs colors '{"artillery_core":[1,0.9,0.7,1],"artillery_edge":[1,0.3,0.1,1]}'
 */
import net from "node:net";

const PORT = Number(process.env.AI_PORT || 9081);
const HOST = process.env.AI_HOST || "127.0.0.1";

// 短别名 → 游戏侧真命令名（AI 手打时省事）
const ALIAS = {
  // ⚠️ start 留给主菜单的「开始一局」；战斗里开战用 fight
  fight: "start_battle", menu: "back_to_menu", next: "result_next",
  end: "result_end", ff: "fast_forward", shot: "screenshot", lock: "shop_lock",
};

const args = process.argv.slice(2);
if (args.length === 0) {
  console.error("用法: node tools/ai_client.mjs <cmd> [args...]");
  process.exit(2);
}

const [raw, ...rest] = args;
const cmd = ALIAS[raw] ?? raw;
const num = (v) => (v === undefined ? undefined : Number(v));
const on = (v) => v === "1" || v === "true" || v === "on";

function build(cmd, rest) {
  switch (cmd) {
    case "state": case "ping": case "info": case "quit":
    case "refresh": case "levelup": case "restart":
    case "result_next": case "result_end": case "salvage_zero":
    case "start_battle": case "back_to_menu":
      return { cmd };
    case "wait": case "fast_forward":
      return { cmd, args: { seconds: num(rest[0] ?? 1) } };
    case "buy": case "recall": case "salvage": case "event_ship":
      return { cmd, args: { index: num(rest[0] ?? 0) } };
    case "move":
      return { cmd, args: { field: num(rest[0]), row: num(rest[1]), col: num(rest[2]) } };
    case "deploy":
      return { cmd, args: { bench: num(rest[0]), row: num(rest[1]), col: num(rest[2]) } };
    case "sell":
      return { cmd, args: { source: rest[0] ?? "bench", index: num(rest[1] ?? 0) } };
    case "stance":
      return { cmd, args: { ship_id: num(rest[0]), stance: num(rest[1]) } };
    case "pause": case "shop_lock": case "shell": case "markers":
    case "settings":
      return { cmd, args: { on: on(rest[0]) } };
    case "start": case "continue": case "select_mode": case "select_difficulty":
    case "replay_intro": case "quit_game": case "next": case "skip_talk":
    case "finish": case "seek":
      return { cmd, args: rest.length ? {
        difficulty_index: rest[0] !== undefined ? num(rest[0]) : undefined,
        difficulty_id: rest[1] ?? undefined,
        index: rest[0] !== undefined ? num(rest[0]) : undefined,
        t: rest[0] !== undefined ? num(rest[0]) : undefined,
      } : {} };
    case "screenshot":
      return { cmd, args: { name: rest[0] ?? "shot" } };
    case "ui_map":
      return { cmd };
    case "ui_click":
      return { cmd, args: { query: rest.join(" ") } };
    case "mouse_move": case "hover": case "mouse_move_vp":
      return { cmd, args: { x: num(rest[0]), y: num(rest[1]) } };
    case "cell_point":
      return { cmd, args: { row: num(rest[0]), col: num(rest[1]) } };
    case "verify_point":
      return { cmd, args: { x: num(rest[0]), y: num(rest[1]), path: rest[2] ?? "" } };
    case "calibrate_mouse":
      return { cmd };
    case "mouse_click": case "mouse_down": case "mouse_up":
      return { cmd, args: { x: num(rest[0]), y: num(rest[1]), button: num(rest[2] ?? 1) } };
    case "mouse_drag":
      return { cmd, args: { ax: num(rest[0]), ay: num(rest[1]), bx: num(rest[2]), by: num(rest[3]), steps: num(rest[4] ?? 12) } };
    case "mouse_path":
      // 用法: mouse_path '[[x,y],[x,y],...]' [hold]
      return { cmd, args: { points: JSON.parse(rest[0] ?? "[]"), hold: rest[1] === "hold" } };
    case "frame":
      return { cmd, args: { mode: rest[0] ?? "battle" } };
    case "camera":
      return { cmd, args: {
        yaw: rest[0] !== undefined ? num(rest[0]) : undefined,
        pitch: rest[1] !== undefined ? num(rest[1]) : undefined,
        zoom: rest[2] !== undefined ? num(rest[2]) : undefined,
      } };
    case "colors":
      return { cmd, args: JSON.parse(rest[0] ?? "{}") };
    case "event_choose":
      return { cmd, args: { id: rest[0] ?? "" } };
    default:
      return { cmd, args: rest.length ? JSON.parse(rest[0]) : {} };
  }
}

const req = build(cmd, rest);
req.id = 1;

const sock = net.createConnection({ host: HOST, port: PORT }, () => {
  sock.write(JSON.stringify(req) + "\n");
});

let buf = "";
sock.on("data", (chunk) => {
  buf += chunk.toString("utf8");
  let i = buf.indexOf("\n");
  while (i >= 0) {
    const line = buf.slice(0, i).trim();
    buf = buf.slice(i + 1);
    if (line) {
      let obj = null;
      try { obj = JSON.parse(line); } catch { console.error("bad reply:", line); }
      if (obj) {
        // 原样打印整条响应：ok / data / error 都要看得见
        console.log(JSON.stringify(obj));
        if (obj.ok === false) console.error("ERROR:", obj.error);
        sock.end();
        process.exit(obj.ok === false ? 1 : 0);
      }
    }
    i = buf.indexOf("\n");
  }
});
sock.on("error", (e) => {
  console.error("连接失败（游戏在跑吗？AI 桥监听 " + HOST + ":" + PORT + "）：" + e.message);
  process.exit(3);
});
setTimeout(() => { console.error("超时"); process.exit(4); }, 30000).unref();
