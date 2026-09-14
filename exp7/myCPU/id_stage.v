// ID：指令译码、寄存器堆读写、立即数生成和分支判断。
// 译码结果和操作数在时钟上升沿一起进入 ID/EX 流水寄存器。
module id_stage (
    // 时钟与低有效同步复位
    input  wire         clk,
    input  wire         resetn,

    // 来自 IF/ID 的指令与 PC
    input  wire         if_id_valid,
    input  wire [31:0]  if_id_pc,
    input  wire [31:0]  if_id_inst,

    // 来自 WB 的寄存器堆写端口
    input  wire         rf_we,
    input  wire [4:0]   rf_waddr,
    input  wire [31:0]  rf_wdata,

    // 反馈给 IF 的分支结果（组合逻辑）
    output wire         br_taken,
    output wire [31:0]  br_target,

    // ID/EX 寄存器输出，供 EX 阶段使用
    output reg          id_ex_valid,
    output reg  [31:0]  id_ex_pc,
    output reg  [31:0]  id_ex_rj_value,
    output reg  [31:0]  id_ex_rkd_value,
    output reg  [31:0]  id_ex_imm,
    output reg  [11:0]  id_ex_alu_op,
    output reg          id_ex_src1_is_pc,
    output reg          id_ex_src2_is_imm,
    output reg          id_ex_res_from_mem,
    output reg          id_ex_mem_we,
    output reg          id_ex_gr_we,
    output reg  [4:0]   id_ex_dest
);

// 指令字段提取
wire         reset    = ~resetn;
wire [31:0]  inst     = if_id_inst;
wire [5:0]   op_31_26 = inst[31:26];
wire [3:0]   op_25_22 = inst[25:22];
wire [1:0]   op_21_20 = inst[21:20];
wire [4:0]   op_19_15 = inst[19:15];
wire [4:0]   rd       = inst[4:0],
             rj = inst[9:5],
             rk = inst[14:10];
wire [11:0]  i12      = inst[21:10];
wire [19:0]  i20      = inst[24:5];
wire [15:0]  i16      = inst[25:10];
wire [25:0]  i26      = {inst[9:0], inst[25:10]};

// 操作码独热译码
wire [63:0]  op_31_26_d;
wire [15:0]  op_25_22_d;
wire [3:0]   op_21_20_d;
wire [31:0]  op_19_15_d;

decoder_6_64 u0 (
    .in  (op_31_26),
    .out (op_31_26_d)
);

decoder_4_16 u1 (
    .in  (op_25_22),
    .out (op_25_22_d)
);

decoder_2_4 u2 (
    .in  (op_21_20),
    .out (op_21_20_d)
);

decoder_5_32 u3 (
    .in  (op_19_15),
    .out (op_19_15_d)
);

// 指令识别：算术、逻辑、移位、访存和跳转
wire         inst_add_w   = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1] & op_19_15_d[0];
wire         inst_sub_w   = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1] & op_19_15_d[2];
wire         inst_slt     = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1] & op_19_15_d[4];
wire         inst_sltu    = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1] & op_19_15_d[5];
wire         inst_nor     = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1] & op_19_15_d[8];
wire         inst_and     = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1] & op_19_15_d[9];
wire         inst_or      = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1] & op_19_15_d[10];
wire         inst_xor     = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1] & op_19_15_d[11];
wire         inst_slli_w  = op_31_26_d[0] & op_25_22_d[1] & op_21_20_d[0] & op_19_15_d[1];
wire         inst_srli_w  = op_31_26_d[0] & op_25_22_d[1] & op_21_20_d[0] & op_19_15_d[9];
wire         inst_srai_w  = op_31_26_d[0] & op_25_22_d[1] & op_21_20_d[0] & op_19_15_d[17];
wire         inst_addi_w  = op_31_26_d[0] & op_25_22_d[10];
wire         inst_ld_w    = op_31_26_d[10] & op_25_22_d[2];
wire         inst_st_w    = op_31_26_d[10] & op_25_22_d[6];
wire         inst_jirl    = op_31_26_d[19];
wire         inst_b       = op_31_26_d[20];
wire         inst_bl      = op_31_26_d[21];
wire         inst_beq     = op_31_26_d[22];
wire         inst_bne     = op_31_26_d[23];
wire         inst_lu12i_w = op_31_26_d[5] & ~inst[25];

