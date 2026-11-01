# DNS 泄露防护（两套架构）

本文对应两种常见部署：

- **架构 A**：路由器做网关，代理跑在另一台设备上（mihomo / Clash 透明模式，或按设备手动设代理）
- **架构 B**：路由器自己跑 dae，代理和分流都在路由器上

先明确一个语义：**“无 DNS 泄露”是配置正确后的结果，不是某个开关**。它只表示“本地链路 / 运营商看不到明文 DNS”，不代表代理服务商看不到你的查询。

---

## 0. 什么算泄露

| 现象 | 说明 |
| --- | --- |
| LAN 设备把 53 直接发到 WAN | 明文查询绕过路由器，运营商可见 |
| 境外域名用国内 DNS 解析 | 不一定是“泄露”，但会被国内解析器看到，且可能被污染 |
| IPv6 的 DNS 没被接管 | 只劫持了 IPv4，AAAA / v6 查询直出 |
| 设备自带 DoH / DoT | 浏览器、安卓 Private DNS 走 443/853，53 劫持看不到 |
| 代理端 DNS 没走代理 | 域名在本地解析后再连代理，查询仍暴露给本地网络 |

---

## 1. 两套架构都要做的基础项

### 1.1 DHCP 只下发路由器一个 DNS

```sh
uci set dhcp.lan.dhcp_option='6,192.168.1.1'
uci set dhcp.lan.dns='192.168.1.1'
uci commit dhcp
/etc/init.d/dnsmasq restart
```

### 1.2 劫持 LAN 的 53（IPv4 + IPv6）

用 MosDNS 自带的劫持（会加 nft 规则，v4/v6 的 UDP 53 都重定向到 5335）：

```sh
uci set mosdns.config.local_dns_redirect='1'
uci commit mosdns
/etc/init.d/mosdns restart
```

> 如果跑的是 dae（架构 B），二选一：让 dae 劫持 53，或让 MosDNS 劫持 53。**不要两边同时劫持**，否则规则顺序不可控。下面架构 B 会写推荐做法。

### 1.3 阻断 LAN 直接访问外部 53 / 853

MosDNS 的 redirect 只处理 UDP 53；设备用 TCP 53、DoT 853 仍然能绕。用 fw4 规则兜底（持久化，重启不丢）：

```sh
# 先给代理设备开例外（按自己的 IP 改）
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-proxy-DNS'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].src_ip='192.168.1.253'
uci set firewall.@rule[-1].proto='tcp udp'
uci set firewall.@rule[-1].dest_port='53 853'
uci set firewall.@rule[-1].target='ACCEPT'

# 其余 LAN 设备禁止直接访问外部 DNS
uci add firewall rule
uci set firewall.@rule[-1].name='Block-LAN-DNS'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].proto='tcp udp'
uci set firewall.@rule[-1].dest_port='53 853'
uci set firewall.@rule[-1].target='REJECT'

uci commit firewall
/etc/init.d/firewall reload
```

说明：

- 访问路由器自身 53 的流量走 input 链，不受这两条 forward 规则影响；
- `src=lan` 同时覆盖 IPv4 和 IPv6；
- 代理设备若用 mihomo 的 1053 端口解析，不在 53/853 范围内，不受影响；
- 规则顺序按 uci 添加顺序，例外必须在阻断之前。

### 1.4 关掉 IPv6 的 RDNSS（或者确保 v6 也被劫持）

只下发 IPv4 DNS、不放 RDNSS：

```sh
uci set dhcp.lan.ra_dns='0'
uci commit dhcp
/etc/init.d/odhcpd restart
```

如果保留 RDNSS，就必须确认 v6 的 53 也被劫持/阻断（1.2 的 MosDNS 劫持覆盖 v6 UDP 53，但要自己测）。

### 1.5 设备自带 DoH / DoT

这个没法在网络层“完全”解决，只能提高成本：

- 安卓：设置 → 私人 DNS → 关闭
- Chrome / Firefox：关闭“安全 DNS”
- iOS：不装配置描述文件
- 真要拦：在代理/防火墙层按域名或 SNI 拦已知 DoH 端点（`dns.google`、`cloudflare-dns.com`、`doh.pub`、`dns.alidns.com`…），但维护成本高、容易误伤

---

## 2. 架构 A：路由器 + 外部透明代理

```
设备 ──(网关/DNS 都指路由器)──> 路由器
                                  ├─ dnsmasq:53 → MosDNS:5335（DoH）
                                  └─ 流量 → 外部代理设备（按 IP/域名分流）
```

### 2.1 要点

1. MosDNS 负责本机 DNS（缓存 + 广告过滤），`local_dns_redirect=1` 接管 LAN 的 53。
2. 境外域名不要用国内 DoH 解析：
   ```sh
   uci set mosdns.config.remote_dns='udp://192.168.1.253:1053'
   uci commit mosdns
   ```
   前提是代理设备开了 DNS 监听（mihomo 常见 1053）。没有 DNS 监听就保持国内 DoH，接受“不泄露但可能污染”。
3. 代理设备的 DNS 端口不要暴露给 LAN（只监听本机或只允许路由器访问），否则设备可以绕过 MosDNS 直接问它。
4. 代理设备的 DNS 查询本身要走代理，不要让它直连国外 53。

### 2.2 这套架构的泄露面

- 设备自带的 DoH（1.5）
- IPv6 没接管（1.4）
- 代理设备的 DNS 端口暴露（2.1 第 3 点）
- 代理设备自己用本地 DNS 解析境外域名（2.1 第 4 点）

