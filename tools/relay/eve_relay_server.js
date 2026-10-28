// EVE 自走棋 · UDP 中转服务器（Node 版，部署到 VPS 用）
//
// 用法：  node eve_relay_server.js [port]        （默认 27100）
//        PORT=27100 node eve_relay_server.js
//
// 协议与 GDScript 版（tools/relay_server.gd）完全一致：
//   [EV][8 字节房间码][1 字节身份 0=房主 1=加入方][ENet 原始数据报]
//
// 只做：按房间把两端 UDP 包互转 / 记录地址 / 清理闲置房间。
// 不解析游戏数据、不落盘、不断言任何游戏规则。
//
// ⚠️ 放行防火墙：  ufw allow 27100/udp     （云厂商安全组也要放行同样端口）

const dgram = require('dgram');

const HEADER = 11;
const ROOM_TTL_MS = 60000;
const CLEAN_EVERY_MS = 15000;

const port = parseInt(process.argv[2] || process.env.PORT || '27100', 10);
const sock = dgram.createSocket('udp4');
const rooms = new Map(); // code -> { eps: [null, null], last: number }

let relayed = 0;

sock.on('message', (buf, rinfo) => {
  if (buf.length < HEADER || buf[0] !== 0x45 || buf[1] !== 0x56) return;
  const code = buf.slice(2, 10).toString('ascii');
  const side = buf[10] & 1;
  let room = rooms.get(code);
  if (!room) {
    room = { eps: [null, null], last: 0 };
    rooms.set(code, room);
  }
  room.eps[side] = { ip: rinfo.address, port: rinfo.port };
  room.last = Date.now();
  const other = room.eps[side ^ 1];
  if (!other) return;
  sock.send(buf, other.port, other.ip);
  relayed++;
});

sock.on('error', (err) => {
  console.error('[relay] socket error:', err.message);
  process.exit(1);
});

sock.bind(port, '0.0.0.0', () => {
  console.log(`[relay] listening udp ${port}`);
});

setInterval(() => {
  const now = Date.now();
  for (const [code, room] of rooms) {
    if (now - room.last >= ROOM_TTL_MS) rooms.delete(code);
  }
  const mem = process.memoryUsage().rss / 1048576;
  console.log(`[relay] rooms=${rooms.size} relayed=${relayed} rss=${mem.toFixed(1)}MB`);
}, CLEAN_EVERY_MS);

process.on('SIGINT', () => {
  console.log('[relay] bye');
  sock.close();
  process.exit(0);
});
