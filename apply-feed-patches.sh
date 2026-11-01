#!/bin/sh
# 阶段: ./scripts/feeds install -a 之后、make defconfig 之前 (工作流步骤 "Apply feed patches", cwd = openwrt/)
# 用途: 给第三方 feed 里的包补上游还没合并的补丁。feed 是 src-git 直接拉 master，
#       在本仓库改源码没用 —— 只能在 feeds install 之后把补丁塞进包目录的 patches/，
#       由 OpenWrt 的 Build/Patch 在解包/复制 src 之后按 -p1 应用（补丁路径相对包内 src/）。
# 约束: 补丁先在临时目录对 src/ 做一次 --dry-run，应用不上就立刻失败；
#       否则会编了几个小时才发现内核模块没打上，PON 断网还是要手动重启。
set -eu

REPO_ROOT=${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")" && pwd)}

# $1=feed 包目录  $2...=补丁文件
apply_patches() {
	pkgdir=$1
	shift
	[ -d "$pkgdir/src" ] || {
		echo "::error::找不到包源码目录 $pkgdir/src（feed 结构变了？）"
		exit 1
	}
	for patch in "$@"; do
		[ -f "$patch" ] || {
			echo "::error::补丁不存在: $patch"
			exit 1
		}
		tmp=$(mktemp -d)
		cp -a "$pkgdir/src/." "$tmp/"
		if ! (cd "$tmp" && patch -p1 --dry-run -s <"$patch"); then
			rm -rf "$tmp"
			echo "::error::补丁应用失败: $patch（上游可能已合并或改动 $pkgdir，核对后删除本仓库对应补丁）"
			exit 1
		fi
		rm -rf "$tmp"
		mkdir -p "$pkgdir/patches"
		cp "$patch" "$pkgdir/patches/$(basename "$patch")"
		echo "[OK] $(basename "$patch") -> $pkgdir/patches"
	done
}

# issue #49: XG-PON MBI RX overrun 会把 MAC 卡死（MBI_RX_STOP_DONE 不置位），
# 只有 MAC epoch 复位能恢复。补丁在 overrun 风暴（>=32 次、距上次复位 >60s）后自动复位，
# 作者在 XG-040G-MD 与 ZN504XG-D 上实测：463s 死链(需手动重启) -> 17.6s 自动恢复。
# 同时把 mbi_header_overrun_irq / mbi_payload_overrun_irq / mbi_reset 计数加进
# /sys/kernel/debug/airoha-xpon-*/mac，刷机后可直接确认补丁在不在、有没有触发过。
apply_patches feeds/pon_drivers/airoha-xpon \
	"$REPO_ROOT"/patches/airoha-xpon/*.patch

echo "=== feed 补丁检查 ==="
ls -1 feeds/pon_drivers/airoha-xpon/patches/
