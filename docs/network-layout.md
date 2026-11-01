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
- `/usr/sbin/iptv-multi`：`br-lan = lan1`，`br-iptv = lan2 lan3 lan4 + pon0.43`；
- 单口版 `luci-app-iptv` 默认 `enabled=0`，避免它把桥改回单口；
- IPTV 业务 VLAN 默认 `43`，可在脚本里用 `SVC_VLAN` 覆盖。

> 文档里的地址和 VLAN 都是示例，按自己环境替换。
