#!/usr/bin/env node
/**
 * EVE 自走棋 —— AI 纯鼠标操作机器人（tools/ai_mouse_bot.mjs）
 *
 * 用户定案（2026-10-26）：不准后台操作。所有动作都走合成鼠标事件：
 * 光标真的会挪（Input.warp_mouse）、真的会点、布阵是真正的拖拽。
 * 本脚本只做两件事：
 *   1) 读 ui_map / state（传感器，允许）；
 *   2) 发 mouse_* / ui_click_*（执行器，全是鼠标）。
 *
 * 坐标为什么能对准（2026-10-26 实测 + 读 Godot 源码）：
 *   Input.warp_mouse() 走 DisplayServer，吃【窗口坐标】；
 *   Control.get_global_rect() 给的是【视口坐标】。两者差一个随窗口大小
 *   变化的偏移（本机实测 +60px）。所以：
 *     - 进场先 calibrate_mouse 量一次偏移并缓存；
 *     - 点控件用 ui_click_path（游戏自己过偏移量）；
 *     - 拖布阵用分阶段拖拽：按下（棋盘才入画）-> 等取景收敛
 *       -> cell_point 用游戏自己的 screen_to_cell 反查真实格子位置
 *       -> 移动 -> 松手。
 *
 * 演示优先：默认慢节奏 + 只打里程碑，观众跟得上。
 *
 *   node tools/ai_mouse_bot.mjs --watch
 *   node tools/ai_mouse_bot.mjs --watch --delay 3000
 *   node tools/ai_mouse_bot.mjs --difficulty hard
 */
import net from "node:net";

const PORT = Number(process.env.AI_PORT || 9081);
const HOST = process.env.AI_HOST || "127.0.0.1";

const argv = process.argv.slice(2);
const arg = (k, d) => {
  const i = argv.indexOf("--" + k);
  return i >= 0 && argv[i + 1] !== undefined ? argv[i + 1] : d;
};
const WATCH = argv.includes("--watch") || argv.includes("--demo");
const DELAY = Number(arg("delay", WATCH ? 2600 : 300));
const DIFF = arg("difficulty", "");
const MAX_NODES = Number(arg("nodes", 15));
const ROUNDS = Math.max(1, Number(arg("rounds", 1)));

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let stepNo = 0;

function step(what, why) {
  if (!WATCH) return;
  stepNo++;
  console.log("  " + String(stepNo).padStart(2, "0") + ". " + what + (why ? "   <- " + why : ""));
}
function note(what) {
  if (!WATCH) return;
  console.log("      . " + what);
}
async function pace() { if (WATCH) await sleep(DELAY); }

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
      } catch (e) { console.error("bad reply", line); }
    }
    i = buf.indexOf("\n");
  }
});
sock.on("error", (e) => { console.error("connection failed:", e.message); process.exit(3); });

function send(cmd, args) {
  const id = nextId++;
  return new Promise((resolve) => {
    pending.set(id, resolve);
    sock.write(JSON.stringify({ id, cmd, args: args || {} }) + "\n");
    setTimeout(() => { if (pending.delete(id)) resolve({ ok: false, error: "timeout" }); }, 40000);
  });
}
const state = async () => {
  const r = await send("state");
  return r.ok ? (r.data || {}) : null;
};
const uiMap = async () => {
  const r = await send("ui_map");
  return r.ok ? (r.data || {}) : null;
};

// ---- mouse primitives ----
const move = (x, y) => send("mouse_move", { x, y });
const clickPath = async (p) => {
  const r = await send("ui_click_path", { path: p });
  if (!r.ok) note("click failed " + p.slice(-24) + ": " + (r.error || JSON.stringify(r.data)));
  return r;
};
const clickNamed = async (q) => {
  const r = await send("ui_click", { query: q });
  if (!r.ok) note("cannot click [" + q + "]: " + (r.error || JSON.stringify(r.data)));
  return r;
};
const center = (rect) => [Math.round(rect[0] + rect[2] / 2), Math.round(rect[1] + rect[3] / 2)];

