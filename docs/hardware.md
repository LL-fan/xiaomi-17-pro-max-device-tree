# 硬件规格与设备树节点对照（hardware.md）

本文记录 Xiaomi 17 Pro Max（popsicle / canoe / SM8850）的真实硬件信息，以及它们在
设备树中的位置。规格来自真机 `getprop` / `/sys` / `/proc/device-tree` 实测，节点路径
来自 `dts/xiaomi-17-pro-max.dts`（base + board overlay 合并后的最终树）。

## 1. 板级识别

| 项 | 值 | 设备树位置 |
|---|---|---|
| 根 model（base） | `Qualcomm Technologies, Inc. Canoe Alt. Thermal Profile v2 SoC` | `/ model` |
| 根 compatible（base） | `qcom,canoe` | `/ compatible` |
| 板级 model（dtbo） | `Qualcomm Technologies, Inc. Popsicle based on SM8850` | overlay `/ model` |
| 板级 compatible | `qcom,canoe-mtp qcom,canoe qcom,canoep-mtp qcom,canoep qcom,mtp` | overlay `/ compatible` |
| qcom,msm-id | `<0x1000294 0x20000>` | `/ qcom,msm-id` |
| qcom,board-id / xiaomi,miboard-id | `<0x00 0x00>` / `<0x01 0x00>` | 根节点 |
| qcom,chipid | `0x44050a01`（硬件常量，非个人数据） | SoC 节点 |

## 2. SoC / CPU / 虚拟化

- Qualcomm Snapdragon **SM8850**，`machine=CANOE`，`family=Snapdragon`，revision 2.0，ARM64，8 核。
- 中断控制器：GIC + 电源域中断控制器 `/soc/pdc@b370000`；PCIe 侧 `/soc/pcie_pdc`。
- GPU（Adreno）：`/soc/qcom,kgsl-3d0@3d00000`（`interrupt-names = kgsl_3d0_irq/cx_host_irq`）。
- 虚拟化：Gunyah hypervisor（bootconfig `hypervisor=gunyah`），对应 `qtvm-*` 两份 overlay
  （SVM 标准虚拟机、OEMVM），正常 Android 不启用。

## 3. 内存与存储

| 项 | 值 / 节点 |
|---|---|
| 运行内存 | 12 GB（真机 `/proc/meminfo` MemTotal = 11273956 kB） |
| `/ memory` | `device_type="memory"`，物理基址由 reserved-memory 切分 |
| reserved-memory | 大量 `/reserved-memory/*` 固定预留区（GPU/相机/视频/安全世界等） |
| UFS 主控 | `/soc/ufshc@1d84000`，`compatible="qcom,ufshc"` |
| UFS PHY | `compatible="qcom,ufs-phy-qmp-v4-canoe"`（UFS 4.x QMP PHY） |
| UFS OPP/DMA | `/soc/ufshc-opp-table`、`/soc/ufshc_dma_resv_region` |
| 闪存型号 | KLUFG8RHKF-F0H1（真机 `/sys/block/sda/device/model`） |

## 4. 屏幕与显示

| 项 | 值 / 节点 |
|---|---|
| 分辨率 / 密度 | 1200 × 2608，480 dpi（真机 `wm size/density`） |
| 刷新率 | LTPO 24/30/60/90/120 Hz（DSI 内含多组 timing，`timing@0..`） |
| HDR | HDR10 / HLG / HDR10+ / Dolby Vision（type 1–4），峰值约 3200 nit |
| 显示主控 | `/soc/qcom,mdss_mdp@9800000`（SDE/MDSS） |
| DSI 控制器 | `compatible="qcom,dsi-ctrl-hw-v2.10"` |
| DSI PHY | `compatible="qcom,dsi-phy-v7.2"` |
| 面板 | `qcom,mdss_dsi_nt37801_wqhd_plus_cmd`（**Novatek NT37801** AMOLED，CMD 模式） |
| 面板供电 | `qcom,amoled-regulator`、`qcom,amoled-ecm` |
| 外接显示 | `qcom,dp-display`（DisplayPort，经 USB-C DP combo PHY） |
| 写回/外屏 | `qcom,wb-display`（writeback） |

## 5. 触控与屏下指纹（FOD）

设备树同时保留多供应商触控方案（量产分料）：

| compatible | 说明 |
|---|---|
| `goodix,gt9615` | 汇顶 Goodix GT9615 触控 |
| `synaptics,tcm-spi` | 新思 Synaptics TCM（SPI） |
| `fuda,nu1671` | Fuda / Novatek NU1671 触控 |
| `mca_sc96281_fod_data` / `mca_nu1671_fod_data` | 屏下光学指纹（FOD）坐标/校准数据节点 |
| `fingerprint-screen`、`fingerprint_1v8_vdd` | 屏下指纹供电与挂载节点 |

