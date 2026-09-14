// 五级流水线顶层：只声明连线并例化各阶段。
// IF/ID、ID/EX、EX/MEM、MEM/WB 寄存器分别封装在 IF、ID、EX、MEM 内。
// ID 的分支结果反馈给 IF；WB 的写端口反馈给 ID 内部的寄存器堆。
module mycpu_top (
    // 时钟与低有效复位
    input  wire         clk,
    input  wire         resetn,

    // 指令 SRAM 接口
    output wire         inst_sram_en,
    output wire [3:0]   inst_sram_we,
    output wire [31:0]  inst_sram_addr,
    output wire [31:0]  inst_sram_wdata,
    input  wire [31:0]  inst_sram_rdata,

    // 数据 SRAM 接口
    output wire         data_sram_en,
    output wire [3:0]   data_sram_we,
    output wire [31:0]  data_sram_addr,
    output wire [31:0]  data_sram_wdata,
    input  wire [31:0]  data_sram_rdata,

    // 写回调试接口
    output wire [31:0]  debug_wb_pc,
    output wire [3:0]   debug_wb_rf_we,
    output wire [4:0]   debug_wb_rf_wnum,
    output wire [31:0]  debug_wb_rf_wdata
);

// ID → IF：分支反馈
wire         br_taken;
wire [31:0]  br_target;

// IF → ID：指令有效位、PC 和指令字
wire         if_id_valid;
wire [31:0]  if_id_pc,
             if_id_inst;

// ID → EX：操作数、立即数和后续阶段控制
wire         id_ex_valid;
wire [31:0]  id_ex_pc,
             id_ex_rj_value,
             id_ex_rkd_value,
             id_ex_imm;
wire [11:0]  id_ex_alu_op;
wire         id_ex_src1_is_pc,
             id_ex_src2_is_imm,
             id_ex_res_from_mem,
             id_ex_mem_we,
             id_ex_gr_we;
wire [4:0]   id_ex_dest;

// EX → MEM：运算结果、存储数据和后续阶段控制
wire         ex_mem_valid;
wire [31:0]  ex_mem_pc,
             ex_mem_alu_result,
             ex_mem_store_data;
wire         ex_mem_res_from_mem,
             ex_mem_mem_we,
             ex_mem_gr_we;
wire [4:0]   ex_mem_dest;

// MEM → WB：写回数据和控制
wire         mem_wb_valid;
wire [31:0]  mem_wb_pc,
             mem_wb_alu_result,
             mem_wb_mem_result;
wire         mem_wb_res_from_mem,
             mem_wb_gr_we;
wire [4:0]   mem_wb_dest;

// WB → ID：寄存器堆写回
wire         rf_we;
wire [4:0]   rf_waddr;
wire [31:0]  rf_wdata;

// IF：PC、取指和 IF/ID 寄存器
if_stage u_if (
    .clk             (clk),
    .resetn          (resetn),
    .redirect_i      (br_taken),
    .redirect_pc_i   (br_target),
    .inst_sram_rdata (inst_sram_rdata),
    .inst_sram_en    (inst_sram_en),
    .inst_sram_we    (inst_sram_we),
    .inst_sram_addr  (inst_sram_addr),
    .inst_sram_wdata (inst_sram_wdata),
    .if_id_valid     (if_id_valid),
    .if_id_pc        (if_id_pc),
    .if_id_inst      (if_id_inst)
);

// ID：译码、寄存器堆、分支判断和 ID/EX 寄存器
id_stage u_id (
    .clk                (clk),
    .resetn             (resetn),
    .if_id_valid        (if_id_valid),
    .if_id_pc           (if_id_pc),
    .if_id_inst         (if_id_inst),
    .rf_we              (rf_we),
    .rf_waddr           (rf_waddr),
    .rf_wdata           (rf_wdata),
    .br_taken           (br_taken),
    .br_target          (br_target),
    .id_ex_valid        (id_ex_valid),
    .id_ex_pc           (id_ex_pc),
    .id_ex_rj_value     (id_ex_rj_value),
    .id_ex_rkd_value    (id_ex_rkd_value),
    .id_ex_imm          (id_ex_imm),
    .id_ex_alu_op       (id_ex_alu_op),
    .id_ex_src1_is_pc   (id_ex_src1_is_pc),
    .id_ex_src2_is_imm  (id_ex_src2_is_imm),
    .id_ex_res_from_mem (id_ex_res_from_mem),
    .id_ex_mem_we       (id_ex_mem_we),
    .id_ex_gr_we        (id_ex_gr_we),
    .id_ex_dest         (id_ex_dest)
);