/**
 * Phased drag (the only reliable way to deploy).
 * 1) press on bench slot -> board enters view; 2) wait for framing to settle;
 * 3) cell_point asks the game for the real screen position of the cell;
 * 4) move in steps (so the cursor is visible); 5) release.
 */
async function phasedDrag(slotRect, row, col, label) {
  const [sx, sy] = center(slotRect);
  const down = await send("mouse_down", { x: sx, y: sy });
  if (!down.ok) { note("press failed"); return false; }
  await sleep(WATCH ? 1400 : 900);
  const cp = await send("cell_point", { row, col });
  if (!cp.ok) { note("cell_point failed"); await send("mouse_up", { x: sx, y: sy }); return false; }
  const d = (cp.data && cp.data.data) || {};
  const cx = Math.round(d.x || 0), cy = Math.round(d.y || 0);
  step(label, "row " + row + " col " + col + " -> screen(" + cx + "," + cy + ")" + (d.found ? "" : " (guess)"));
  const steps = WATCH ? 8 : 5;
  for (let i = 1; i <= steps; i++) {
    const t = i / steps;
    await move(Math.round(sx + (cx - sx) * t), Math.round(sy + (cy - sy) * t));
    await sleep(WATCH ? 110 : 60);
  }
  await sleep(WATCH ? 500 : 200);
  const up = await send("mouse_up", { x: cx, y: cy });
  await sleep(WATCH ? 900 : 500);
  return up.ok;
}

/** 误点开设置窗就自己关掉（顶条「≡」与「开战」紧邻，最容易点错）。 */
async function closeSettingsIfOpen(tag) {
  const s = await state();
  if (!s || !s.settings_open) return false;
  step("设置窗被误点开了 → 用鼠标点关闭", tag || "继续操作");
  const r = await send("close_settings");
  await sleep(900);
  if (!r.ok) note("关设置失败: " + (r.error || JSON.stringify(r.data)));
  return true;
}

/**
 * 点「开战」并**验证真的开打了**。
 * 顶条上「开战」和「≡」紧邻，偏移算错就会点到设置 —— 那种情况下
 * phase 不会变、settings_open 会变真，所以这两个信号就是判据。
 */
async function clickStartBattle() {
  const tries = [[0, 0], [60, 0], [120, 0], [30, 0], [90, 0], [0, 18], [0, -18]];
  for (const [dx, dy] of tries) {
    if (dx === 0 && dy === 0) {
      await clickNamed("开战");
    } else {
      await send("mouse_click", { x: 1284 + dx, y: 26 + dy });
    }
    await sleep(1100);
    const t = await state();
    if (!t) continue;
    if (t.phase_name === "BATTLE") return true;
    if (t.settings_open) await closeSettingsIfOpen("重试开战");
  }
  note("开战多次未成功（可能场上没船）");
  return false;
}

// ---- main menu ----
const DIFF_NAMES = ["simple", "normal", "hard", "inferno"];
async function menuStart() {
  const s = await state();
  if (!s || s.scene !== "menu") return;
  step("main menu: click Campaign", "left mode column");
  await clickNamed("Mode_campaign");
  await pace();
  const idx = DIFF ? Math.max(0, DIFF_NAMES.indexOf(DIFF)) : 0;
  // ⚠️⚠️ 关键：「▶ 开始X」按钮**不切换难度**！它用的是「当前选中的卡片」
  //    （_on_start_pressed 读 _pick[content_id]，默认 0 = 简单）。
  //    ⇒ 必须先点长条本体选中该难度，再点开始。否则永远在打简单。
  step("选中难度「" + ["简单", "普通", "困难", "炼狱"][idx] + "」", "点长条本体（不是开始按钮）");
  const map = await uiMap();
  const strips = (map && map.strips) || [];
  const strip = strips[idx];
  if (strip) {
    // 点长条上部（名字区），避开底部的开始按钮
    const sx = Math.round(strip.rect[0] + strip.rect[2] / 2);
    const sy = Math.round(strip.rect[1] + 40);
    await send("mouse_click", { x: sx + 60, y: sy });
    await sleep(1200);
    const chk = await state();
    if (chk && chk.difficulty_index !== idx) {
      note("难度没选上（现在是 " + chk.difficulty_index + "），重试");
      for (const dy of [30, 60, 20, 80, 100]) {
        await send("mouse_click", { x: sx + 60, y: strip.rect[1] + dy });
        await sleep(1000);
        const c2 = await state();
        if (c2 && c2.difficulty_index === idx) break;
      }
    }
    const ok = await state();
    note("当前难度下标 " + (ok ? ok.difficulty_index : "?"));
  }
  step("main menu: click Start-" + DIFF_NAMES[idx], "difficulty index " + idx);
  await clickNamed("开始" + ["简单", "普通", "困难", "炼狱"][idx]);
  await pace();
  for (let i = 0; i < 25; i++) {
    await sleep(500);
    const t = await state();
    if (!t) continue;
    if (t.scene === "intro") { step("skip intro cutscene", "no info in it"); await send("finish"); await sleep(900); }
    if (t.scene === "battle") return;
  }
}


