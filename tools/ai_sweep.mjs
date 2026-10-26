#!/usr/bin/env node
/**
 * EVE 自走棋 —— AI 难度扫荡 + 通关率报表（tools/ai_sweep.mjs）
 *
 * 自己轮换四个难度（简单 / 普通 / 困难 / 炼狱），每个难度打若干整轮，
 * 打完一轮（15 节点通关或信标归零撤离）就回主菜单换下一个难度，
 * 全部跑完后写报表：
 *
 *   tools/ai_runs/runs.csv     逐局原始记录
 *   tools/ai_runs/report.md    按难度汇总的报表
 *
 * 胜率口径（用户 2026-10-26 定案）：**通关率 = 打到 15 节点的局数 / 总局数**。
 * 单场战斗胜负另列一栏供参考，但不是 headline。
 *
 * 演示模式（给人看）：
 *   node tools/ai_sweep.mjs --demo
 *   node tools/ai_sweep.mjs --demo --demo-delay 2000
 */
import net from "node:net";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const PORT = Number(process.env.AI_PORT || 9081);
const HOST = process.env.AI_HOST || "127.0.0.1";
// ⚠️ 输出目录必须相对**脚本自身**解析：按 cwd 算的话，从仓库根跑一次
//    报表就飞到 F:\evezzq\tools\ai_runs 去了（实测踩过）。
const HERE = path.dirname(fileURLToPath(import.meta.url));
const OUT_DIR = path.join(HERE, "ai_runs");

/** 四个难度：下标 ↔ id ↔ 中文名（与主菜单 EveCampaignTiers.DIFFICULTIES 对齐）。 */
const DIFFICULTIES = [
  { index: 0, id: "simple", name: "简单" },
  { index: 1, id: "normal", name: "普通" },
  { index: 2, id: "hard", name: "困难" },
  { index: 3, id: "inferno", name: "炼狱" },
];

const argv = process.argv.slice(2);
const arg = (k, d) => {
  const i = argv.indexOf("--" + k);
  return i >= 0 && argv[i + 1] !== undefined ? argv[i + 1] : d;
};
const ROUNDS = Math.max(1, Number(arg("rounds", 1)));
const ONLY = arg("difficulty", "");
const MAX_NODES = Number(arg("nodes", 15));
const DEMO = argv.includes("--demo");
const DEMO_DELAY = Number(arg("demo-delay", 2500));
const VERBOSE = argv.includes("--verbose");   // 不再被 demo 连带打开
const NO_SHOTS = argv.includes("--no-shots");

const plan = ONLY
  ? DIFFICULTIES.filter((d) => d.id === ONLY || d.name === ONLY || String(d.index) === ONLY)
  : DIFFICULTIES;
if (!plan.length) { console.error("未知难度:", ONLY); process.exit(2); }

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ── 演示用的分步输出 ────────────────────────────────────────────
let stepNo = 0;
/**
 * 打一条步骤。演示模式下带序号 + 理由，并且每步之间停一拍，
 * 让人能跟上「AI 现在在干什么、为什么这么干」。
 */
function step(what, why) {
  stepNo++;
  const no = String(stepNo).padStart(2, "0");
  if (DEMO) {
    console.log("  " + no + ". " + what + (why ? "   ← " + why : ""));
  }
}

/** 细节：只有 --verbose 才打印，演示模式默认闭嘴。 */
function detail(what, why) {
  if (!VERBOSE) return;
  console.log("      · " + what + (why ? " ← " + why : ""));
}
async function pace() {
  if (DEMO) await sleep(DEMO_DELAY);
}
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);

// ── 桥 ──────────────────────────────────────────────────────────
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
      } catch { log("bad reply", line); }
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
    setTimeout(() => { if (pending.delete(id)) resolve({ ok: false, error: "client timeout" }); }, 25000);
  });
}
const state = async () => {
  const r = await send("state");
  return r.ok ? (r.data || {}) : null;
};

// ── 一局的记录 ──────────────────────────────────────────────────
const runs = [];

