# 实验 13：其他异常、中断与计数器

任务来源：[CPU 设计实战，实践任务 13](https://bookdown.org/loongson/_book3/chapter-support-exception.html#subsec-exp13)。

## 实现

在 `exp12/myCPU` 的基础上扩展 `exp13/myCPU`：

- ID 检测 ADEF、BRK、INE 和中断，EX 检测字/半字访存的 ALE。
- 38 位异常总线携带 6 类独立异常标志和 BADV/PC；WB 按架构优先级编码 ECODE，统一保存异常状态并跳转。
- 异常指令及其后的指令不得写通用寄存器、CSR 或数据 SRAM；冲刷可取消除法。
- 新增 ECFG、BADV、TID、TCFG、TVAL、TICLR。BADV 仅在地址异常时更新。
- 支持两路软件中断、八路硬件中断、定时器中断，由 CRMD.IE 与 ECFG.LIE 共同屏蔽。
- TCFG 支持单次/周期定时，TICLR 的有效写 1 清除定时器中断。
- 64 位稳定计数器每拍递增，支持 `rdcntvl.w`、`rdcntvh.w` 和读取 TID 的 `rdcntid`。
- ID 等待较早的 CSR 写指令提交后再判断中断和特权级，保证紧邻 CSR 修改的指令使用新状态。

顶层新增 `hw_int_in[7:0]`，高电平有效，映射至 ESTAT.IS[9:2]。输入应来自 CPU 时钟域；异步外部源需在 SoC 中同步。现有实验 SoC 没有外部中断源，因此在 `soc_lite_top.v` 中接零；独立定向测试逐路驱动它。

`if_stage.v`、`alu.v`、`tools.v`、`regfile.v` 沿用 exp12。取指重定向继续通过顶层的冲刷优先级实现。

## 仿真

在仓库根目录使用 PowerShell：

```powershell
# 原始 func / golden_trace：58 个功能测试点
./exp13/soc_verify/soc_bram/testbench/run_sim.ps1

# 八路硬件中断、ECFG/IE 屏蔽、异常状态及 store 取消
./exp13/soc_verify/soc_bram/testbench/run_sim.ps1 -HardwareInterrupts
```

脚本默认使用 `E:/Xilinx/Vivado/2019.2/bin`，可通过 `-VivadoBin` 指定其他安装位置，通过 `-BuildDir` 指定输出目录。默认输出位于系统临时目录 `arch-exp13-func`。

脚本在临时目录生成测试平台副本，仅调整文件路径、波形输出、进度打印和超时保护，保留原始 trace 与计分比较。同步 SRAM 模型已修正 `wdata` 端口方向和 Verilog 数组声明。

## 验证记录（2026-10-25）

- Vivado 2019.2 编译、展开通过。
- 原始 58/58 功能测试点通过，最终输出 `----PASS!!!`，仿真结束时间 1,997,175 ns。
- 八路硬件中断的屏蔽、IE 控制、ERA/ESTAT/PRMD/CRMD 检查通过；待处理中断紧邻 ECFG 写入时，后续两个 store 均未访问 SRAM。
- `xc7a200tfbg676-1` 的 CPU 独立综合通过，无错误、无综合关键警告、无推断锁存器。综合仍有未使用端口等普通警告。
- 未进行布局布线、时序收敛或 FPGA 上板验证。

`patch/exp12_to_exp13.patch` 仅记录 CPU 源码相对于 exp12 的差异。仿真脚本、SoC 中断输入连接和 SRAM 模型修正在该补丁之外。
