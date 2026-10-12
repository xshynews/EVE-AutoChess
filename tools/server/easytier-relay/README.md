# 自建 EasyTier 会合 / 中继节点

游戏内置的会合节点（`scripts/net/eve_relay_list.gd`）目前都是第三方公益节点，随时可能关站或限速。
自建一个节点后，联机的可用性就不再依赖别人。

节点只做两件事：

- **会合**：玩家互相交换地址，然后尝试 P2P 直连；
- **中继**：直连打洞失败时转发流量。

节点不保存任何数据，也不参与游戏逻辑。

## 机器要求

- 一台有公网 IP 的 Linux 服务器，1 核 1G 即可。斗地主每局流量很小，中继时每个房间也只有几 KB/s。
- 放行 TCP 与 UDP 11010 端口（云服务器还要在控制台的安全组里放行）。
- 国内云服务器只用 IP + 非 80/443 端口时，通常不涉及网站备案；正式上线前请按所用云厂商的规定确认。

## 部署

```bash
# 1. 下载与游戏内置内核同版本的 Linux 版（版本号见 tools/pipeline/_fetch_easytier.py 的 VERSION）
#    https://github.com/EasyTier/EasyTier/releases
sudo mkdir -p /opt/easytier
sudo unzip easytier-linux-x86_64-v2.6.4.zip -d /opt/easytier
sudo mv /opt/easytier/easytier-linux-x86_64/* /opt/easytier/
sudo chmod +x /opt/easytier/easytier-core

# 2. 用独立的低权限用户运行
sudo useradd --system --no-create-home --shell /usr/sbin/nologin easytier

# 3. 安装并启动服务
sudo cp easytier-relay.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now easytier-relay

# 4. 查看状态
systemctl status easytier-relay
journalctl -u easytier-relay -f
```

## 关键参数

| 参数 | 作用 |
|---|---|
| `--no-tun` | 节点本身不需要虚拟网卡 |
| `-l tcp://0.0.0.0:11010` / `-l udp://...` | 对外监听，玩家的内核经 `-p` 连到这里 |
| `--relay-network-whitelist "eve-ddz-*"` | 只为本游戏的房间网络转发数据（网络名前缀见 `eve_room_code.gd` 的 `NET_PREFIX`） |
| `--relay-all-peer-rpc true` | 白名单外的网络仍可借本节点交换 RPC、建立直连，但数据不经本节点转发 |

如需限制中继带宽，可加 `--foreign-relay-bps-limit <字节每秒>`。

## 接入游戏

1. 在 `scripts/net/eve_relay_list.gd` 的 `BUILTIN` 列表最前面加上 `tcp://<服务器IP或域名>:11010`。
   所有玩家必须使用同一份列表，否则互相看不到，所以改列表要随版本一起发布。
2. 公益节点保留在后面作为备用。
3. 以后有了大厅服务，节点列表应改为由服务器下发（内置列表作兜底），换节点就不必发新版本。
   见 `docs/联机方案.md`。
