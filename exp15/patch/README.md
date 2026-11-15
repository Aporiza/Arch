# exp14 到 exp15 的 CPU 补丁

`exp14-vs-exp15-myCPU.patch` 仅包含 CPU RTL 的差异：新增 `mycpu_core.v`、替换 `mycpu_top.v`、新增 `sram_axi_bridge.v`。其它 CPU 模块与 exp14 一致，无需包含在补丁中。不包含官方 AXI SoC 实验环境、测试脚本或文档。

补丁路径统一为 `a/myCPU/...` 和 `b/myCPU/...`，应用目标应是包含 exp14 版本 `myCPU` 的实验目录副本。当前 exp15 已完成修改，不要对其重复应用，也不要直接覆盖原 exp14。

例如在仓库根目录，对一个已复制 exp14 `myCPU` 的新实验目录 `target_exp` 应用：

```powershell
git -c core.autocrlf=true apply --check --directory=target_exp exp15/patch/exp14-vs-exp15-myCPU.patch
git -c core.autocrlf=true apply --directory=target_exp exp15/patch/exp14-vs-exp15-myCPU.patch
```

已在隔离目录中复制 exp14 CPU、执行 `git apply --check` 和实际应用，并逐文件核对结果与当前 exp15 CPU 一致（忽略 Windows/Linux 换行差异）。
