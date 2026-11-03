# 实验 14：类 SRAM 接口与流水线阻塞

在 exp13 的五级流水线基础上，接入实验包的 `soc_hs_bram`，支持地址接受、数据返回分别延迟的类 SRAM 接口。保留既有的指令、前递、异常、中断和计数器功能。

## 先读哪些文件

1. `myCPU/mycpu_top.v`：查看级间连线。`ready_go` 仅在各阶段内部使用，顶层连接接收能力、有效位和数据。
2. `myCPU/if_stage.v`：查看 pre-IF 发请求、取指响应缓存、重定向后丢弃旧响应。
3. `myCPU/id_stage.v`：查看 `id_allow_in`、相关阻塞和 `br_stall`，分支在真正离开 ID 时才生效。
4. `myCPU/ex_stage.v`：查看地址对齐检查、数据请求、地址握手与除法完成状态的保留。
5. `myCPU/mem_stage.v`：查看 load/store 等待 `data_ok`、读数据锁存及向 WB 注入气泡。

## 握手约定

| 信号/条件 | 含义 |
| --- | --- |
| `req` | CPU 发起地址请求，地址、方向、大小、字节写使能和写数据一起有效 |
| `req && addr_ok` | 上升沿接收这笔请求；单独的 `addr_ok` 不表示产生了事务 |
| `data_ok` | 已接收请求完成，load 的读数据当拍有效，store 也会产生完成响应 |
| `valid` | 当前流水槽中有指令，包括等待中的指令 |
| `ready_go` | 本级工作完成，可向下一级提供有效项；不代表下一级已接收 |
| `allow_in` | 本级为空，或本级完成且下一级能接收，可以更新本级入口槽 |
| `valid && ready_go && next_allow_in` | 当前指令真正向下一级交接 |

沿用原工程的寄存器归属：IF/ID 放在 IF 模块内，但保存的是 ID 当前使用的指令；ID/EX 放在 ID 模块内，保存 EX 当前指令；EX/MEM、MEM/WB 同理。因而 ID 只有在 `ex_allow_in` 为 1 时才能更新 ID/EX，EX 只有在 `mem_allow_in` 为 1 时才能更新 EX/MEM。

pre-IF 是 IF 模块内部“选择下一 PC、发地址请求”的逻辑，不是新增的第六级模块。每个总线端口最多有一笔未完成事务；采用保守控制以便理解和验证，不以满吞吐取指为目标。遵循实验接口约定：响应最早出现在地址被接收后的下一拍；未被接收的请求可被取消。

## 容易出错的地方

- **ID 阻塞不等于 IF 没有空位。** IF 可以提前发请求，但返回时 ID 仍不接收，就必须保存指令及其 PC。`inst_buf_valid` 表示这份缓存占用，避免下一笔响应覆盖它。
- **分支必须只生效一次。** ID 只有在操作数就绪且 EX 可接收时产生 `br_taken`；`br_stall` 暂停尚未完成的分支之后的新请求。IF 锁存重定向目标，目标不会因为旧响应还没返回而丢失。
- **冲刷不能撤回已被外部接收的请求。** IF 用 `discard_pending` 标记旧请求，先等响应并丢弃，再请求最新目标。响应与重定向同拍时直接丢弃。
- **store 同样要等待响应。** 若地址握手后就丢掉 store，随后 load 可能错把 store 的 `data_ok` 当作自己的数据。
- **避免年轻 store 破坏精确异常。** MEM 中有旧异常或 ertn 时，用 `mem_req_block` 禁止年轻访存请求；WB 冲刷当拍禁止新请求。地址不对齐的访存只传递 ALE，不访问 RAM。
- **除法完成后可能仍不能交接。** 除法器的 `complete` 只有一拍，EX 用 `div_done` 保留完成状态，直到 MEM 能接收，或异常冲刷取消指令。
- **WB 不能重复提交。** MEM 等响应时保持 EX/MEM，同时每拍向 WB 送无效项；响应到达时锁存读数据，并且只提交一次。

官方 SoC 没有外部硬件中断源，因此 `hw_int_in` 接零；另外在 SoC 文件末尾恢复 `default_nettype wire`，避免本文件的禁止隐式连线设置影响后续官方外设。随机延迟包装器、外设逻辑、func 和 golden trace 保持实验包原样。

## 仿真与波形

在仓库根目录的 PowerShell 中运行：

```powershell
# 默认：官方随机短延迟
./exp14/tests/run_sim.ps1

# 无额外随机延迟、随机长延迟，分别使用独立输出目录
./exp14/tests/run_sim.ps1 -Seed 5500ff -BuildDir "$env:TEMP/arch-exp14-nodelay"
./exp14/tests/run_sim.ps1 -Seed 551234 -BuildDir "$env:TEMP/arch-exp14-longdelay"

# 取指缓存/冲刷、除法阻塞/取消、store 响应的定向测试
./exp14/tests/run_sim.ps1 -CornerCases -BuildDir "$env:TEMP/arch-exp14-corner"
```

默认使用 `D:/Xilinx/Vivado/2019.2/bin`，可用 `-VivadoBin` 修改。脚本保留官方测试的 trace 与计分比较，只在临时目录调整文件位置、打印频率、超时和随机种子，生成文件不会写进 RTL 目录。`tests/ram_model.v` 是回归使用的同步 RAM 行为模型，不加入官方 Vivado 工程，避免与 RAM IP 重名。协议监视器检查响应配对、阻塞时数据保持和计数器写回；官方 trace 对随时间变化的计数值会关闭比较，因此单独检查。

Vivado 中启动 Behavioral Simulation 后，在 Tcl Console 执行：

```tcl
source D:/Desktop/Vivado_prj/exp14/wave_exp14.tcl
```

观察 `req/addr_ok/data_ok` 的先后顺序，再看对应阶段的 `valid/ready_go/allow_in` 和 PC。地址等待时 EX 停留，数据等待时 MEM 停留；后级阻塞通过接收能力逐级向前传播。

## 验证记录（2026-11-02）

- Vivado 2019.2 编译、展开通过。
- 官方 58 个功能点在 `5500ff`、`5501ff`、`551234` 三种种子下均全部通过；地址等待、响应等待、取指缓存和丢弃旧响应均被覆盖。
- 定向测试通过：ID 阻塞时取指返回、连续重定向、响应与重定向同拍、错误取指地址、MEM 长阻塞跨过除法完成脉冲、除法中途取消后重启、store 等待响应且只提交一次。
- CPU 独立综合通过，无错误、无关键警告、无推断锁存器；存在未使用端口的普通警告。`tests/synth_check.tcl` 用于复现，生成报告保存在运行目录。
- 独立综合按 20 ns 时钟进行的时序估算 WNS 为 -1.933 ns，尚未达到该时钟目标。主要路径经过组合乘法、前递及前端控制，后续需要在完整工程中布局布线后优化和确认，不能把功能仿真通过当作 50 MHz 上板时序通过。
- FPGA 上板和布局布线后的时序验证尚未执行。
