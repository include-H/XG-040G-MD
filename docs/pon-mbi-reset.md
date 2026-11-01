# PON 断网自愈（MBI RX overrun）

对应上游 issue：[pbs05/ponwrt#49](https://github.com/pbs05/ponwrt/issues/49)（根因）、
[pbs05/ponwrt#50](https://github.com/pbs05/ponwrt/issues/50)（现象）。

## 现象

```
kern.warn kernel: airoha-xpon 1fb64000.ethernet: XG-PON MAC error:
  int=0x00008000 fifo=0x00000180 tx=0x00000000 rx=0x00000000 bwm=0x00000005
```

刷屏之后 `pppoe-wan` 掉线，**不会自己恢复**，必须进 LuCI 重启 PON 口或重启整机。
#49 的记录里，未修补时要 **463 秒**死链 + 手动干预；补丁后 **17.6 秒**自动恢复。

## 原因

`int=0x8000` 是 `INT_FIFO_ERROR`，`fifo=0x180` 是 MBI RX header + payload overrun
（BIT 7 | BIT 8），`tx=0`、`rx=0` 说明与发送、MAC 收发错误无关 —— 是**下行 MBI 接收缓冲区溢出**。

溢出后 MAC 进入卡死状态：

```
MBI_RX_STOP_DONE 一直不置位（raw=0xc1018101）
```

MPI 停得掉、MBI 发送停得掉，只有 MBI 接收侧拒绝进入静止状态。软件层
`stop_mac_interfaces()` 等超时也没用，**只有整个 MAC epoch 复位**能恢复。

触发条件（#49 的观测）：

- 与负载**无关**，不是“大流量跑久了才断”；
- 随机，典型在 uptime **36–46 小时**出现；
- 正常运行时 overrun 计数一直是 0，`fifo=0x180` 是干净的故障指示；
- `bwm=0x5` 不是判据，健康链路启动几秒后也是 `0x5`。

## 补丁做了什么

`patches/airoha-xpon/0001-xgpon-queue-mac-epoch-reset-on-mbi-rx-overrun-storm.patch`
（来自 #49 附件，作者在 XG-040G-MD 与 ZN504XG-D 上实测）：

- MAC 错误中断里累计 MBI RX overrun；
- 连续 ≥32 次、且距上次复位 >60 秒，就在 `link_work` 里排一次 MAC epoch reset；
- 复位后 O5 注册流程重新拉起上游，userspace 自动重推数据路径，PPPoE 自动重拨；
- 顺带把 `mbi_header_overrun_irq`、`mbi_payload_overrun_irq`、`mbi_reset` 计数
  加进 `/sys/kernel/debug/airoha-xpon-*/mac`。

本仓库在 `apply-feed-patches.sh` 里把补丁注入 `feeds/pon_drivers/airoha-xpon/patches/`，
构建时由 OpenWrt 的 `Build/Patch` 自动应用；补丁 dry-run 不通过会直接让构建失败，
不会静默产出一个“没打补丁”的固件。

## 刷机后怎么确认

```sh
cat /sys/kernel/debug/airoha-xpon-pon0/mac
```

有补丁时多出这几行：

```
bwm_check: 0x00000005
mbi_header_overrun_irq: 0
mbi_payload_overrun_irq: 0
mbi_reset: 0
```

- 前两个计数一直是 0：链路健康；
- 开始增长并出现 `XG-PON MAC error`：已经进过 overrun 风暴；
- `mbi_reset` 变成 1 以上：补丁自动复位过，同时 `logread` 里会有
  `XG-PON MAC epoch reset (MBI RX overrun storm)`。

## 升级/移除

- 上游 `pbs05/openwrt-pon-drivers` 合并同类修复后，本仓库的补丁会应用失败，
  构建直接报错 —— 那时删掉 `patches/airoha-xpon/` 下的补丁，
  并同时删掉 `apply-feed-patches.sh` 里对应的 `apply_patches` 调用。
- 补丁只做复位，不改数据面；如果只想临时规避，仍可 `/etc/init.d/ppe-offload stop`
  回软件转发，但那是降低负载，不是修这个 bug。