---

## 3. 架构 B：路由器 + dae

```
设备 ──(网关/DNS 都指路由器)──> 路由器
                                  ├─ dae 劫持 53 → DNS 上游（可指向 MosDNS）
                                  └─ dae eBPF 按 IP/域名分流 → 代理节点
```

### 3.1 推荐接法：dae 劫持，MosDNS 做上游

```dae
global {
  wan_interface: auto
  lan_interface: br-lan
  auto_config_kernel_parameter: true
}

dns {
  upstream {
    mosdns: 'udp://127.0.0.1:5335'
  }
  routing {
    request {
      fallback: mosdns
    }
  }
}

routing {
  pname(mosdns, dnsmasq) -> must_direct
  dip(geoip:private) -> direct
  dip(geoip:cn) -> direct
  fallback: proxy
}
```

- **不要**同时开 MosDNS 的 `local_dns_redirect`（会和 dae 的劫持抢 53）；
- MosDNS 继续做缓存和广告过滤，dae 的 DNS 上游指向它；
- 境外解析是否干净，取决于 MosDNS 的 `remote_dns`：指到代理侧 DNS 才不泄露。

### 3.2 如果只想按 IP 分流

也可以让 MosDNS 劫持 53（`local_dns_redirect=1`），dae 的 `dns` 段不参与，只做流量分流：

```dae
routing {
  dip(geoip:private) -> direct
  dip(geoip:cn) -> direct
  fallback: proxy
}
```

这种方式最简单，但 dae 的域名规则（`domain(geosite:...)`）就用不上了。

### 3.3 这套架构的泄露面

- `routing` 里把境外写成 `must_direct`（查询直出）
- `dns` 上游用了国内 DNS 解析境外（被国内解析器看到）
- 设备自带 DoH / IPv6 绕过（同 1.5 / 1.4）
- 代理侧 DNS 没走代理

---

## 4. 验证方法

在路由器上抓 WAN 侧 53，同时用 LAN 设备访问几个网站：

```sh
WAN=$(uci -q get network.wan.device || echo pon0)
tcpdump -ni "$WAN" 'udp port 53 or tcp port 53 or tcp port 853'
```

- 只应看到**路由器自己**（源地址是 WAN IP）的查询；
- 出现 `192.168.1.x` 源地址的 53/853 → 有设备绕过，回 1.3 加规则。

从 LAN 设备测试是否被劫持：

```sh
dig @8.8.8.8 example.com          # 应该超时，或返回路由器/ MosDNS 的结果
dig @223.5.5.5 example.com        # 同上
```

IPv6：

```sh
dig -6 @2606:4700:4700::1111 example.com
```

DoH 是否被设备使用（抓 443 的 SNI）：

```sh
tcpdump -ni "$WAN" -A 'tcp port 443' | grep -iE 'dns\.google|cloudflare-dns|doh\.pub|dns\.alidns'
```

在线测试：在 LAN 设备上跑 `dnsleaktest.com`。注意结果要结合架构看：
- 架构 A：结果应显示代理出口的 DNS（如果代理 DNS 走代理），或国内 DNS（如果没配）；
- 架构 B：结果应显示代理侧 DNS；显示本地运营商 DNS 就说明境外查询没走代理。

---

## 5. 检查表

- [ ] DHCP 只下发一个 DNS（路由器）
- [ ] LAN 的 UDP 53 被劫持（v4 + v6）
- [ ] LAN 的 TCP 53 / 853 被阻断，且代理设备有例外
- [ ] IPv6 RDNSS 关闭，或 v6 的 53 已接管
- [ ] 设备自带 DoH/DoT 已关闭或按需拦截
- [ ] MosDNS 的 `remote_dns` 指向代理侧（或接受国内 DoH）
- [ ] 代理设备的 DNS 端口没有暴露给 LAN
- [ ] 代理设备自己的 DNS 查询走代理
- [ ] `tcpdump` 在 WAN 侧看不到 LAN 源地址的 53
- [ ] `dnsleaktest` 结果符合预期

---

## 6. 常见误区

| 说法 | 实际 |
| --- | --- |
| “用了 DoH 就不泄露” | 链路加密了，但解析器仍能看到查询内容 |
| “流量走代理了，DNS 肯定也走” | 不一定，DNS 可能还在本地直出 |
| “关了 IPv6 就安全” | 设备自带 DoH 仍然可能绕过 |
| “dae 无 DNS 泄露” | 是架构结果，不是开关；配错照样漏 |
| “节点在境外就不泄露” | 本地 DNS 解析 + 境外连接，查询仍在本地暴露 |

---

## 7. 两套架构对照

| 项目 | 架构 A（外部代理） | 架构 B（dae） |
| --- | --- | --- |
| DNS 入口 | dnsmasq → MosDNS（劫持 53） | dae 劫持 53 → MosDNS |
| 境外解析 | MosDNS `remote_dns` 指代理侧 DNS | 同上，或 dae DNS 上游走代理 |
| 分流依据 | 外部代理的 IP/域名规则 | dae 的 `dip(geoip:cn)` / `domain(geosite:cn)` |
| 主要泄露面 | 代理 DNS 暴露、设备 DoH、IPv6 | 规则写错、DNS 上游直连、设备 DoH、IPv6 |
| 复杂度 | 两台设备，DNS 链路长 | 一台设备，规则集中 |