async function playRun(diff, roundNo) {
  const t0 = Date.now();
  const rec = {
    difficulty: diff.name, difficulty_id: diff.id, round: roundNo,
    cleared: false, ending: "", nodes: 0, wins: 0, losses: 0,
    beacon: 0, level: 1, field: 0, seconds: 0,
  };
  let lastNode = 0;
  let guard = 0;
  let countedFinish = false;
  let ffDone = false;
  let atEndTicks = 0;
  // 无进展保护：同一个 (phase, node) 连续停留这么久还没变化 ⇒ 报警。
  // 病象（2026-10-26 实测）：打捞门面把拒绝吞成 ok，机器人对着同一个下标
  // 无限重试，而「继续」又一直弹确认框 ⇒ 卡了 454 秒才被守卫上限捞出来。
  let stuckKey = "";
  let stuckTicks = 0;

  while (guard++ < 1200) {
    const s = await state();
    if (!s) { log("读不到状态，放弃本局"); break; }
    const node = s.node ? s.node.index : 0;
    if (node > lastNode) {
      lastNode = node; rec.nodes = node;
      const secs = s.node ? s.node.battle_seconds : 0;
      step("进入节点 " + node + "/15",
        "敌 " + (s.enemy || []).length + " 艘 · 时限 " + secs + "s");
    }
    rec.beacon = s.economy ? s.economy.beacon : rec.beacon;
    rec.level = s.economy ? s.economy.level : rec.level;
    rec.field = (s.field || []).length;

    // ── 无进展检测 ──
    const key = s.phase_name + ":" + node;
    if (key === stuckKey) stuckTicks++; else { stuckKey = key; stuckTicks = 0; }
    if (stuckTicks === 25) {
      log("⚠️ 在 " + key + " 停留过久（约 " + Math.round(stuckTicks * 0.35) + "s），强制推一把");
      // 先试着应答确认框，再试推进
      await send("dialog_confirm");
      await send("result_next");
    }
    if (stuckTicks > 60) {
      log("❌ 在 " + key + " 彻底卡住，放弃本局");
      rec.ending = "STUCK";
      rec.seconds = Math.round((Date.now() - t0) / 1000);
      return rec;
    }

    // ⓪ 确认框优先：弹着的时候别的指令都不会生效
    if ((s.dialog || {}).any_open) {
      const sal = s.salvage || {};
      const afford = (sal.items || []).some((it) => it.price <= (sal.coin || 0));
      if (sal.state === "list" && afford) {
        await salvageAll(s);
      } else {
        step("确认「放弃打捞」并继续", "残骸捞不起了（◆" + (sal.coin || 0) + "）");
        const r = await send("dialog_confirm");
        if (!r.ok) log("确认框失败");
      }
      await pace();
      await sleep(350);
      continue;
    }

    // 战斗结果：只在 finished 的那一帧计一次
    if (s.battle && !s.battle.finished) countedFinish = false;
    if (s.battle && s.battle.finished && !countedFinish) {
      countedFinish = true;
      if (s.battle.winner_team === 0) rec.wins++; else rec.losses++;
      step("节点 " + node + " 战斗结束：" + (s.battle.winner_team === 0 ? "胜" : "负"),
        "信标 " + rec.beacon + " · 累计 " + rec.wins + "胜" + rec.losses + "负");
    }

    if (s.phase_name !== "BATTLE") ffDone = false;

    switch (s.phase_name) {
      case "PREP":
        if ((s.event || {}).open || (s.event || {}).ship_pick_open) await pickEvent(s);
        else await prepAndFight(s);
        break;
      case "BATTLE":
        // 快进：只要战斗还没结束就继续推。
        // ⚠️ 不能只推「场景计时器剩余时间」—— 首领战双方都有后勤舰在修，
        //    会打成僵局，按设计要到 3 倍时限才按剩余战力收场
        //    （EveBattleSimulator._check_outcome 的 HARD_STOP_MULT）。
        //    只推一截的话机器人会在这里干等十几分钟（实测踩过）。
        if (s.battle && !s.battle.finished) {
          const left = s.timer_left > 0 ? s.timer_left : 20;
          const push = Math.min(90, Math.max(30, left + 10));
          step("快进战斗 " + push + " 秒", "已模拟 " + Math.round(s.battle.elapsed) + "s · 场景剩余 " + left + "s");
          await send("fast_forward", { seconds: push });
        }
        await pace();
        await sleep(250);
        break;
      case "RESOLVE":
        await salvageAll(s);
        step("结算 → 下一节点", "信标 " + rec.beacon);
        await send("result_next");
        await pace();
        await sleep(850);
        break;
      case "ENDING":
        rec.cleared = s.ending_name === "CLEARED";
        rec.ending = s.ending_name;
        rec.nodes = node;
        if (!NO_SHOTS) await send("screenshot", { name: `sweep_${diff.id}_${roundNo}_end` });
        step("本局结束：" + rec.ending,
          "节点 " + node + "/15 · 信标 " + rec.beacon + " · " + rec.wins + "胜" + rec.losses + "负");
        rec.seconds = Math.round((Date.now() - t0) / 1000);
        return rec;
      default:
        await sleep(400);
    }

    // 兜底：节点打到上限就收工。⛔ 不能无条件记通关 ——
    // 最后一节点打输了也是「到 15」，要看最后一场战斗的胜负。
    if (node >= MAX_NODES && s.phase_name !== "BATTLE") {
      atEndTicks++;
      if (atEndTicks > 20) {
        const wonLast = rec.wins + rec.losses > 0 && rec.wins >= rec.losses;
        rec.cleared = wonLast;
        rec.ending = wonLast ? "CLEARED" : "UNFINISHED";
        rec.seconds = Math.round((Date.now() - t0) / 1000);
        step("节点已到 " + MAX_NODES + " 且没有后续 ⇒ 记 " + rec.ending,
          "末场胜=" + wonLast);
        return rec;
      }
    } else {
      atEndTicks = 0;
    }
    await sleep(110);
  }
  rec.seconds = Math.round((Date.now() - t0) / 1000);
  log("步数上限，本局强制收工");
  return rec;
}

