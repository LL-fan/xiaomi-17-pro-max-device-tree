# Xiaomi 17 Pro Max (popsicle / canoe / SM8850) Device Tree

#说点闲话~（ps：目前我的类原生系列还在持续开发中，希望多多关注酷安@岚岚凡~）
这是我的个人设备树项目，收录小米 17 Pro Max（产品代号 **popsicle**、
高通板级代号 **canoe**、SoC **Qualcomm SM8850**）的 Linux/Android
**设备树（Device Tree）源码与可复现构建内容**


本仓库的 DTS 是从**真机实际运行的出厂固件中精确提取并反编译**得到，再经过
`base dtb + 板级 overlay` 合并整理，用于还原设备运行时的设备树；仓库内
`make` 即可用上游 `dtc` 重新编译出 dtb/dtbo，并通过与原厂二进制的根节点元数据对照校验。

> 为什么是反编译而不是内核源码里的 dts？小米开源分支 `popsicle-w-oss`
> （MiCode/Xiaomi_Kernel_OpenSource）**未包含板级 dts 源**——其
> `arch/arm64/boot/dts/vendor` 是指向独立 `qcom/opensource/devicetree` 仓的符号链接，
> 而该仓未随分支发布。详见 [`original/notes.md`](original/notes.md)。

---

## 1. 设备概览

| 项目 | 规格 |
|---|---|
| 产品名 / 型号 | Xiaomi 17 Pro Max（`ro.product.model`） |
| 产品代号 | popsicle |
| 板级 / 平台代号 | canoe（`ro.board.platform`，SoC machine = CANOE） |
| SoC | Qualcomm Snapdragon **SM8850**，8 核，ARM64，rev 2.0 |
| 内存 | 12 GB（MemTotal ≈ 10.75 GiB） |
| 存储 | UFS 4.x，型号 KLUFG8RHKF-F0H1 |
| 屏幕 | 1200 × 2608，480 dpi，LTPO 24/30/60/90/120 Hz，HDR10/HLG/HDR10+/Dolby，峰值 3200 nit |
| 触控 / 屏下指纹 | Goodix GT9615 / Synaptics TCM / Fuda NU1671（多供应商），FOD 屏下光学指纹 |
| 音频 | WCD939x codec + WSA884x 智能功放 ×4 + Cirrus CS40L26a / CS35L43 |
| 电池 | 7500 mAh Li-poly |
| 内核 | GKI **android16-6.12 = Linux 6.12.92** |
| Bootloader | Qualcomm ABL（EDK2），A/B 虚拟分区（Virtual A/B），boot/vendor_boot header v4 |
| 出厂系统 | HyperOS / 澎湃 OS（Android 16） |

完整硬件与对应节点见 [`docs/hardware.md`](docs/hardware.md)。

---

## 2. 目录结构

```
xiaomi-17-pro-max-device-tree/
├── README.md                 # 本文件
├── LICENSE                   # 项目采用的许可证文本及来源说明
├── Makefile                  # make / make verify / make clean
├── dts/
│   ├── xiaomi-17-pro-max.dts            # 【主入口】base+overlay 合并后的完整最终树（52k 行）
│   ├── xiaomi-17-pro-max-common.dtsi    # SoC 基础树（vendor_boot 内 dtb，28k 行）
│   └── overlays/
│       ├── board-popsicle-overlay.dts   # 板级 overlay（dtbo 分区，26k 行）
│       ├── qtvm-svm-overlay.dts         # Gunyah SVM 虚拟机 overlay
│       └── qtvm-oemvm-overlay.dts       # Gunyah OEMVM overlay
├── include/dt-bindings/       # 仅 SM8850/canoe 专属绑定头（11 个）+ 依赖说明
├── configs/
│   └── build-config.example   # 在内核树内编译时的 build.config 模板（kleaf/build.sh）
├── scripts/
│   ├── build-dtb.sh           # dtc 编译 + 打包 dtbo.img
│   ├── mkdtimage.py           # 零依赖 Android dt_table(dtbo.img) 打包/解析
│   ├── verify-stock.sh        # 与原厂二进制对照校验
│   └── extract-from-device.sh # 从一台真机 adb 提取并反编译（复现本仓库来源）
├── docs/
│   ├── hardware.md            # 硬件规格 ↔ 设备树节点
│   ├── partitions.md          # 分区 / vendor_boot / dtbo / A-B 布局
│   └── testing.md             # 编译校验、真机核对、已验证/未验证节点
├── patches/                   # 接入构建时对设备配置/内核做过的真实改动
│   ├── 0001-device-prebuilt-kernel-dtbo-and-partitions.patch
│   ├── 0002-kernel-uapi-qualcomm-headers.patch
│   └── README.md
└── original/                  # 原厂二进制对照（非权威，权威源是 dts/）
    ├── stock-base.dtb         # vendor_boot 内 base dtb（出厂）
    ├── stock-dtbo.img         # dtbo 分区镜像（dt_table，已去 padding）
    ├── stock-qtvm-dtbo.img    # qtvm_dtbo 分区镜像
    ├── stock-bootconfig.txt   # vendor_boot bootconfig
    └── extracted/             # 逐份原始反编译文本（溯源用）
```

