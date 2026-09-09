# Patches

这些补丁记录了在把设备树/内核接入 AviumUI（LineageOS 23.2 / Android 16）构建时，
对**设备配置**和 **GKI 内核 UAPI 头**做过的真实改动，供复现与审计。它们都不是对
`dts/` 源文件本身的编辑——本仓库的 DTS 是从出厂固件精确反编译得到的（见
`original/notes.md`）。

## 0001-device-prebuilt-kernel-dtbo-and-partitions.patch

对象：`device/xiaomi/popsicle/BoardConfig.mk`

要点：
- 使用**预编译内核与设备树**：`TARGET_FORCE_PREBUILT_KERNEL := true`、
  `TARGET_PREBUILT_KERNEL := .../prebuilt/Image`、
  `BOARD_PREBUILT_DTBOIMAGE := .../prebuilt/dtbo.img`；
- 指定 `BOARD_DTBOIMG_PARTITION_SIZE`、boot/vendor_boot header v4；
- 动态分区列表补齐 `system_dlkm` / `vendor_dlkm`，去掉未使用的 `vbmeta_vendor`
  （对应 fastboot 无此分区的问题），并移除其 AVB chained 配置；
- vendor/system DLKM 文件系统 ext4 → erofs。

> 说明：构建时 `prebuilt/dtbo.img` 用的是早期提取的精简版；真机最终生效的是更完整的
> 出厂 dtbo（见 `original/notes.md` 的“两份 dtbo”说明）。本仓库 `dts/` 以真机完整版为准。

## 0002-kernel-uapi-qualcomm-headers.patch

对象：GKI common 内核（android16-6.12）`include/uapi/`，新增 30 个高通私有用户态头
（display/drm、sound、IPA、mem-buf、ion、nfc 等），使 `make headers_install` 通过。
属于内核用户态接口补全，与设备树节点无直接关系，仅在你要从源码完整构建内核时需要。

## 应用方式

```bash
# 0001 在 Android 源码根
cd device/xiaomi/popsicle && patch -p1 < ../../patches/0001-*.patch
# 0002 在 GKI 内核树根
cd kernel/xiaomi/popsicle && patch -p1 < /path/to/0002-*.patch
```