// ---- 羁绊认知（决策核心）----
// 每组里每艘船只算 1 点，取命中的第一个标签（与 EveTraitTable.count 一致）。
const FACTION = ["艾玛", "加达里", "盖伦特", "米玛塔尔"];
const WEAPON = ["激光炮", "混合炮", "射弹炮", "导弹"];
const DEFENSE = ["甲抗", "盾抗"];
const TIERS = { faction: [2, 4], weapon: [3, 6], defense: [3, 6] };

function firstIn(traits, pool) {
  for (const t of traits || []) if (pool.includes(t)) return t;
  return "";
}

/** 统计舰队（field+bench）的三组计数。 */
function countTraits(ships) {
  const out = { faction: {}, weapon: {}, defense: {} };
  for (const g of ["faction", "weapon", "defense"]) {
    const pool = g === "faction" ? FACTION : g === "weapon" ? WEAPON : DEFENSE;
    for (const m of pool) out[g][m] = 0;
  }
  for (const sh of ships || []) {
    const tr = sh.traits || [];
    const f = firstIn(tr, FACTION); if (f) out.faction[f]++;
    const w = firstIn(tr, WEAPON); if (w) out.weapon[w]++;
    const d = firstIn(tr, DEFENSE); if (d) out.defense[d]++;
  }
  return out;
}

/** 某标签当前落在哪一档（返回 0 / 3 / 6 之类的阈值）。 */
function tierOf(group, name, n) {
  const t = TIERS[group] || [];
  let hit = 0;
  for (const v of t) if (n >= v) hit = v;
  return hit;
}

/**
 * 给一张商店卡打分：能不能把某组推上一档 > 同组已有最多 > 高费。
 * 返回 { score, reason }
 */
function scoreOffer(offer, counts) {
  let score = 0;
  const reasons = [];
  const groups = [
    { g: "faction", pool: FACTION, name: firstIn(offer.traits || [], FACTION) },
    { g: "weapon", pool: WEAPON, name: firstIn(offer.traits || [], WEAPON) },
    { g: "defense", pool: DEFENSE, name: firstIn(offer.traits || [], DEFENSE) },
  ];
  for (const it of groups) {
    if (!it.name) continue;
    const n = (counts[it.g] && counts[it.g][it.name]) || 0;
    const cur = tierOf(it.g, it.name, n);
    const next = tierOf(it.g, it.name, n + 1);
    if (next > cur) { score += 100; reasons.push(it.name + " 到档 " + next); }
    else { score += n * 3; if (n > 0) reasons.push(it.name + " 同组 " + n); }
  }
  score += (offer.cost || 1) * 2;
  return { score, reason: reasons.slice(0, 2).join(" + ") || "新体系" };
}


