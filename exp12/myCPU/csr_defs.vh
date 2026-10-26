// CSR 编号和异常标志集中定义，流水总线不再依赖散落的数字位号。
`ifndef MYCPU_CSR_DEFS_VH
`define MYCPU_CSR_DEFS_VH

`define CSR_CRMD      14'h0000
`define CSR_PRMD      14'h0001
`define CSR_ECFG      14'h0004
`define CSR_ESTAT     14'h0005
`define CSR_ERA       14'h0006
`define CSR_BADV      14'h0007
`define CSR_EENTRY    14'h000c
`define CSR_SAVE0     14'h0030
`define CSR_SAVE1     14'h0031
`define CSR_SAVE2     14'h0032
`define CSR_SAVE3     14'h0033
`define CSR_TID       14'h0040
`define CSR_TCFG      14'h0041
`define CSR_TVAL      14'h0042
`define CSR_TICLR     14'h0044

// {csr_re, csr_we, ertn, syscall, csr_num[13:0], wmask[31:0], wdata[31:0]}
`define CSR_BUS_WD    82
`define CSR_BUS_RE    81
`define CSR_BUS_WE    80
`define CSR_BUS_ERTN  79

// 异常逐项携带到 WB，再按优先级编码；地址由 PC/ALU 结果通路保存。
`define EX_FLAGS_WD   6
`define EX_INT        5
`define EX_ADEF       4
`define EX_ALE        3
`define EX_SYS        2
`define EX_BRK        1
`define EX_INE        0

`define ECODE_INT     6'h00
`define ECODE_ADE     6'h08
`define ECODE_ALE     6'h09
`define ECODE_SYS     6'h0b
`define ECODE_BRK     6'h0c
`define ECODE_INE     6'h0d
`define ESUBCODE_ADEF 9'b0

`endif