async function salvageAll(s) {
  const sal = s.salvage || {};
  if (sal.state !== "list") return;
  let got = 0;
  for (const it of sal.items || []) {
    if (it.price <= (sal.coin || 0)) {
      const r = await send("salvage", { index: it.idx });
      if (r.ok) { got++; detail("打捞 " + it.name, "−◆" + it.price); }
      else detail("打捞被拒：" + it.name, r.data ? r.data.reason : r.error);
    }
  }
}

async function pickEvent(s) {
  const ev = s.event || {};
  if (ev.ship_pick_open) {
    step("事件节点：选 1 艘船", "第 0 艘");
    await send("event_ship", { index: 0 });
    return;
  }
  if (!ev.open) return;
  const opts = (ev.options || []).filter((o) => !o.taken && o.id);
  if (!opts.length) return;
  const score = (o) => (o.coin ? 100 : 0) + (o.xp ? 50 : 0) + (o.beacon_max ? 30 : 0);
  opts.sort((a, b) => score(b) - score(a));
  const pick = opts[0];
  step("事件节点四选一 → " + (pick.name || pick.id),
    "偏好：星币 > 经验 > 信标上限");
  await send("event_choose", { id: String(pick.id) });
}

async function prepAndFight(s) {
  let coin = s.economy ? s.economy.coin : 0;
  let benchCount = (s.bench || []).length;
  const bought = [];
  // ① 买：留 2 ◆ 刷新费，别一次烧光
  for (const o of (s.shop && s.shop.offers) || []) {
    if (!o || !o.ship_key) continue;
    if (o.cost <= coin - 2 && benchCount < 8) {
      const r = await send("buy", { index: o.index });
      if (r.ok) {
        coin -= o.cost; benchCount++;
        bought.push(o.name + "◆" + o.cost);
        detail("买商店第 " + o.index + " 张：" + o.name, "◆" + o.cost + " · 剩 ◆" + coin);
      }
    }
  }
  // ② 钱多就买经验
  const st = await state();
  const cur = st || {};
  if ((cur.economy ? cur.economy.coin : 0) >= 12 && (cur.economy ? cur.economy.level : 1) < 6) {
    await send("levelup");
    step("买经验（4◆）", "◆" + (cur.economy ? cur.economy.coin : 0) + " → 等级上限更高");
  }
  // ③ 上场：跳过已占用格
  const st2 = await state();
  const s2 = st2 || {};
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
  let deployed = 0;
  const limit = s2.field_limit || 3;
  const onField = (s2.field || []).length;
  for (let b = 0; b < (s2.bench || []).length && onField + b < limit; b++) {
    const cell = free[ci++];
    if (!cell) break;
    const r = await send("deploy", { bench: b, row: cell[0], col: cell[1] });
    if (r.ok) deployed++;
    detail("备战席 " + b + " 上场 → 第" + cell[0] + "行第" + cell[1] + "列",
      "我方部署区 = 行 7~10 · 上限 " + limit + " 艘");
  }
  if (bought.length) step("商店买入 " + bought.length + " 艘", bought.join(" / "));
  if (deployed > 0) step("布阵：上场 " + deployed + " 艘", "我方区行 7~10 · 上限 " + limit + " 艘");
  // ④ 开战（布阵后重读一次，报出来的上场数才是真的）
  const st3 = await state();
  const onFieldNow = ((st3 || {}).field || []).length;
  const fr = await send("start_battle");
  if (!fr.ok) step("开战被拒", fr.error || JSON.stringify(fr.data));
  else step("开战", "上场 " + onFieldNow + " 艘 · 对 " + (((st3 || {}).enemy) || []).length + " 艘");
}

/** 回主菜单并选下一个难度。 */
async function toMenuAndPick(diff) {
  for (let i = 0; i < 20; i++) {
    const s = await state();
    if (!s) { await sleep(500); continue; }
    if (s.scene === "menu") break;
    if (s.scene === "intro") { await send("finish"); await sleep(600); continue; }
    step("退回主菜单", "当前在 " + s.scene + " 场景");
    await send("back_to_menu");
    await sleep(900);
  }
  await send("select_mode", { index: 2 });
  await send("select_difficulty", { index: diff.index });
  const s = await state();
  const ok = s && s.difficulty_index === diff.index;
  step("主菜单选难度 → 「" + diff.name + "」", "难度下标 " + diff.index + (ok ? "" : "（切换存疑！）"));
  return ok;
}