// EX：ALU 和 EX/MEM 寄存器
ex_stage u_ex (
    .clk                 (clk),
    .resetn              (resetn),
    .id_ex_valid         (id_ex_valid),
    .id_ex_pc            (id_ex_pc),
    .id_ex_rj_value      (id_ex_rj_value),
    .id_ex_rkd_value     (id_ex_rkd_value),
    .id_ex_imm           (id_ex_imm),
    .id_ex_alu_op        (id_ex_alu_op),
    .id_ex_src1_is_pc    (id_ex_src1_is_pc),
    .id_ex_src2_is_imm   (id_ex_src2_is_imm),
    .id_ex_res_from_mem  (id_ex_res_from_mem),
    .id_ex_mem_we        (id_ex_mem_we),
    .id_ex_gr_we         (id_ex_gr_we),
    .id_ex_dest          (id_ex_dest),
    .ex_mem_valid        (ex_mem_valid),
    .ex_mem_pc           (ex_mem_pc),
    .ex_mem_alu_result   (ex_mem_alu_result),
    .ex_mem_store_data   (ex_mem_store_data),
    .ex_mem_res_from_mem (ex_mem_res_from_mem),
    .ex_mem_mem_we       (ex_mem_mem_we),
    .ex_mem_gr_we        (ex_mem_gr_we),
    .ex_mem_dest         (ex_mem_dest)
);

// MEM：数据 SRAM 接口和 MEM/WB 寄存器
mem_stage u_mem (
    .clk                 (clk),
    .resetn              (resetn),
    .ex_mem_valid        (ex_mem_valid),
    .ex_mem_pc           (ex_mem_pc),
    .ex_mem_alu_result   (ex_mem_alu_result),
    .ex_mem_store_data   (ex_mem_store_data),
    .ex_mem_res_from_mem (ex_mem_res_from_mem),
    .ex_mem_mem_we       (ex_mem_mem_we),
    .ex_mem_gr_we        (ex_mem_gr_we),
    .ex_mem_dest         (ex_mem_dest),
    .data_sram_rdata     (data_sram_rdata),
    .data_sram_en        (data_sram_en),
    .data_sram_we        (data_sram_we),
    .data_sram_addr      (data_sram_addr),
    .data_sram_wdata     (data_sram_wdata),
    .mem_wb_valid        (mem_wb_valid),
    .mem_wb_pc           (mem_wb_pc),
    .mem_wb_alu_result   (mem_wb_alu_result),
    .mem_wb_mem_result   (mem_wb_mem_result),
    .mem_wb_res_from_mem (mem_wb_res_from_mem),
    .mem_wb_gr_we        (mem_wb_gr_we),
    .mem_wb_dest         (mem_wb_dest)
);

// WB：写回选择与调试输出
wb_stage u_wb (
    .mem_wb_valid        (mem_wb_valid),
    .mem_wb_pc           (mem_wb_pc),
    .mem_wb_alu_result   (mem_wb_alu_result),
    .mem_wb_mem_result   (mem_wb_mem_result),
    .mem_wb_res_from_mem (mem_wb_res_from_mem),
    .mem_wb_gr_we        (mem_wb_gr_we),
    .mem_wb_dest         (mem_wb_dest),
    .rf_we               (rf_we),
    .rf_waddr            (rf_waddr),
    .rf_wdata            (rf_wdata),
    .debug_wb_pc         (debug_wb_pc),
    .debug_wb_rf_we      (debug_wb_rf_we),
    .debug_wb_rf_wnum    (debug_wb_rf_wnum),
    .debug_wb_rf_wdata   (debug_wb_rf_wdata)
);

endmodule