// ALU 控制位：各位含义与 alu.v 的 alu_op 接口一致
wire [11:0]  alu_op = {
    inst_lu12i_w,  // [11] 高位立即数
    inst_srai_w,   // [10] 算术右移
    inst_srli_w,   // [ 9] 逻辑右移
    inst_slli_w,   // [ 8] 逻辑左移
    inst_xor,     // [ 7] 按位异或
    inst_or,      // [ 6] 按位或
    inst_nor,     // [ 5] 按位或非
    inst_and,     // [ 4] 按位与
    inst_sltu,    // [ 3] 无符号比较
    inst_slt,     // [ 2] 有符号比较
    inst_sub_w,   // [ 1] 减法
    (inst_add_w | inst_addi_w | inst_ld_w | inst_st_w | inst_jirl | inst_bl) // [0] 加法
};

// 分支比较和存储指令以 rd 作为第二个源寄存器
wire         src_reg_is_rd = inst_beq | inst_bne | inst_st_w;
wire         src1_is_pc    = inst_jirl | inst_bl;
wire         src2_is_imm   = inst_slli_w | inst_srli_w | inst_srai_w |
                            inst_addi_w | inst_ld_w   | inst_st_w   |
                            inst_lu12i_w | inst_jirl  | inst_bl;

// jirl/bl 使用 PC + 4 作为链接地址；lu12i.w 将立即数放入高 20 位
wire [31:0]  imm = (inst_jirl | inst_bl) ? 32'd4                  :
                   inst_lu12i_w          ? {i20, 12'b0}          :
                                           {{20{i12[11]}}, i12};

// 分支偏移按字对齐：符号扩展后左移两位
wire [31:0]  br_offs = (inst_b | inst_bl) ? {{4{i26[25]}}, i26, 2'b0} :
                                         {{14{i16[15]}}, i16, 2'b0};
wire [31:0]  jirl_offs = {{14{i16[15]}}, i16, 2'b0};

// 后续阶段控制：访存结果选择、存储使能、通用寄存器写使能
wire         res_from_mem = inst_ld_w,
             mem_we = inst_st_w,
             gr_we = ~inst_st_w & ~inst_beq & ~inst_bne & ~inst_b;

// bl 写入 r1；其余指令的目的寄存器来自 rd
wire [4:0]   dest      = inst_bl ? 5'd1 : rd;
wire [4:0]   rf_raddr2 = src_reg_is_rd ? rd : rk;

// 寄存器堆读数据及分支比较
wire [31:0]  rj_value,
             rkd_value;
wire         rj_eq_rd = (rj_value == rkd_value);

// 寄存器堆：ID 提供读地址，WB 提供写使能、目的寄存器号和写回数据
regfile u_rf (
    .clk    (clk),
    .raddr1 (rj),
    .rdata1 (rj_value),
    .raddr2 (rf_raddr2),
    .rdata2 (rkd_value),
    .we     (rf_we),
    .waddr  (rf_waddr),
    .wdata  (rf_wdata)
);

// 只有有效指令才能发起跳转；beq/bne 比较寄存器值，b/bl/jirl 无条件跳转
assign br_taken = ((inst_beq & rj_eq_rd) |
                   (inst_bne & ~rj_eq_rd) |
                   inst_jirl | inst_bl | inst_b) & if_id_valid;
assign br_target = (inst_beq | inst_bne | inst_bl | inst_b)
                 ? if_id_pc + br_offs
                 : rj_value + jirl_offs;

// ID/EX：操作数、目的寄存器号和控制位必须属于同一条指令。
always @(posedge clk) begin
    if (reset)
        id_ex_valid <= 1'b0;
    else begin
        id_ex_valid        <= if_id_valid;
        id_ex_pc           <= if_id_pc;
        id_ex_rj_value     <= rj_value;
        id_ex_rkd_value    <= rkd_value;
        id_ex_imm          <= imm;
        id_ex_alu_op       <= alu_op;
        id_ex_src1_is_pc   <= src1_is_pc;
        id_ex_src2_is_imm  <= src2_is_imm;
        id_ex_res_from_mem <= res_from_mem;
        id_ex_mem_we       <= mem_we;
        id_ex_gr_we        <= gr_we;
        id_ex_dest         <= dest;
    end
end

endmodule
