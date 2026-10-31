#!/usr/bin/env bash
# EVE 自走棋 · 中继服务器一键部署（Ubuntu 22.04/24.04）
#
# 用法（在 VPS 上，root 或 sudo）：
#   1. 先把本文件和 eve_relay_server.js 传上去（scp 或面板上传）
#   2. sudo bash setup_vps.sh
#
# 完成后：
#   - 中继以 systemd 服务常驻，开机自启，监听 UDP 27100
#   - 查看状态：  systemctl status eve-relay
#   - 查看日志：  journalctl -u eve-relay -f
#   - 端口对齐：  ⛔ 客户端 net.cfg 里必须写 `服务器IP:27100`，端口与此脚本一致
set -euo pipefail

PORT=27100
DIR=/opt/eve-relay

# ── 1. Node.js（Ubuntu 自带源足够，中继零依赖） ──
if ! command -v node >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y nodejs
fi

# ── 2. 部署文件 ──
mkdir -p "$DIR"
cp "$(dirname "$0")/eve_relay_server.js" "$DIR/"

# ── 3. 防火墙（云控制台的安全组还要单独放行 UDP $PORT！） ──
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  ufw allow ${PORT}/udp
fi

# ── 4. systemd 常驻 ──
cat >/etc/systemd/system/eve-relay.service <<EOF
[Unit]
Description=EVE AutoChess UDP relay
After=network.target

[Service]
ExecStart=/usr/bin/node ${DIR}/eve_relay_server.js ${PORT}
Restart=always
RestartSec=3
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=${DIR}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now eve-relay
sleep 1
systemctl --no-pager status eve-relay | head -n 8
echo "==> 部署完成。别忘了到云控制台安全组/防火墙放行 UDP ${PORT}"
