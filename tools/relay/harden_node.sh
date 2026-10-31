#!/bin/sh
# =============================================================================
#  分发节点加固（幂等，可在服务器上反复执行）
#
#  背景（2026-10-30）：
#    0.14.10 发到玩家群之后，作者担心「有人拿到端口后 DDoS」。
#    实测当天服务器是空闲的（3 秒采样入站 2.4 KB/s、出站 2.8 KB/s，
#    estab 连接 4 条），唯一在碰 80 的是 Google Cloud 段的自动扫描器
#    （35.210.17.107），属于互联网常态，不是定向攻击。
#
#    但顺手查出两处**真实**问题：
#      1. Caddy 原来配的是 `file_server browse` ⇒ 任何人可以直接列出
#         /update/pck/ 下有什么文件（信息泄露，等于把包地址告诉扫描器）。
#      2. 80 端口没有任何限流 ⇒ 只要有人开 20~30 个连接同时拉 6 MB 的 pck，
#         4 Mbps 出网带宽立刻打满，正常玩家全部卡死。这不需要 DDoS，
#         一个脚本小子就够，甚至「发版瞬间几十个玩家同时更新」都会这样。
#
#  做了三件事：
#    · Caddy：关目录浏览 / 只许 GET+HEAD / 抹掉 Server 头 / 加访问日志
#    · iptables：单 IP 并发 24 条、单 IP 新建 40/s、单 IP UDP 300/s
#    · systemd：开机自动恢复上面这些规则（否则重启即失效）
#
#  ⚠️ 参数怎么定的（改之前先想清楚，别拍脑袋）：
#    · 并发 24：一个客户端正常只开 1~2 条连接（HTTP/1.1 keep-alive）。
#      24 足够容纳同一 NAT 出口下的十几个玩家，又能挡住并发下载刷带宽。
#    · 40/s 新建：正常玩家拉一次清单就一条请求，40/s 已经是 20 倍余量。
#    · UDP 300/s：中继是回合制同步，单客户端实测每秒几十包；300/s 留足余量。
#    ⚠️ 全部按**源 IP** 分桶。运营商 CGNAT 下多个玩家可能共用出口 IP，
#       所以这三个值不能往小调。
#
#  用法：
#      sudo sh harden_node.sh          # 应用 iptables 规则（Caddy 部分需手工覆盖配置）
# =============================================================================
set -u

# ── 1) iptables 限流（幂等：先删后插）────────────────────────────────
R_CONN='-p tcp --dport 80 -m connlimit --connlimit-above 24 --connlimit-mask 32 -j REJECT --reject-with tcp-reset'
R_HTTP='-p tcp --dport 80 -m hashlimit --hashlimit-name h80 --hashlimit-above 40/sec --hashlimit-burst 80 --hashlimit-mode srcip --hashlimit-htable-expire 30000 --hashlimit-htable-size 8192 -j DROP'
R_UDP='-p udp --dport 27100 -m hashlimit --hashlimit-name hudp --hashlimit-above 300/sec --hashlimit-burst 600 --hashlimit-mode srcip --hashlimit-htable-expire 20000 --hashlimit-htable-size 16384 -j DROP'
# 22 端口：挡 SSH 爆破。
#  ⚠️ 为什么不直接把 sshd 改成「禁密码 + 禁 root 直连」——自动化通道做不到，
#     运维接口对 /etc/ssh 与 sshd 相关命令一律 AccessDeny。这是平台**故意**
#     的保护（防止把用户锁在自己机器外面），不该想办法绕过。
#     所以退一步，在网络层把爆破速率压死：正常登录一次只几条连接，
#     爆破脚本每 IP 每分钟几百次，6/min 足够把它拖死而我们毫无感觉。
#  ✅ 真正禁密码登录的命令见 docs/联机与热更部署.md 末尾（需本人手工执行）。
R_SSH_CONN='-p tcp --dport 22 -m connlimit --connlimit-above 6 --connlimit-mask 32 -j REJECT --reject-with tcp-reset'
R_SSH_RATE='-p tcp --dport 22 -m hashlimit --hashlimit-name h22 --hashlimit-above 6/min --hashlimit-burst 8 --hashlimit-mode srcip --hashlimit-htable-expire 300000 --hashlimit-htable-size 8192 -j DROP'

# ⚠️ 变量传给 iptables 时**不要加引号**：加了引号整个字符串会作为单个参数
#    传进去，iptables 报 `unknown protocol " tcp --dport 80 -m connlimit..."`。
for R in "$R_CONN" "$R_HTTP" "$R_UDP" "$R_SSH_CONN" "$R_SSH_RATE"; do
  iptables -D INPUT $R 2>/dev/null
done

iptables -I INPUT 1 $R_CONN
iptables -I INPUT 2 $R_HTTP
iptables -I INPUT 3 $R_UDP
iptables -I INPUT 4 $R_SSH_CONN
iptables -I INPUT 5 $R_SSH_RATE

echo "✓ iptables 限流已应用（5 条）"

# ── 2) 开机自启（否则重启一次全丢，而且很难发现）─────────────────────
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cat > /etc/systemd/system/eve-firewall.service <<EOF
[Unit]
Description=EVE AutoChess ingress rate limits
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/eve-firewall.sh

[Install]
WantedBy=multi-user.target
EOF

if [ "$SELF" != "/usr/local/sbin/eve-firewall.sh" ] && [ -f "$SELF" ]; then
  cp -f "$SELF" /usr/local/sbin/eve-firewall.sh 2>/dev/null && chmod 755 /usr/local/sbin/eve-firewall.sh
fi

systemctl daemon-reload
systemctl enable --now eve-firewall >/dev/null 2>&1
echo "✓ eve-firewall.service 已设为开机自启"

# ── 3) Caddyfile：见 docs/联机与热更部署.md 里的完整配置 ──────────────
#  ⚠️ 这里不自动覆盖 Caddyfile —— 覆盖错了站点会直接 502。
#     手写的那份在服务器的 /etc/caddy/Caddyfile，备份在 Caddyfile.bak2。
#  ⚠️ 日志**不能**写 /var/log/caddy/：caddy 用户在那里没有写权限，
#     reload 会失败（旧配置继续跑，所以表面上「没坏」，很能骗人）。
#     实际写 /var/lib/caddy/eve-access.log。
echo ""
echo "iptables 部分完成。Caddy 加固请参照 docs/联机与热更部署.md 手写："
echo "  · 关掉 file_server 的 browse"
echo "  · 只允许 GET/HEAD（其余 405）"
echo "  · header 抹掉 Server"
echo "  · 日志输出到 /var/lib/caddy/eve-access.log（不是 /var/log/caddy/）"
