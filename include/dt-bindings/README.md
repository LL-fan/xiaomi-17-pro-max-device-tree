# dt-bindings headers

本目录只保留 **SM8850 / canoe 平台专属** 的设备树绑定头（时钟控制器 GCC/CAMCC/DISPCC/…、
interconnect、IPCC mailbox），共 11 个，来自小米开源内核 `popsicle-w-oss`
的 `include/dt-bindings/`。

## 为什么 standalone `make` 不需要它们

`dts/` 下发布的 DTS 是从出厂固件**精确反编译**得到的，所有 `#define` 宏都已被展开为
立即数（例如 `<0x10c>` 而不是 `<GCC_UART_CFG_AHB_CLK>`），因此仅用 `dtc` 即可重新编译，
不依赖任何头文件。

## 什么时候需要这些头 + 上游头

如果你要把 DTS **还原成符号化、可随内核维护** 的形式（用宏代替立即数、`#include` 标准
绑定），则除了本目录的平台专属头，还需要 Linux 上游通用绑定，来自 GKI common 内核树：

```
# GKI common kernel (android16-6.12, Linux 6.12.92)
include/dt-bindings/**        # 上游通用绑定 (gpio/clock/interrupt/regulator/...)
# MiCode vendor glue (popsicle-w-oss)
include/dt-bindings/clock/qcom,*-canoe.h   # 即本目录这 11 个
```

获取上游内核：

```bash
git clone -b android16-6.12 https://android.googlesource.com/kernel/common
# 小米厂商层（含本目录头）
git clone -b popsicle-w-oss https://github.com/MiCode/Xiaomi_Kernel_OpenSource
```

在内核树内编译符号化 DTS 时，把本目录合并进 `include/dt-bindings/`，并通过
`DTC_FLAGS += -@ -i include` 让 dtc 能找到头与 include 路径。

## 本目录清单

- `clock/qcom,gcc-canoe.h`            Global Clock Controller
- `clock/qcom,camcc-canoe.h`          Camera Clock Controller
- `clock/qcom,dispcc-canoe.h`         Display Clock Controller
- `clock/qcom,gpucc-canoe.h`          GPU Clock Controller
- `clock/qcom,videocc-canoe.h`        Video Clock Controller
- `clock/qcom,evacc-canoe.h`          Video/Analog(EV-A) Clock Controller
- `clock/qcom,tcsrcc-canoe.h`         TCSR Clock Controller
- `clock/qcom,cambistmclkcc-canoe.h`  Camera Bist Master Clock
- `clock/qcom,gxclkctl-canoe.h`       Graphics extra clock control
- `interconnect/qcom,canoe.h`         NoC interconnect IDs
- `mailbox/qcom-ipcc-canoe.h`         Inter-Processor Communication Controller
