#!/bin/sh
# 阶段: ./scripts/feeds update -a 之前 (工作流步骤 "Load custom feeds", cwd = openwrt/)
# 用途: 往 feeds.conf.default 追加或放开第三方 feed 源; mosdns 是例外, 必须插到 packages 之前, 见该段注释
# 约束: feed 名只能用字母数字下划线 —— scripts/feeds 的解析正则里名字捕获组是 (\w+)、
#       不含连字符, 带 `-` 会在 feeds update 时报 "Syntax error in feeds.conf.default"
#       (2026-10-10 的 CI 失败即此因, 不是仓库格式问题)。
# 不在这里 clone 包: 非 feed 格式的第三方包必须等 feeds install 之后才 clone,
#       否则依赖解析不到、包会被 make defconfig 静默跳过, 见 clone-packages.sh。

# Uncomment a feed source
# sed -i 's/^#\(.*helloworld\)/\1/' feeds.conf.default

# Add a feed source
# echo 'src-git helloworld https://github.com/fw876/helloworld' >>feeds.conf.default
# echo 'src-git passwall https://github.com/xiaorouji/openwrt-passwall' >>feeds.conf.default

# echo "src-git kenzo https://github.com/kenzok8/openwrt-packages" >> ./feeds.conf.default
# echo "src-git small https://github.com/kenzok8/small" >> ./feeds.conf.default

# MosDNS (sbwml) —— 分流 DNS: mosdns 5.3.4 主程序 + luci-app-mosdns 界面 + geo2txt 地理解包工具。
# 【必须插在 src-git packages 之前】immortalwrt/packages 至今仍有 net/mosdns (5.3.3),
# 而 scripts/feeds 的 install_src 对同名包只认第一个声明的 feed ($installed{$name} 真即跳过)。
# packages 在前的后果: 装成官方那份 —— 它没有 stats_api / query log / adblock_set 等
# 二十多个补丁, luci-app-mosdns 的统计页和 mosdns-panel 的 /metrics 全部拿不到数据,
# 而且它自带的 /etc/init.d/mosdns 与 /etc/mosdns/config.yaml 会和 luci-app-mosdns 的同名文件相撞。
# sed 的 i 命令按锚点插入, 锚点没匹配上就是静默不插, 故下面补一段行序断言。
grep -q '^src-git mosdns ' feeds.conf.default || \
  sed -i '/^src-git packages /i src-git mosdns https://github.com/sbwml/luci-app-mosdns.git^dbdd91ab8ac8b079b6a3ca1a48d99e970d17111b' feeds.conf.default

# 断言 mosdns 行存在且排在 packages 之前 (grep -n 取行号比较)
mosdns_ln=$(grep -n '^src-git mosdns ' feeds.conf.default | cut -d: -f1)
packages_ln=$(grep -n '^src-git packages ' feeds.conf.default | cut -d: -f1)
if [ -z "$mosdns_ln" ] || [ -z "$packages_ln" ] || [ "$mosdns_ln" -gt "$packages_ln" ]; then
  echo "::error::feeds.conf.default 里 src-git mosdns 必须存在且排在 src-git packages 之前 (实际: mosdns=$mosdns_ln packages=$packages_ln)"
  exit 1
fi

# MosDNS 监控面板 (MayflyDestiny) —— 在 LuCI 的 MosDNS 菜单下多一个「面板」标签页,
# 看缓存命中率环形图、实时筛日志、清缓存/恢复 dump, 数据源是 mosdns 的 API 端口 (默认 9091)。
# 仓库根下是 luci-app-mosdns-panel/ 一个包目录 (img/ 与 yaml/ 里没有 Makefile, scripts/feeds 扫不到、自动忽略),
# 可直接作为 feed; 与 packages 无同名包, 追加到末尾即可。feed 名用下划线 mosdns_panel, 连字符见文件头约束。
# 它是 Lua 应用, 但 luci.mk 检测到 luasrc/ 会自动补 +luci-lua-runtime, 依赖不用手写。
grep -q '^src-git mosdns_panel ' feeds.conf.default || \
  echo 'src-git mosdns_panel https://github.com/MayflyDestiny/luci-app-mosdns-panel.git^526ad2afe86b410e472b6f9c311f960324a68fbd' >>feeds.conf.default

# Lucky 大吉 (lucky 核心 + LuCI 界面：IPv6 端口转发 / DDNS / 反向代理)
# 仓库根下是 lucky/ 与 luci-app-lucky/ 两个包目录，可直接作为 feed 扫描；
# 固定提交避免上游改动影响编译。feed 名 lucky 不含连字符，符合上面的命名约束。
# 源码仓库的 feeds.conf.default 只保留默认 feed，第三方 feed 统一在这里追加；
# grep 判重保证重复执行不会写入第二条。
grep -q '^src-git lucky ' feeds.conf.default || \
  echo 'src-git lucky https://github.com/gdy666/luci-app-lucky.git^9449a5250c61f1aa8f16b2d8e04a9da25c26e735' >>feeds.conf.default