// ---- prep phase ----
async function prep(s) {
  const map = await uiMap();
  const cards = (map && map.shop_cards) || [];
  const slots = (map && map.bench_slots) || [];

  // 1) 买：先算羁绊，再按「能上档 > 同组已多 > 高费」排序（这是这个品类的核心决策）
  let coin = s.economy ? s.economy.coin : 0;
  const owned = [...(s.field || []), ...(s.bench || [])];
  const counts = countTraits(owned);
  const traitLine = ["faction", "weapon", "defense"]
    .map((g) => g.slice(0, 3) + ":" + Object.entries(counts[g]).filter(([, v]) => v > 0).map(([k, v]) => k + v).join("/"))
    .filter((x) => x.split(":")[1])
    .join("  ");
  if (traitLine) note("当前羁绊 " + traitLine);

  // ⚠️ 备战席只有 8 格；满了还买等于浪费（船会进不来 / 花钱打水漂）
  const benchUsed = (s.bench || []).length;
  const benchRoom = 8 - benchUsed;
  if (benchRoom <= 0) note("备战席已满，本轮不买船");

  const scored = cards
    .map((c) => {
      const offer = ((s.shop || {}).offers || [])[c.index];
      if (!offer || !offer.ship_key) return null;
      const sc = scoreOffer(offer, counts);
      return { c, offer, score: sc.score, reason: sc.reason };
    })
    .filter(Boolean)
    .sort((a, b) => b.score - a.score);

  let bought = 0;
  for (const it of scored) {
    if (bought >= benchRoom) break;
    if (it.offer.cost > coin - 2) continue;
    step("鼠标点商店第 " + it.c.index + " 张：" + it.offer.name,
      "◆" + it.offer.cost + " · " + it.reason + " · 剩 ◆" + (coin - it.offer.cost));
    await clickPath(it.c.path);
    await pace();
    coin -= it.offer.cost;
    bought++;
    // 买完立刻更新计数（后面的卡打分才准）
    const t = it.offer.traits || [];
    const f = firstIn(t, FACTION); if (f) counts.faction[f]++;
    const w = firstIn(t, WEAPON); if (w) counts.weapon[w]++;
    const d = firstIn(t, DEFENSE); if (d) counts.defense[d]++;
  }
  if (bought) note("共买入 " + bought + " 艘");

  // 1b) 买经验：星币 >= 12 且等级 < 6
  const lv = s.economy ? s.economy.level : 1;
  if (coin >= 12 && lv < 6) {
    step("鼠标点「加速等级」", "◆" + coin + " · Lv" + lv + " → Lv" + (lv + 1) + "（多一个上场位 + 更好的商店概率）");
    await clickNamed("加速等级");
    await pace();
    coin -= 4;
  }

  // 2) deploy: phased drag bench -> free cell
  const s2 = await state();
  const taken = new Set();
  for (const f of (s2.field || [])) {
    const m = /^\((\d+),\s*(\d+)\)$/.exec(String(f.cell || ""));
    if (m) taken.add(m[1] + ":" + m[2]);
  }
  const free = [];
  for (let r = 7; r <= 10; r++) for (let c = 0; c < 11; c++) {
    if (!taken.has(r + ":" + c)) free.push([r, c]);
  }
  const limit = s2.field_limit || 3;
  const bench = (s2.bench || []).length;
  for (let b = 0; b < bench && (s2.field || []).length + b < limit && b < free.length; b++) {
    const slot = slots[b];
    if (!slot) break;
    const ok = await phasedDrag(slot.rect, free[b][0], free[b][1], "drag bench " + b + " onto the board");
    await pace();
    if (!ok) break;
  }

  // 3) 开战：点完必须验证，没打成就是点到设置了（两按钮紧邻）
  const s3 = await state();
  step("鼠标点「开战」", ((s3.field) || []).length + " ship(s) on board");
  await clickStartBattle();
  await pace();
}

