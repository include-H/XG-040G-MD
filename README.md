# Nokia XG-040G-MD 固件

基于 [PonWrt](https://github.com/pbs05/ponwrt)（ImmortalWrt）的 **Nokia XG-040G-MD**（Airoha AN7581）光猫固件构建配置与云编译工作流。

本仓库是面向该机型的通用配置：预装的 PON 身份、DNS、IPTV、代理设置都可以按自己的线路和需求调整。

## 文档

- [DNS 泄露防护（两套架构）](docs/dns-leak.md)
- [PPE 硬件 offload 修复记录](docs/ppe-offload.md)

## 硬件

| 项目 | 值 |
| --- | --- |
| SoC | Airoha AN7581，4× Cortex-A53 @ 1.2GHz |
| 内存 | 512MB |
| 闪存 | 256MB NAND（UBI 布局） |
| PON | XG-PON（10G/2.5G）；驱动支持 XG-PON / XGS-PON / GPON / EPON 线路模式切换 |
| LAN | 1× 2.5G（lan1）作为主 LAN；3× 1G（lan2-4）作为 IPTV 桥接口 |
| USB | 2 路，带 5V 供电控制 |
| WiFi | 无 |

## 固件特性

| 分类 | 内容 |
| --- | --- |
| 基础 | PonWrt（ImmortalWrt）master，Linux 6.18，APK 包管理，SquashFS + UBIFS |
| PON | `luci-app-pon`、`airoha-ponctl`、`airoha-pond`、`airoha-pon-debug`、`airoha-en7581-npu-firmware`；默认线路模式 **XG-PON** |
| DNS | MosDNS 出厂启用：监听 5335，dnsmasq 转发，缓存，国内 DoH（阿里/腾讯/DNSPod），`adblock_set` 过滤 217heidai 列表 |
| IPTV | lan2-4 桥接到 PON 业务 VLAN（默认 43）+ `msd_lite` 组播转 HTTP（7088）；单口版 `luci-app-iptv` 保留但默认不接管 |
| 代理 | `dae` + geoip/geosite，**默认关闭**，节点和分流规则不预置；附 `dae-sub` 订阅归一化工具 |
| 身份默认值（示例） | `vendor_id=ZTEG`、`equipment_id=ZXHN G7615TV2-XG`、`hardware_version=V2.0`、`software_version=V3.0.0P1T3`，在 `files/etc/uci-defaults/99-pon-identity` 里改 |
| 内核 | 启用 BTF（dae 的 eBPF CO-RE 需要） |
| 网络加速 | PPE/NPU 硬件 offload：用 `lan1`+`pon0` 物理口建 flowtable（见文档），CPU 约 3% @ 1.1Gbps |
| 已移除 | AdGuard Home、OpenClash |

> PON 序列号（4 字符厂商前缀 + 8 位十六进制）和 LOID / LOID 密码跟运营商绑定，**不写默认值**。

## 仓库结构

```
├── .github/workflows/build-an7581-immortalwrt.yml   # 云编译工作流
├── an7581.config                                    # 设备配置（menuconfig 展开结果）
├── files/
│   ├── etc/uci-defaults/98-mosdns-defaults          # MosDNS 出厂默认值
│   ├── etc/uci-defaults/99-pon-identity             # OMCI 身份默认值
│   └── usr/sbin/dae-sub                             # 订阅归一化（纯文本/base64）
├── add-feed-sources.sh                              # feeds update 前：增删第三方 feed
├── clone-packages.sh                                # feeds install 后：clone 非 feed 包
└── set-firmware-defaults.sh                         # make defconfig 后：改出厂默认值
```

源码由工作流从 `DenzelVincent/ponwrt` 的 `master` 分支浅克隆。

## 云编译

Actions → **Build ImmortalWrt Firmware (AN7581)** → Run workflow。

| 输入 | 说明 |
| --- | --- |
| `clean_dl_cache` | 清空 `dl/` 下载缓存 |
| `clean_ccache` | 清空 `.ccache` |
| `release` | 勾选后创建 GitHub Release（否则只留 artifact） |

首次构建约 **4–5 小时**：内核带 debug info + BTF，且要从源码编 LLVM 22 作为 dae 的 BPF 工具链。之后的构建有 ccache/dl 缓存会快一些。

产物：`bin/targets/airoha/an7581/` 下的 `*-sysupgrade.itb`。

## 本地编译

```sh
sudo bash -c 'bash <(curl -s https://build-scripts.immortalwrt.org/init_build_environment.sh)'

git clone --depth 1 -b master https://github.com/DenzelVincent/ponwrt.git
cd ponwrt

sh /path/to/XG-040G-MD/add-feed-sources.sh
./scripts/feeds update -a
./scripts/feeds install -a
sh /path/to/XG-040G-MD/clone-packages.sh

cp /path/to/XG-040G-MD/an7581.config .config
make defconfig
sh /path/to/XG-040G-MD/set-firmware-defaults.sh
make -j$(nproc)
```

## 刷机

1. 用 [AN758x-Stock2UBI](https://github.com/pbs05/an758x-stock2ubi) 备份原厂 flash 并安装 UBI 布局；
2. 启动镜像和 Web 恢复由 [AN758x U-Boot](https://github.com/pbs05/uboot-an758x) 提供；
3. 刷入 `*-sysupgrade.itb`（U-Boot Web 或现有 OpenWrt 的 sysupgrade）；
4. 通过 U-Boot Web 或 LuCI「网络 → PON → 配置 → PON board data」恢复 `bosa` / `ri` 原厂校准与身份数据。

## 首次配置

1. **PON**：LuCI「网络 → PON」确认线路模式（默认 XG-PON），填 PON 序列号（4 字符厂商前缀 + 8 位十六进制，或 16 位十六进制）和 LOID / LOID 密码；接华为 OLT 注册不上时 OMCC 版本可试 `0x86`。
2. **MosDNS**：开箱即用；需要改上游或广告规则在「服务 → MosDNS」。想让境外域名解析更干净，可把 `remote_dns` 指向代理端（mihomo / Clash）的 DNS 端口。
3. **IPTV**：先建 IPTV 接口（`pon0.<VLAN>`，DHCP 或静态，必要时克隆机顶盒 MAC），再在「服务 → msd_lite」填 `0.0.0.0:7088` 和源接口；播放地址 `http://192.168.1.1:7088/rtp/组播IP:端口`。
4. **dae**：默认关闭。LuCI「服务 → dae」里写节点和 `routing`，典型三行：

```dae
routing {
  dip(geoip:private) -> direct
  dip(geoip:cn) -> direct
  fallback: proxy
}
```

订阅可用 `dae-sub add 名字 URL` 归一化（支持纯文本和 base64；Clash YAML 需先转成通用订阅）。

## 已知限制

- AN7581 没有 ARMv8 AES 指令，用户态 TLS 的 AES-GCM 走软件实现；代理协议优先选 ChaCha20 系（WireGuard、SS-2022、VLESS+ChaCha20）。
- PPE 硬件转发在部分拓扑下 `ppe/bind` 不生效（桥接、路由+PPPoE 都有人复现），别把满速寄托在硬件 offload 上。
- dae 的订阅只认 base64 分享链接和 SIP008，不认 Clash YAML；用 `dae-sub` 或换通用订阅链接。

## 免责声明

刷写固件、修改 PON 配置存在风险，可能导致设备无法启动、配置或数据丢失、PON 无法注册。操作前务必备份原厂固件和设备数据。

请确保操作符合当地法律法规及运营商规定，请勿用于未经授权的网络接入、冒用或复制他人设备身份。因使用本项目产生的后果由使用者自行承担。
