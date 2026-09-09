# 分区与设备树镜像布局（partitions.md）

说明 Xiaomi 17 Pro Max（popsicle）上设备树相关分区的位置、格式，以及
base dtb / board overlay / qtvm overlay 三者如何组合成运行时设备树。

## 1. A/B 与动态分区

- 设备为 **A/B 双槽 + Virtual A/B**（`BOARD_USES_VIRTUAL_AB := true`），所有可启动分区都有
  `_a` / `_b` 两份；当前测试机槽位为 `_a`。
- `system / system_ext / product / vendor / odm / system_dlkm / vendor_dlkm` 位于 super 动态分区；
  bootloader 与设备树相关分区为独立物理分区。

## 2. 设备树相关分区（by-name → 块设备）

| by-name 分区 | 块节点(当前槽) | 内容 | 分区大小 |
|---|---|---|---|
| `boot_a` | sde14 | GKI 内核 Image + generic ramdisk（header v4） | 100663296 (96 MiB) |
| `init_boot_a` | sde30 | init ramdisk（header v4） | 8388608 (8 MiB) |
| `vendor_boot_a` | sde25 | vendor ramdisk + **base dtb**（VNDRBOOT v4） | 100663296 (96 MiB) |
| `dtbo_a` | sde18 | **板级 overlay**（Android dt_table） | 25165824 (24 MiB) |
| `qtvm_dtbo_a` | sde22 | Gunyah 虚拟机 overlay（dt_table，2 项） | 5 MiB |
| `cpucp_dtb_a` | sde31 | **注意：是 ELF 固件，不是设备树** | — |
| `dtbo_b` / `vendor_boot_b` | sde61 / sde68 | B 槽对应分区 | 同上 |

> 避坑：`cpucp_dtb` 名字里带 dtb，但文件头是 ELF（协处理器固件），`dtc` 无法解析，
> 不属于设备树，本仓库不收录。

## 3. vendor_boot 内的 base dtb（VNDRBOOT header v4）

从 `vendor_boot_a` 解出的头部关键字段：

| 字段 | 值 |
|---|---|
| magic | `VNDRBOOT` |
| header_version | 4 |
| page_size | 4096 (0x1000) |
| header_size | 2128 |
| vendor ramdisk 总大小 | 15924489 |
| **dtb_size** | **4511568** |
| **dtb_addr** | 0x1f00000 |

这份 dtb 就是 `dts/xiaomi-17-pro-max-common.dtsi`（SoC 基础树，model
“Canoe Alt. Thermal Profile v2 SoC”，compatible `qcom,canoe`）。
用 AOSP `unpack_bootimg --boot_img vendor_boot.img --out out/` 可取出其中的 `dtb`。

## 4. dtbo / qtvm_dtbo 的 dt_table 格式

Android `dt_table_header`（大端）：

```
offset  size  field
0       u32   magic = 0xD7B7AB1E
4       u32   total_size
8       u32   header_size = 32
12      u32   dt_entry_size = 32
16      u32   dt_entry_count
20      u32   dt_entries_offset = 32
24      u32   page_size (设备 dtbo=4096)
28      u32   version (设备=0)
# 紧跟 dt_entry_count 个 dt_table_entry（各 32B）：
#   dt_size, dt_offset, id, rev, custom[4]
# 每个 dtb 从 page_size 对齐的 dt_offset 开始
```

- `dtbo_a`：1 个表项，板级 overlay（1463920 B，model “Popsicle based on SM8850”），
  即 `dts/overlays/board-popsicle-overlay.dts`。
- `qtvm_dtbo_a`：2 个表项（SVM 513062 B / OEMVM 9674 B），即 `dts/overlays/qtvm-*.dts`。
- `scripts/mkdtimage.py` 用纯 Python 实现该格式的 `create` / `dump`，`make` 用它把
  编译出的 overlay 重新打包成 `build/dtbo.img`。

## 5. 运行时组合关系

```
vendor_boot.dtb (base, qcom,canoe)
        +  dtbo 表项0 (board popsicle overlay)
        =  最终生效设备树  ≡  /proc/device-tree  ≡  dts/xiaomi-17-pro-max.dts
qtvm_dtbo (SVM/OEMVM) 仅在 Gunyah 虚拟机启动时叠加，正常 Android 不使用
```

合并由 bootloader 在启动时完成；本仓库在主机侧用 `fdtoverlay` 离线复现了同一结果
（`fdtoverlay -i base.dtb -o merged.dtb board-overlay.dtbo`），合并后不再含 `fragment@`
/ `__overlay__`，是一棵扁平完整树。

## 6. 提取与刷写

提取（从一台可 root 的真机，自动完成 dd→解包→反编译→合并）：

```bash
scripts/extract-from-device.sh ./from-device
```

刷写（fastbootd/bootloader，仅设备树相关）：

```bash
fastboot flash vendor_boot_a vendor_boot.img   # 含 base dtb
fastboot flash dtbo_a        build/dtbo.img     # 板级 overlay
# 单独验证合并树也可把 merged dtb 放进 vendor_boot 的 dtb 区域后重打包
```

> 注意：fastboot 中**不存在** `vbmeta_vendor_a/b` 分区（本设备无此分区），刷写脚本若
> 写该分区会报 `No such partition`，应跳过——这也是 `patches/0001` 移除其 AVB 链的原因。