async function pickEvent(s) {
  const ev = s.event || {};
  if (ev.ship_pick_open) {
    // 选船：面板复用同一批 event_cards，选项按钮此时已隐藏
    //   ⇒ 只能按矩形点卡（点选项按钮会「找不到」然后死循环）。
    //   选**最贵**的那艘：同样的 +8% 攻击 / +15% 结构，基数越大收益越大。
    step("事件节点：选 1 艘船", "给费用最高的那艘");
    const map = await uiMap();
    const cards = (map && map.event_cards) || [];
    const costs = [...(s.field || []), ...(s.bench || [])].map((x) => x.cost || 1);
    let best = 0;
    for (let i = 1; i < costs.length && i < cards.length; i++) {
      if (costs[i] > costs[best]) best = i;
    }
    const card = cards[best] || cards[0];
    if (card) {
      await clickCardVerified(card, "事件节点：选 1 艘船");
    } else {
      note("没有可点的船卡");
    }
    await pace();
    return;
  }
  if (!ev.open) return;
  // 四选一：星币 > 经验 > 信标上限 > 其它（前期钱最值钱）
  const opts = (ev.options || []).filter((o) => !o.taken && o.id);
  if (!opts.length) return;
  const val = (o) => (o.coin || 0) * 100 + (o.xp || 0) * 50 + (o.beacon_max || 0) * 30 + (o.free_advanced_roll ? 10 : 0);
  const order = opts.map((o) => ({ o })).sort((a, b) => val(b.o) - val(a.o));
  const pick = order[0];
  // ⚠️ 事件卡是 PanelContainer，不是 Button ⇒ 不能按文字点，必须按矩形点。
  // ⚠️⚠️ 卡片下标必须按 **id 在完整 options 里的位置** 找，不能用「过滤后」的下标 ——
  //    已获取过的选项会被过滤掉，两者会错位（实测：选了要选船的增益却直接跳过）。
  const map = await uiMap();
  const cards = (map && map.event_cards) || [];
  const fullIdx = ((s.event || {}).options || []).findIndex((o) => o.id === pick.o.id);
  const card = (fullIdx >= 0 ? cards.find((c) => c.index === fullIdx) : null) || cards[0];
  step("事件节点四选一 → " + (pick.o.name || pick.o.id), "星币 > 经验 > 信标上限");
  if (card) {
    await clickCardVerified(card, "事件节点四选一");
  } else {
    await clickNamed(pick.o.name || "武器调校");
  }
  await pace();
}

/**
 * 点一张「卡」（PanelContainer，hover 验证不了）并**验证面板是否关闭**。
 * 事件窗 / 选船面板都靠这个判据 —— 面板还开着就是没点中，换偏移重试。
 */
async function clickCardVerified(card, tag) {
  const [cx, cy] = center(card.rect);
  const tries = [60, 0, 30, 90, 120, 15, 45, 75, 105, 135];
  for (const dx of tries) {
    await send("mouse_click", { x: cx + dx, y: cy });
    await sleep(1100);
    const t = await state();
    if (!t) continue;
    const stillOpen = (t.event || {}).open || (t.event || {}).ship_pick_open;
    if (!stillOpen) return true;
    if (t.settings_open) await closeSettingsIfOpen(tag);
  }
  note(tag + "：多次点击后面板仍未关闭");
  return false;
}

/** 打捞能捞的就捞（半价换高费船），捞不起就点「确定放弃」。全走鼠标。 */
async function handleDialog(s) {
  const sal = s.salvage || {};
  const map0 = await uiMap();
  const btns = (map0 && map0.buttons) || [];
  // 结果页的打捞按钮文案含「打捞」；还剩货位就点一艘
  const salvageBtns = btns.filter((b) => /打捞/.test(b.name) && b.name !== "打捞");
  const affordable = (sal.items || []).filter((it) => it.price <= (sal.coin || 0));
  if (sal.state === "list" && affordable.length && salvageBtns.length) {
    step("打捞残骸：" + affordable[0].name, "半价 ◆" + affordable[0].price + " · 剩 ◆" + ((sal.coin || 0) - affordable[0].price));
    await clickPath(salvageBtns[0].path);
    await pace();
    return;
  }
  step("确认框：点「确定放弃」", "残骸捞不起了（◆" + (sal.coin || 0) + "）");
  const ok = await clickNamed("确定放弃");
  if (!ok.ok) await clickNamed("确定");
  await pace();
}


