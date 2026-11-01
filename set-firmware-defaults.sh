#!/bin/sh
# 阶段: make defconfig 之后、make download 与正式编译之前
#       (工作流步骤 "Load custom config" 末尾, cwd = openwrt/)
# 用途: 改用固件的出厂默认值。改的是源码树里会被装进 rootfs 的文件, 构建期改一次即随固件走,
#       用户侧恢复出厂或 sysupgrade -n 之后仍是这里的值 —— 这是它和"运行时 uci 改"的区别。
# 注意: 本脚本被本分支三份编译目标 (an7581 / an7581-gpon / an7583-gpon) 共用,
#       改动对三份产出同时生效; 只想给某台设备单独设默认值时, 先想清楚这个共用前提。

# Modify default IP (取消注释并修改为你需要的地址)
sed -i 's/192.168.1.1/10.0.0.1/g' package/base-files/files/bin/config_generate