> 指纹 HAL 为 Goodix AIDL（运行时 `IFingerprint/default`，sensor 5）。FOD 的按压区域、
> 亮度补偿等静态参数在上述 `*_fod_data` 节点。

## 6. 音频

| 单元 | compatible / 节点 |
|---|---|
| 主控/Codec 数字宏 | `/soc/spf_core_platform/lpass-cdc/`：`rx-macro@6AC0000`、`wsa-macro@6B00000`、`wsa2-macro@6AA0000`、`va-macro@7660000` |
| 主 Codec | `qcom,wcd939x-codec` / `qcom,wcd939x-i2c`（另保留 wcd9378 兼容） |
| 智能功放 | `qcom,wsa884x` ×2（wsa-macro）+ `qcom,wsa884x_2` ×2（wsa2-macro），共 4 颗 |
| 触觉/升压 | `cirrus,cs40l26a`（触觉/扬声器 boost） |
| 智能功放(备) | `cirrus,cs35l43` ×2 |
| SoundWire | aliases `swr0..swr4` 指向各 macro master |

## 7. 相机

- 相机子系统时钟：`qcom,canoe-camcc`、`qcom,canoe-cambistmclkcc`（见 `include/dt-bindings/clock/`）。
- 传感器接口：多路 `qcom,cam-i2c-sensor` / `cam-i2c-actuator` / `cam-i2c-eeprom`（CCI/I2C），
  两个 `qcom,cam-sensor` 前端，CSIPHY/CSID/CSIPHY-SD 相关匹配约 80 处。
- 闪光灯：`qcom,camera-flash`（经 PMIC `pmh0101-flash-led`）。
- 相机 SMMU：`qcom,msm-cam-smmu` 及其 cb；同步/请求管理 `cam-sync`、`cam-req-mgr`、`cam-crm-v3`。
- 具体 sensor（OV/S5K/IMX 等）由 vendor 相机模块在运行时按 EEPROM ID 枚举，设备树只描述
  通用 CSI/CCI 通道与供电/复位，故不写死单一 sensor 型号。

## 8. 电源 / PMIC / 电池 / 充电

- SPMI 仲裁：`qcom,canoe-spmi-pmic-arb`，总线 `/soc/.../spmi@c426000`，下挂多颗 PMIC：
  **PMH0110、PMH0101、PMK8850、PMK8350**（gpio/rtc/pon/pwm/flash/bcl 等子功能齐全）。
- 整机约 879 处 regulator 引用、810 处 clock 引用，构成完整电源/时钟树。
- 电池：7500 mAh（`charge_full_design=7500000` µAh），Li-poly。
- 充电相关节点：`xiaomi,charger_partition`、`mca,quick_charger`、`mca,business_charger`、
  `mca_charger_thermal`、`mca,qcom_subpmic`。
- 热管理：`thermal-zones` 体系（合并树中 thermal 相关匹配上百处）。

## 9. 连接（USB / PCIe / 总线）

| 单元 | 节点 |
|---|---|
| USB 主控 | `/soc/ssusb@a600000/dwc3@a600000`（DWC3，cmdline `androidboot.usbcontroller=a600000.dwc3`） |
| USB2 PHY | `/soc/hsphy@88e3000` |
| USB3/DP combo PHY | `/soc/ssphy@88e8000`（`qcom,usb-ssphy-qmp-dp-combo`） |
| PCIe | `/soc/pcie@1c00000/pcie_rp`，`cnss_pci0`（连接 Wi-Fi/连接模组） |
| 调试 UART | `/soc/qcom,qupv3_1_geni_se@ac0000/qcom,qup_uart@a9c000`，**115200n8**（`serial0`/`stdout-path`） |
| 高速 UART | `qupv3_3_geni_se@19c0000/qup_uart@1994000`（`hsuart0`） |
| I2C/SPI | QUPv3_1@ac0000（i2c0–6）、QUPv3_2@8c0000、QUPv3_3@19c0000 下多路 i2c/spi/uart |

## 10. 启动命令行（chosen/bootargs 摘要）

`/chosen/bootargs` 关键项：`console=ttyMSM0,115200n8`、`androidboot.hardware=qcom`、
`androidboot.usbcontroller=a600000.dwc3`、`cpufreq.default_governor=performance`、
`rcu_nocbs=0-7`、`irqaffinity=0-1`、`kpti=0`、`kasan=off` 等；完整 bootconfig 见
`original/stock-bootconfig.txt`。

## 11. 已验证 / 未验证

见 [`testing.md`](testing.md) 的节点验证清单。简表：

- 已在真机验证：启动、CPU/时钟/regulator/PMIC、UFS、USB、PCIe 连接、DSI 点亮与 120Hz、
  触控、音频出声、电池/充电。
- 部分验证：相机（通道完整，具体成像由 vendor 模块负责）。
- 未在本机验证：Gunyah qtvm SVM/OEMVM overlay（需要虚拟化场景）。