async function main() {
  if (WATCH) console.log("[DEMO] pausing " + DELAY + "ms per step, milestones only, all real mouse input");
  const results = [];
  for (let round = 1; round <= ROUNDS; round++) {
    stepNo = 0;
    console.log("");
    console.log("=== round " + round + " / " + ROUNDS + " ===");
    const r = await playOneRound();
    results.push(r);
    if (round < ROUNDS) {
      await send("back_to_menu");
      await sleep(2500);
    }
  }
  const cleared = results.filter((x) => x.cleared).length;
  console.log("");
  console.log("=== sweep summary ===");
  console.log("runs " + results.length + " · cleared " + cleared +
    " · clear rate " + (100 * cleared / Math.max(1, results.length)).toFixed(1) + "%");
  for (const r of results) {
    console.log("  - " + r.difficulty + " -> " + r.ending +
      " · node " + r.node + "/15 · beacon " + r.beacon + " · " + r.seconds + "s");
  }
}

async function playOneRound() {
  const t0 = Date.now();
  const rec = { difficulty: DIFF || "simple", ending: "", node: 0, beacon: 0, cleared: false, seconds: 0 };
  await menuStart();
  let stuckKey = "", stuckN = 0;
  let guard = 0;
  while (guard++ < 900) {
    const s = await state();
    if (!s) { await sleep(400); continue; }
    const node = s.node ? s.node.index : 0;
    // ⓪ 误开的设置窗优先关掉：它开着的时候其它点击全被吃掉
    await closeSettingsIfOpen();

    // ⓪ 确认框优先：弹着的时候别的动作都不生效（实测反复点「继续」只会把它再弹一次）
    if ((s.dialog || {}).any_open) {
      await handleDialog(s);
      await sleep(600);
      continue;
    }

    const key = s.phase_name + ":" + node;
    if (key === stuckKey) stuckN++; else { stuckKey = key; stuckN = 0; }
    if (stuckN === 18) {
      console.log("WARN stuck at " + key + ", trying dialog / continue");
      await send("dialog_confirm");
      await clickNamed("继续 · 下一节点");
    }
    if (stuckN > 40) {
      console.log("ERROR stuck at " + key + ", giving up");
      rec.ending = "STUCK"; rec.node = node; rec.beacon = s.economy.beacon;
      rec.seconds = Math.round((Date.now() - t0) / 1000);
      return rec;
    }

    switch (s.phase_name) {
      case "PREP":
        if ((s.event || {}).open || (s.event || {}).ship_pick_open) await pickEvent(s);
        else { step("node " + node + "/15 - prep", "enemy " + (s.enemy || []).length + " ship(s)"); await prep(s); }
        break;
      case "BATTLE":
        step("battle - waiting", "simulated " + Math.round((s.battle || {}).elapsed || 0) + "s");
        await pace();
        await sleep(700);
        break;
      case "RESOLVE":
        step("resolve page: click Continue", "beacon " + s.economy.beacon);
        await clickNamed("继续 · 下一节点");
        await pace();
        break;
      case "ENDING":
        step("run over: " + s.ending_name, "node " + node + " - beacon " + s.economy.beacon);
        rec.ending = s.ending_name; rec.node = node; rec.beacon = s.economy.beacon;
        rec.cleared = s.ending_name === "CLEARED";
        rec.seconds = Math.round((Date.now() - t0) / 1000);
        return rec;
      default:
        await sleep(400);
    }
    if (node >= MAX_NODES && s.phase_name !== "BATTLE") {
      step("reached node " + MAX_NODES, "done");
      rec.ending = "CLEARED"; rec.node = node; rec.beacon = s.economy.beacon;
      rec.cleared = true; rec.seconds = Math.round((Date.now() - t0) / 1000);
      return rec;
    }
    await sleep(WATCH ? 200 : 120);
  }
}

main().then(() => { sock.end(); process.exit(0); });
