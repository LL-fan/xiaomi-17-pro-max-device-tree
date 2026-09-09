# 原厂设备树来源与提取说明（provenance）

本目录是**对照与溯源材料**，仓库的权威源是上层 `dts/` 文本。这里记录 DTS 是怎么来的、
用什么工具、以及合规检查结论，便于他人独立复现与审计。

## 1. 为什么需要从固件反编译

我最初尝试从开源内核取板级 dts 源，结论是**官方开源分支不含板级 dts**：

- GKI common 内核 `kernel/xiaomi/popsicle`（分支 android16-6.12，Linux 6.12.92）只有上游
  各厂商示例，没有小米板级 dts。
- 小米厂商层 `popsicle.mi-glue`（来自 **MiCode/Xiaomi_Kernel_OpenSource 分支
  `popsicle-w-oss`**，唯一提交 “Kernel: Xiaomi 17/17Pro/17ProMax for Android W”）里，
  `arch/arm64/boot/dts/vendor` 是一个指向 `../../../../../qcom/opensource/devicetree`
  的**符号链接**，而该独立 devicetree 仓既不在本地 sparse checkout 白名单内，也未随
  popsicle-w-oss 分支发布（GitHub 上该分支根目录无 `qcom/`，返回 404）；其 `.gitignore`
  还显式忽略 `arch/*/boot/dts/vendor`。
- 因此 ROM 构建时走的是**预编译设备树**（`TARGET_FORCE_PREBUILT_KERNEL := true`、
  `BOARD_PREBUILT_DTBOIMAGE := device/xiaomi/popsicle/prebuilt/dtbo.img`），out 目录没有
  任何由 dts 现场编译出的 .dtb 中间产物。

在未获得对应板级 DTS 源码的情况下，从**实际运行的固件提取并反编译**
是目前还原运行时设备树的一种可靠方法；它仍需要通过逐节点比较和真机测试进一步确认。

## 2. 从哪些分区提取（当前槽 _a）

| 来源 by-name | 块设备 | 取出内容 |
|---|---|---|
| `vendor_boot_a` | sde25 | VNDRBOOT v4，解出 base dtb（4511568 B） |
| `dtbo_a` | sde18 | Android dt_table，1 个板级 overlay（1463920 B） |
| `qtvm_dtbo_a` | sde22 | dt_table，2 个 Gunyah VM overlay（513062 / 9674 B） |
| `cpucp_dtb_a` | sde31 | **ELF 协处理器固件，不是设备树，已排除** |

`dd` 命令、unpack/反编译/合并的完整自动化见 `../scripts/extract-from-device.sh`。

## 3. 工具与处理流程

1. `adb shell su 0 dd if=/dev/block/by-name/<part> of=/data/local/tmp/x.img` 提取并 `adb pull`。
2. vendor_boot 用 AOSP host 工具 `unpack_bootimg --boot_img ... --out ...` 取出其中 `dtb`
   （VNDRBOOT v4：page=4096、header_size=2128、dtb_size=4511568、dtb_addr=0x1f00000）。
3. dtbo/qtvm 按 `dt_table_header`（magic `0xD7B7AB1E`，header/entry 各 32B）切分出每个 dtb；
   对应实现即 `../scripts/mkdtimage.py dump`。
4. 用 **dtc 1.6.1**（Debian `device-tree-compiler`）`dtc -I dtb -O dts` 反编译：
   - base → 28429 行（`qcom,canoe`）
   - board overlay → 26513 行（“Popsicle based on SM8850”）
   - qtvm SVM → 12640 行、OEMVM → 452 行
5. `fdtoverlay -i base.dtb -o merged.dtb board-overlay.dtbo` 离线复现 bootloader 的叠加，
   得到 **52090 行扁平完整树**（合并后 `fragment@` / `__overlay__` 计数均为 0），形成
   `dts/xiaomi-17-pro-max.dts`，用于还原运行时 `/proc/device-tree`。
6. 回编闭环：`dtc -I dts -O dtb -@` 全部返回 0；`make verify` 与原厂根节点元数据 4/4 一致
   （见 `../docs/testing.md`）。

## 4. 本目录文件

| 文件 | 说明 |
|---|---|
| `stock-base.dtb` | vendor_boot 内出厂 base dtb（4511568 B） |
| `stock-dtbo.img` | dtbo 分区镜像，已按 dt_table total_size 去掉分区 padding（1466368 B） |
| `stock-qtvm-dtbo.img` | qtvm_dtbo 分区镜像，同样去 padding（524288 B） |
| `stock-bootconfig.txt` | vendor_boot 的 bootconfig（androidboot.hardware=qcom、hypervisor=gunyah 等） |
| `extracted/extracted-base.dts` | base 的原始反编译文本（= `dts/*-common.dtsi` 溯源副本） |
| `extracted/extracted-board-overlay.dts` | 板级 overlay 原始反编译文本 |
| `extracted/extracted-build-output-dtbo.dts` | 构建树里那份早期 dtbo 的反编译（见下） |

## 5. 两份 dtbo 的区别（重要）

适配过程中出现过两份不同的板级 dtbo，务必区分：

| | 构建用 prebuilt dtbo | 真机实际运行 dtbo（本仓库采用） |
|---|---|---|
| 路径 | `device/xiaomi/popsicle/prebuilt/dtbo.img` | `/dev/block/by-name/dtbo_a` |
| 表项大小 | 141204 B（镜像 141268 B） | 1463920 B（镜像去 padding 后 1466368 B） |
| 反编译行数 / fragment | 5951 行 / 445 | 26513 行 / 1359 |
| 内容 | 早期提取的精简子集 | 完整板级设备树 |

二者 md5 不同、规模相差约 10 倍。**本仓库 `dts/` 一律以真机实际运行的完整版为准**
（更完整、与 `/proc/device-tree` 一致）；精简版仅留在 `extracted/extracted-build-output-dtbo.dts`
作为历史对照。

## 6. 隐私 / 机密扫描结论

对 base 与 board overlay 全文检索 serial/imei/mac/bluetooth-wifi 地址/secret/password/
private-key/cert/modem 校准/efs/qfuse/die-id 等：

- **未发现**任何个人或机密数据（无 MAC/IMEI/序列号/密钥/校准/账号信息）。
- 仅命中硬件常量：`qcom,chipid = <0x44050a01>`（芯片标识）与相机拓扑 `*-uuid`
  （硬件连接关系），属于可公开的硬件描述。

关键词扫描未发现明显的个人或机密数据，但这不能替代发布前的人工审查、
许可证核对和再分发权限确认。重新发布前仍建议用下列命令自查一遍：

```bash
grep -rinE 'imei|serial-?number|mac-?address|private-?key|secret|password|qfuse|die-?id' dts/
```

## 7. 版权与再分发

- 设备树二进制与 Linux/Android 内核及厂商实现相关，原始版权和许可证应以
  **Qualcomm Innovation Center、Xiaomi 及 Linux 内核来源中的实际声明**为准；
  本仓库随附 GPL-2.0-only 文本和来源说明（见上层 `LICENSE`），不替代对原始来源的许可证核对。
- 本目录只放设备树/bootconfig 这类 GPL 材料，**不含**完整 boot.img / vendor_boot.img、
  厂商专有可执行程序、私钥或测试密钥；需要完整镜像请从你自己设备的对应分区提取。
- 若小米后续在官方分支发布 `qcom/opensource/devicetree` 符号化源码，建议以官方源码为准，
  本反编译版本可作为运行时事实的交叉校验。
