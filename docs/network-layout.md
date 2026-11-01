# 网络布局

## 端口分配

| 端口 | 速率 | 用途 |
| --- | --- | --- |
| `lan1` | 2.5G | 主 LAN，接 2.5G 交换机 / AP |
| `lan2` / `lan3` / `lan4` | 1G | IPTV 桥接口，接机顶盒 |
| `pon0` | XG-PON | WAN（PPPoE over `pon0.41`） |

## 拓扑

```
IPTV 业务 VLAN (pon0.43)
        │
        ├── lan2 ── 机顶盒
        ├── lan3 ── 机顶盒
        └── lan4 ── 机顶盒

WAN (PPPoE, pon0.41)
        │
      ONT
        │
      lan1 (2.5G)
        │
   2.5G 交换机
        ├── AP
        └── PC / NAS
```

## 为什么 1G 口全部做 IPTV

- Airoha PPE 的硬件 offload 只对 `airoha_eth` 的物理口（`lan1`、`pon0`）生效；
- `lan2-4` 是 MT7530 的 DSA 口，不会进 PPE 的 flowtable；
- 所以把 2.5G 口留给主 LAN（下挂 2.5G 交换机），三个 1G 口全部给 IPTV，正好物尽其用。

## 对应配置

- `/usr/sbin/ppe-offload`：`flowtable devices = { lan1, pon0 }`，触发 PPE/NPU offload；
- LuCI「网络 → IPTV (multi-port)」对应 `/etc/config/iptv_multi`：
  - `lan_ports`：要划给 IPTV 的 LAN 口（默认 lan2/lan3/lan4）；
  - `service_vlan`：业务 VLAN（默认 43）；
  - `multicast_vlan` / `igmp_vlan`：可选的组播 / IGMP 上游 VLAN；
  - 选中的口会从 `br-lan` 移到 `br-iptv`，其余口留在主 LAN；
- 不再安装单口版 `luci-app-iptv`，避免它把桥改回单口。

> 文档里的地址和 VLAN 都是示例，按自己环境替换。

## 从主 LAN 看 IPTV

`Multicast VLAN` 只作用在 `br-iptv` 内部，**不会**把组播放进 `br-lan`。所以不插 IPTV 口时，br-lan 设备直接访问 `rtp://239.x.x.x:端口` 是看不到的。

两种做法：

1. **msd_lite（推荐）**：给 IPTV 侧一个带 IP 的接口（或在 `br-iptv` 上配 IP），在「服务 → msd_lite」绑定该接口；LAN 设备播放 `http://192.168.1.1:7088/rtp/239.x.x.x:端口`。
2. **组播路由**（igmpproxy / smcroute）：把 `pon0.43` 的组播转发到 `br-lan`，并放行 IGMP；配置更复杂，而且组播会进入主 LAN。
