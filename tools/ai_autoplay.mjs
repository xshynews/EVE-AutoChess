#!/usr/bin/env node
/**
 * EVE 自走棋 —— AI 自动对战（tools/ai_autoplay.mjs）
 *
 * 一个**启发式机器人**，只通过 AI 桥（127.0.0.1:9081）操作游戏，
 * 用途有两个：
 *   ① 证明「自走棋任务关卡」这条操作面是真的能打通整局的；
 *   ② 给后面的真 AI 当决策骨架（买什么 / 放哪里 / 选哪条增益）。
 *
 *   node tools/ai_autoplay.mjs [--nodes 6] [--difficulty 1] [--shots]
 */
import net from "node:net";

const PORT = Number(process.env.AI_PORT || 9080 + 1);
const HOST = process.env.AI_HOST || "127.0.0.1";

const argv = process.argv.slice(2);
const arg = (k, d) => {
  const i = argv.indexOf("--" + k);
  return i >= 0 && argv[i + 1] !== undefined ? argv[i + 1] : d;
};
const MAX_NODES = Number(arg("nodes", 6));
const DIFFICULTY = Number(arg("difficulty", 1));
const TAKE_SHOTS = argv.includes("--shots");
const VERBOSE = argv.includes("--verbose");

const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);

let sock = net.createConnection({ host: HOST, port: PORT });
let buf = "";
let nextId = 1;
const pending = new Map();

sock.on("data", (chunk) => {
  buf += chunk.toString("utf8");
  let i = buf.indexOf("\n");
  while (i >= 0) {
    const line = buf.slice(0, i).trim();
    buf = buf.slice(i + 1);
    if (line) {
      try {
        const obj = JSON.parse(line);
        const p = pending.get(obj.id);
        if (p) { pending.delete(obj.id); p(obj); }
      } catch (e) { log("bad reply", line); }
    }
    i = buf.indexOf("\n");
  }
});
sock.on("error", (e) => { log("连接失败:", e.message); process.exit(3); });