### 三层 DTS 的关系

```
                 出厂固件
 vendor_boot(dt b)                 dtbo 分区(board overlay)
 xiaomi-17-pro-max-common.dtsi  +  overlays/board-popsicle-overlay.dts
        └── SoC 公共基础树(canoe)         └── popsicle 板级差异(屏/触控/相机/供电…)
                          └── fdtoverlay 合并 ──┘
                          xiaomi-17-pro-max.dts  ← 用于还原运行时 /proc/device-tree 的完整树
```

- 想**读懂整块板子**：直接看 `dts/xiaomi-17-pro-max.dts`（完整、扁平、无 fragment）。
- 想看 **SoC 通用层与板级差异的边界**：对照 `*-common.dtsi` 与 `overlays/`。
- `qtvm-*` 是 Gunyah 虚拟化下 SVM/OEMVM 的叠加，正常 Android 不使用，仅供完整。

---

## 3. 快速编译

### 依赖

- `device-tree-compiler`（**dtc ≥ 1.6**，本仓库用 1.6.1 验证）
- `python3`（仅标准库，用于打包 dt_table）
- 不需要整套内核源码：反编译得到的常量已内联，`dtc` 即可独立编译。

Debian/Ubuntu/WSL：

```bash
sudo apt-get install device-tree-compiler
```

### 编译

```bash
make            # 等价 make dtb
```

产物在 `build/`：

| 产物 | 来源 | 对应真机位置 |
|---|---|---|
| `canoe-base.dtb` | common.dtsi | vendor_boot 内 `dtb` |
| `overlays/board-popsicle.dtbo` | board overlay | dtbo 分区表项 |
| `dtbo.img` | mkdtimage 打包 | 整个 dtbo 分区镜像 |
| `xiaomi-17-pro-max.dtb` | 完整合并树 | base+overlay 合并结果（便于单独刷/核对） |
| `overlays/qtvm-*.dtbo` | VM overlay | qtvm_dtbo 分区 |

### 校验（与原厂对照）

```bash
make verify
```

会重新编译并用 `fdtget` 比对原厂 `original/stock-*` 的 `model` / `compatible`，
当前脚本对 base 和 board overlay 的 `model`、`compatible` 共 4 项检查通过；
这不代表所有节点和属性已经完成逐项等价验证（见 [`docs/testing.md`](docs/testing.md)）。

### 清理

```bash
make clean
```

---

## 4. 在完整内核树内编译（可选）

若要把 DTS 还原成符号化、随内核维护的形式，请配合：

- GKI common：`git clone -b android16-6.12 https://android.googlesource.com/kernel/common`
- 小米厂商层：`git clone -b popsicle-w-oss https://github.com/MiCode/Xiaomi_Kernel_OpenSource`
- 平台专属绑定头见 `include/dt-bindings/`（已随仓库提供 11 个 canoe 头）
- 构建变量模板见 `configs/build-config.example`

---

## 5. 来源、许可证与合规

- DTS 由出厂 `vendor_boot` / `dtbo` / `qtvm_dtbo` 分区反编译得到，提取与合并流程、
  工具版本、两份 dtbo 的差异、隐私扫描结论见 [`original/notes.md`](original/notes.md)。
- 设备树相关内容的原始版权和许可证应以 Qualcomm、Xiaomi 及 Linux 内核
  的原始来源为准；本仓库随附 GPL-2.0-only 文本和来源说明，见 [`LICENSE`](LICENSE)。
- 已按关键词扫描，未发现明显的 MAC/IMEI/序列号/密钥/校准等个人或机密数据；
  这不是对所有隐私或厂商受限信息的绝对保证。文件中保留了
  `qcom,chipid`、相机拓扑 UUID 等硬件常量。
- `original/` 内二进制仅作对照，**权威源是 `dts/` 文本**；仓库不含完整 boot.img /
  vendor_boot.img、不含厂商专有可执行文件与任何私钥。

## 6. 节点验证状态（摘要）

| 子系统 | 状态 |
|---|---|
| CPU/中断/时钟/regulator/SPMI PMIC | 设备树存在，真机启动正常（已验证） |
| UFS / USB(dwc3) / PCIe | 设备树存在，真机存储/USB/外设工作（已验证） |
| 显示 DSI/DP、LTPO 刷新率、触控 | 设备树存在，真机点亮+120Hz+触控正常（已验证） |
| 音频 WCD939x/WSA884x、电池/充电 | 设备树存在，真机出声/充电正常（已验证） |
| 相机 sensor/CCI/CSIPHY | 节点完整，具体 sensor 由 vendor 模块运行时枚举（部分验证） |
| Gunyah qtvm SVM/OEMVM overlay | 已反编译并可回编，未在虚拟化场景实测（未验证） |

完整清单与真机核对方法见 [`docs/testing.md`](docs/testing.md)。
