# 编译验证与真机测试（testing.md）

## 1. 主机环境

| 工具 | 版本 | 用途 |
|---|---|---|
| dtc / fdtoverlay / fdtget / fdtdump | device-tree-compiler **1.6.1** | 反编译 / 编译 / 合并 / 读取 |
| python3 | 3.x（仅标准库） | dt_table 打包解析 `scripts/mkdtimage.py` |
| 验证平台 | WSL2 Ubuntu 22.04（任意 Linux 均可） | `make` |

## 2. 一键编译与校验

```bash
make            # 编译全部 dtb/dtbo 到 build/
make verify     # 重新编译并与 original/stock-* 对照
```

### `make verify` 当前结果（有限元数据检查）

```
== base SoC tree ==
PASS  model      = Qualcomm Technologies, Inc. Canoe Alt. Thermal Profile v2 SoC
PASS  compatible = qcom,canoe
== board overlay ==
PASS  model      = Qualcomm Technologies, Inc. Popsicle based on SM8850
PASS  compatible = qcom,canoe-mtp qcom,canoe qcom,canoep-mtp qcom,canoep qcom,mtp
== merged final tree ==
  model / compatible 同上；nodes=5607 properties=32760
RESULT pass=4 fail=0
```

当前脚本对 base 和 board overlay 的 `model`、`compatible` 共 4 项检查通过。
这些检查只覆盖根节点元数据，不代表所有节点和属性已经完成逐项等价验证。

### 各产物规模

| 产物 | 节点数 | 属性数 | 说明 |
|---|---|---|---|
| canoe-base.dtb（SoC 基础） | 4090 | 15166 | vendor_boot 内 dtb |
| board-popsicle.dtbo（板级） | 2164 | 18495 | dtbo 分区表项 |
| **xiaomi-17-pro-max.dtb（合并）** | **5607** | **32760** | 运行时最终树 |
| qtvm-svm.dtbo | 558 | 10046 | Gunyah SVM |
| qtvm-oemvm.dtbo | 70 | 223 | Gunyah OEMVM |

## 3. 为什么回编产物与原厂不是字节级一致

反编译（dtb→dts）再回编（dts→dtb）**不追求逐字节相同**，这是 dtc 的正常现象：

- 反编译会丢失符号表、注释、属性/节点的原始排列顺序，回编时 dtc 重新排布；
- 数值 phandle 会被重新分配；字符串块、结构块对齐可能变化；
- 因此字节大小会变（例：base 原厂 4511568 B → 回编 578091 B，主要是原厂 dtb 携带
  额外保留段/符号，回编只保留有效结构；board overlay 1463920 B → 1461907 B，仅差约 2 KB）。

当前 `make verify` 只比对根 `model`、`compatible` 等关键元数据，并统计节点/属性规模；
这不能单独证明整棵树逐节点等价。你也可以进一步逐节点 diff：

```bash
dtc -I dtb -O dts original/stock-base.dtb 2>/dev/null > /tmp/a.dts
dtc -I dtb -O dts build/canoe-base.dtb   2>/dev/null > /tmp/b.dts
diff <(grep -vE 'phandle|linux,phandle' /tmp/a.dts) \
     <(grep -vE 'phandle|linux,phandle' /tmp/b.dts)
# 忽略重排与 phandle 后应无实质差异
```

## 4. 关于编译告警（非错误）

`make` 会产生数千条 Warning（写入 `build/warnings.log`），`dtc` 仍返回 0、产物有效。
主要类别：`clocks_property`、`gpios_property`、`iommus_property`、`power_domains_property`、
`cooling_device_property`、`thermal_sensors_property`、`dmas_property`、
`unit_address_vs_reg`、`avoid_default_addr_size`、`reg_format`。

成因：单独编译 overlay 时缺少 base 提供的 `#clock-cells / #gpio-cells / #iommu-cells …`
上下文，dtc 无法校验这些引用的元数；以及反编译把部分地址写成默认尺寸。它们不影响
dtb 二进制的正确性（在完整 base 上 overlay 时这些 cells 由 base 提供）。如需消除，可在
完整内核树内以符号化 dts 连同 `#include` 的绑定头一起编译。

## 5. 真机核对方法

设备需要 root（测试机使用内核 su / KSU）。对比运行时树与本仓库合并树：

```bash
# 运行时最终设备树（二进制）
adb shell su 0 tar -c /proc/device-tree -f /data/local/tmp/pdt.tar   # 或逐节点 cat
# 关键根属性
adb shell su 0 sh -c 'cat /proc/device-tree/compatible | tr "\0" " "; echo'
adb shell su 0 sh -c 'cat /proc/device-tree/model; echo'
# 与 build/xiaomi-17-pro-max.dtb 反编译结果逐节点比对
```

也可用 `scripts/extract-from-device.sh` 从当前设备重新提取并反编译，再与 `dts/` 对比，
确认本仓库与你手上的机器/固件版本一致。

## 6. 节点功能验证清单

| 子系统 | 设备树 | 真机验证 | 结论 |
|---|---|---|---|
| CPU/GIC/PDC、时钟 GCC、regulator、SPMI PMIC | 完整 | 正常启动、频率/供电正常 | 已验证 |
| UFS 4.x（ufshc@1d84000 + QMP v4 PHY） | 完整 | 存储读写正常 | 已验证 |
| USB DWC3 + HS/SS(DP combo) PHY | 完整 | adb/MTP、USB-C 正常 | 已验证 |
| PCIe（cnss_pci0） | 完整 | Wi-Fi/连接模组工作 | 已验证 |
| 显示 MDSS/DSI v2.10/PHY v7.2、NT37801 面板、LTPO | 完整 | 点亮、120Hz、HDR 正常 | 已验证 |
| 触控 Goodix/Synaptics/Fuda、FOD 指纹数据 | 完整 | 触控、屏下指纹位置正常 | 已验证 |
| 音频 WCD939x + WSA884x×4 + CS40l26/CS35l43 | 完整 | 扬声器/听筒出声 | 已验证 |
| 电池/充电、thermal-zones | 完整 | 电量、充电、温控正常 | 已验证 |
| 相机 CSI/CCI/CSIPHY + cam-i2c-sensor | 通道完整 | 具体 sensor 由 vendor 模块枚举 | 部分验证 |
| Gunyah qtvm SVM / OEMVM overlay | 可回编 | 未在虚拟化场景启动 | 未验证 |

## 7. 刷写冒烟测试流程（供参考）

1. `make`，得到 `build/dtbo.img` 与（如需）重打包的 vendor_boot；
2. 进入 bootloader/fastbootd：`fastboot flash dtbo_a build/dtbo.img`；
3. 启动后检查 `dmesg`/`logcat` 是否有 `OF: overlay`、`failed to find node`、
   `could not find phandle` 等错误；
4. 核对 `/proc/device-tree/model`、屏幕/触控/音频等基本功能。

> 若 overlay apply 阶段报 phandle 找不到，通常是 base 与 overlay 版本不匹配——请确认
> 两者来自同一固件（本仓库已按同机同版本配对）。