function send(cmd, args) {
  const id = nextId++;
  return new Promise((resolve) => {
    pending.set(id, resolve);
    sock.write(JSON.stringify({ id, cmd, args: args || {} }) + "\n");
    // 客户端侧超时：桥那边协程卡住时不让机器人干等
    setTimeout(() => { if (pending.delete(id)) resolve({ ok: false, error: "client timeout" }); }, 20000);
  });
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ── 决策辅助 ────────────────────────────────────────────────────
const own = (s) => (s.own || []).filter((x) => x.alive);
const enemies = (s) => (s.enemy || []).filter((x) => x.alive);

/** 准备阶段：有钱就买，买完就上场，然后开战。 */
async function prep(s) {
  const offers = (s.shop && s.shop.offers) || [];
  // ① 买：从便宜的开始，别把钱一次烧光（留 2 刷新费）
  let coin = s.economy ? s.economy.coin : 0;
  let benchCount = (s.bench || []).length;
  for (const o of offers) {
    if (!o || !o.ship_key) continue;
    if (o.cost <= coin - 2 && benchCount < 8) {
      const r = await send("buy", { index: o.index });
      if (r.ok) { log("买", o.name, "◆" + o.cost); coin -= o.cost; benchCount++; }
    }
  }
  // ② 升级：钱多就买经验
  const st = await send("state");
  const cur = st.data || {};
  if ((cur.economy ? cur.economy.coin : 0) >= 12 && (cur.economy ? cur.economy.level : 1) < 6) {
    await send("levelup");
    log("买经验 → Lv", (cur.economy.level || 1) + 1);
  }
  // ③ 上场：备战席全放到我方区（行 7~10，从后住前填）
  //    ⚠️ 必须跳过**已占用**的格子：run.deploy_from_bench 不接受重叠，
  //       而 bench 下标在每次成功后都会变（买过的船会插队）。
  const st2 = await send("state");
  const s2 = st2.data || {};
  const taken = new Set();
  for (const f of s2.field || []) {
    const m = /^\((\d+),\s*(\d+)\)$/.exec(String(f.cell || ""));
    if (m) taken.add(m[1] + ":" + m[2]);
  }
  const free = [];
  for (let r = 7; r <= 10; r++) for (let c = 0; c < 11; c++) {
    if (!taken.has(r + ":" + c)) free.push([r, c]);
  }
  let ci = 0;
  const limit = s2.field_limit || 3;
  const onField = (s2.field || []).length;
  for (let b = 0; b < (s2.bench || []).length && onField + b < limit; b++) {
    const cell = free[ci++];
    if (!cell) break;
    const r = await send("deploy", { bench: b, row: cell[0], col: cell[1] });
    if (r.ok) log("上场 备战席", b, "→", cell.join(","));
    else if (VERBOSE) log("上场被拒:", JSON.stringify(r.data));
  }
  const fr = await send("start_battle");
  if (!fr.ok) log("开战被拒:", fr.error || JSON.stringify(fr.data));
  else log("开战");
}

/** 战斗：快进到结束。 */
async function battle(s) {
  const left = s.timer_left > 0 ? s.timer_left : 20;
  await send("fast_forward", { seconds: Math.min(60, left + 6) });
}

/** 结算：能捞的残骸先捞，然后下一节点。 */
async function resolve(s) {
  const sal = s.salvage || {};
  if (sal.state === "list") {
    for (const it of sal.items || []) {
      if (it.price <= (sal.coin || 0)) {
        const r = await send("salvage", { index: it.idx });
        if (r.ok) log("打捞", it.name, "−◆" + it.price);
      }
    }
  }
  await send("result_next");
  log("结算 → 下一节点");
  // 结算页有关卡延迟（1s 弹窗），等一拍免得同一相位反复进来
  await sleep(900);
}

/** 事件节点：优先选不加钱也能立刻生效的那条。 */
async function event(s) {
  const ev = s.event || {};
  if (ev.ship_pick_open) {
    await send("event_ship", { index: 0 });
    log("事件选船 → 0");
    return;
  }
  if (ev.open) {
    const opts = (ev.options || []).filter((o) => !o.taken && o.id);
    if (!opts.length) { log("事件：没有可选项"); return; }
    // 简单偏好：星币 > 经验 > 其它；同档取靠前的
    const score = (o) => (o.coin ? 100 : 0) + (o.xp ? 50 : 0) + (o.beacon_max ? 30 : 0);
    opts.sort((a, b) => score(b) - score(a));
    const pick = opts[0];
    await send("event_choose", { id: String(pick.id) });
    log("事件选:", pick.name || pick.id);
  }
}

async function main() {
  log("AI 自动对战启动：最多", MAX_NODES, "个节点，难度下标", DIFFICULTY);
  // ① 若在主菜单：开机进一局
  let r = await send("info");
  if (r.data && r.data.scene !== "battle") {
    r = await send("state");
    if (r.data && r.data.scene === "menu") {
      await send("select_mode", { index: 2 });
      await send("select_difficulty", { index: DIFFICULTY });
      await send("start");
      log("主菜单 → 开始一局");
    }
  }
  // ② 主循环
  let guard = 0;
  while (guard++ < 400) {
    const st = await send("state");
    if (!st.ok) { log("state 失败:", st.error); break; }
    const s = st.data || {};
    const node = s.node ? s.node.index : "?";
    if (VERBOSE) log("phase", s.phase_name, "node", node, "coin",
      s.economy ? s.economy.coin : "?", "own", own(s).length, "enemy", enemies(s).length);
    if (TAKE_SHOTS && s.phase_name === "BATTLE") {
      await send("screenshot", { name: "auto_node" + node });
    }
    // ⓪ 确认框优先：弹着的时候别的指令都不会生效（AI 会看起来"卡住"）
    const dlg = s.dialog || {};
    if (dlg.any_open) {
      // 残骸捞完 / 捞不起就走人；否则先尽可能捞
      const sal = s.salvage || {};
      if (sal.state === "list" && (sal.items || []).some((it) => it.price <= (sal.coin || 0))) {
        await resolve(s);
      } else {
        const r = await send("dialog_confirm");
        log(r.ok ? "确认框：放弃残骸并继续" : "确认框确认失败");
      }
      await sleep(400);
      continue;
    }

    switch (s.phase_name) {
      case "PREP":
        if ((s.event || {}).open || (s.event || {}).ship_pick_open) await event(s);
        else await prep(s);
        break;
      case "BATTLE":
        await battle(s);
        break;
      case "RESOLVE":
        await resolve(s);
        break;
      case "ENDING":
        log("本局结束：node", node, "beacon", s.economy ? s.economy.beacon : "?");
        await send("screenshot", { name: "auto_ending" });
        return;
      default:
        await sleep(500);
    }
    // 节点推进够了就收工
    if (typeof node === "number" && node >= MAX_NODES) {
      log("已推进到节点", node, "，收工");
      await send("screenshot", { name: "auto_node" + node });
      return;
    }
    await sleep(120);
  }
  log("达到步数上限，退出");
}

main().then(() => { sock.end(); process.exit(0); });
