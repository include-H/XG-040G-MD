#!/bin/sh
# 阶段: ./scripts/feeds install -a 之后、make defconfig 之前
#       (工作流步骤 "Clone custom packages", cwd = openwrt/)
# 用途: clone 不是 feed 格式的第三方包 —— 仓库根目录直接放 Makefile, scripts/feeds 扫不到,
#       只能整仓 clone 进 package/。
# 位置是硬约束: 这些包的依赖写着 +luci-base 这类 feed 包, 在 feeds install 之前 clone 的话
#       扫描阶段依赖解析不了, make defconfig 会静默跳过整个包 —— 固件里没有对应界面,
#       但编译一路不报错。2026-10-10 airoha-npu 就是这么丢的 (提交 77684b6)。
# 约定: clone 目录名 = 包名; 单个包 clone 失败只打 workflow 标记、不中断整趟编译
#       (丢插件不丢固件); 末尾自检目录, 日志出现 [MISSING] 即该包不会进固件。
# 本地编译同样要在 feeds install 之后跑一遍本脚本, 否则配置里选的包会被静默丢弃。
# 注: lucky 与 mosdns_panel 仓库根下都是包目录 (mosdns_panel 还有 img/ 与 yaml/, 无 Makefile 会被 feeds 自动忽略),
#     由 add-feed-sources.sh 处理的 feed 提供, 本脚本不处理; mosdns 同理, 且它有 feed 行序约束, 见该脚本注释。

clone_pkg() {  # $1=仓库地址 $2=目标目录 $3=失败时的日志级别 warning|error
  if git clone --depth 1 "$1" "$2"; then
    echo "[OK] $2"
  else
    echo "::$3::$2 克隆失败，该插件不会进入固件"
  fi
}

# Airoha NPU 管理界面 (AN758x 平台专用；仓库根目录直接放 Makefile)
clone_pkg https://github.com/DenzelVincent/luci-app-airoha-npu.git package/luci-app-airoha-npu error

echo "=== 第三方包目录检查 ==="
for d in package/luci-app-airoha-npu; do
  [ -d "$d" ] && echo "[OK] $d" || echo "[MISSING] $d"
done
