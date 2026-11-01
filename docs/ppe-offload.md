# PPE 硬件 offload 修复记录

## 现象

- LAN → 外网测速约 1100–1180 Mbps，CPU 约 50%（4×A53 1.2GHz）；
- `/sys/kernel/debug/ppe/config` 里 `npu_attached: 0`；
- `/sys/kernel/debug/ppe/bind` 为空，`ppe/entries` 为空；
- `conntrack -L -o extended` 没有 `OFFLOAD`；
- `dmesg` 里 NPU 固件正常：`NPU fw version: 1456.62`。

## 原因

fw4 生成的 flowtable 设备是：

```
devices = { lan1, lan2, lan3, pon0.41, pppoe-wan }
```

其中 `pon0.41` 是 VLAN、`pppoe-wan` 是 PPP、`lan2/3` 是 mt7530 的 DSA 口。这些设备没有 `airoha_eth` 的 `ndo_setup_tc`，nft 的硬件 offload 块不会传给驱动，`airoha_ppe_offload_setup()` 从未被调用。

**不是 NPU 故障，也不是没开 `flow_offloading_hw`。**

## 修复

用**物理口**单独建一个 flowtable：

```sh
nft add table inet ppe
nft add flowtable inet ppe ft "{ hook ingress priority 0; devices = { lan1, pon0 }; flags offload; }"
nft add chain inet ppe c "{ type filter hook forward priority 10; policy accept; }"
nft add rule inet ppe c meta l4proto { tcp, udp } flow add @ft
```

本仓库用 `files/usr/sbin/ppe-offload` + `files/etc/init.d/ppe-offload` 在开机/接口 up 时自动执行。

验证：

```sh
head -1 /sys/kernel/debug/ppe/config     # npu_attached: 1
wc -l < /sys/kernel/debug/ppe/bind       # > 0
wc -l < /sys/kernel/debug/ppe/entries    # > 0
```

实测：`PPE:51`、CPU 从 50% 降到 **3%**，测速 1178 Mbps。

## 限制

- **只对 `lan1`（2.5G）和 `pon0` 生效**。lan2/3/4 是 MT7530 的 DSA 口，走的不是 airoha_eth，不能进这个 flowtable；
- 如果换了 LAN/WAN 物理口，改 `DEV_LAN` / `DEV_WAN` 环境变量，或修改 `/usr/sbin/ppe-offload` 默认值；
- fw4 自带的 `flow_offloading` / `flow_offloading_hw` 可以保持开启（它的 flowtable 绑不上，但无害），也可以关掉，只留 `ppe` 表；
- NPU 固件版本与这个修复无关：`2.1.1-TLB7.3.283.1456-62` 就够用；
- `CRYPTO HW: 0` 是正常的：AN7581 没有 ARMv8 AES 指令，用户态 TLS 走软件 AES，WireGuard/ChaCha20 不受影响。