// ── 报表 ────────────────────────────────────────────────────────
function writeReports() {
  fs.mkdirSync(OUT_DIR, { recursive: true });
  const csv = path.join(OUT_DIR, "runs.csv");
  const head = "timestamp,difficulty,difficulty_id,round,cleared,ending,nodes,wins,losses,beacon,level,field,seconds";
  const rows = runs.map((r) => [
    new Date().toISOString(), r.difficulty, r.difficulty_id, r.round,
    r.cleared ? 1 : 0, r.ending, r.nodes, r.wins, r.losses,
    r.beacon, r.level, r.field, r.seconds,
  ].join(","));
  fs.writeFileSync(csv, [head, ...rows].join("\n") + "\n");

  const byDiff = new Map();
  for (const r of runs) {
    if (!byDiff.has(r.difficulty)) byDiff.set(r.difficulty, []);
    byDiff.get(r.difficulty).push(r);
  }
  const total = runs.length;
  const totalCleared = runs.filter((r) => r.cleared).length;
  const L = [];
  L.push("# AI 自走棋通关率报表");
  L.push("");
  L.push(`生成时间：${new Date().toLocaleString("zh-CN")}  ·  共 ${total} 局`);
  L.push("");
  L.push("## 总览");
  L.push("");
  L.push(`**总通关率 ${(100 * totalCleared / total).toFixed(1)}%**（通关 ${totalCleared} / 共 ${total}）`);
  L.push("");
  L.push("## 按难度");
  L.push("");
  L.push("| 难度 | 局数 | 通关 | 撤离 | **通关率** | 平均节点 | 平均信标 | 战斗胜/负 |");
  L.push("| --- | --- | --- | --- | --- | --- | --- | --- |");
  for (const [name, list] of byDiff) {
    const n = list.length;
    const cleared = list.filter((r) => r.cleared).length;
    const evac = n - cleared;
    const w = list.reduce((a, r) => a + r.wins, 0);
    const l = list.reduce((a, r) => a + r.losses, 0);
    const nodes = (list.reduce((a, r) => a + r.nodes, 0) / n).toFixed(1);
    const beacon = (list.reduce((a, r) => a + r.beacon, 0) / n).toFixed(1);
    L.push(`| ${name} | ${n} | ${cleared} | ${evac} | **${(100 * cleared / n).toFixed(1)}%** | ${nodes} | ${beacon} | ${w}/${l} |`);
  }
  L.push("");
  L.push("## 逐局明细");
  L.push("");
  L.push("| # | 难度 | 轮次 | 结局 | 节点 | 战斗胜/负 | 信标 | 等级 | 上场 | 用时 |");
  L.push("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |");
  runs.forEach((r, i) => {
    L.push(`| ${i + 1} | ${r.difficulty} | ${r.round} | ${r.ending || "—"} | ${r.nodes} | ${r.wins}/${r.losses} | ${r.beacon} | ${r.level} | ${r.field} | ${r.seconds}s |`);
  });
  L.push("");
  L.push("> 口径：**通关率 = 打到 15 节点的局数 / 总局数**。");
  L.push("> 撤离 = 信标归零。战斗胜/负按单节点战斗计（不含事件节点），仅供参考。");
  L.push("> 原始数据：`tools/ai_runs/runs.csv`");
  const md = path.join(OUT_DIR, "report.md");
  fs.writeFileSync(md, L.join("\n") + "\n");
  return { csv, md };
}

// ── 主流程 ──────────────────────────────────────────────────────
async function main() {
  if (DEMO) {
    log("【演示模式】每一步都会说明在做什么、为什么；每步之间停 " + DEMO_DELAY + "ms");
  }
  log("扫荡启动：", plan.map((d) => d.name).join(" / "), "× ", ROUNDS, "轮");
  for (const diff of plan) {
    for (let round = 1; round <= ROUNDS; round++) {
      stepNo = 0;
      step("── " + diff.name + " · 第 " + round + " 轮 ──", "共 " + ROUNDS + " 轮");
      const ok = await toMenuAndPick(diff);
      if (!ok) { log("跳过这一局（难度没选上）"); continue; }
      await send("start");
      for (let i = 0; i < 6; i++) {
        const s = await state();
        if (!s || s.scene !== "intro") break;
        step("跳过开场剧情", "片头没有信息量");
        await send("finish");
        await sleep(500);
      }
      const rec = await playRun(diff, round);
      runs.push(rec);
      await toMenuAndPick(diff);
    }
  }
  const out = writeReports();
  log("报表已生成：", out.md, "·", out.csv);
  console.log("\n" + fs.readFileSync(out.md, "utf8"));
}

main().then(() => { sock.end(); process.exit(0); });
