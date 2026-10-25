
// ID：指令译码、寄存器堆读写、立即数生成和分支判断。
// 译码结果和操作数在时钟上升沿一起进入 ID/EX 流水寄存器。
module id_stage (
    // 时钟与低有效同步复位
    input  wire         clk,
    input  wire         resetn,
    input  wire         flush,
    input  wire         has_int,
    input  wire [1:0]   current_plv,
    input  wire         csr_pending,

    // 来自 IF/ID 的指令与 PC
    input  wire         if_id_valid,
    input  wire [31:0]  if_id_pc,
    input  wire [31:0]  if_id_inst,

    // 来自 WB 的寄存器堆写端口
    input  wire         rf_we,
    input  wire [4:0]   rf_waddr,
    input  wire [31:0]  rf_wdata,

    // EX/MEM 中尚未就绪的 load、CSR 等结果，用于数据相关检测。
    input  wire         ex_pending_we,
    input  wire [4:0]   ex_pending_dest,
    input  wire         mem_pending_we,
    input  wire [4:0]   mem_pending_dest,
    // EX 当前 ALU 结果和 EX/MEM ALU 结果前递到译码阶段。
    input  wire         ex_forward_we,
    input  wire [4:0]   ex_forward_dest,
    input  wire [31:0]  ex_forward_data,
    input  wire         mem_forward_we,
    input  wire [4:0]   mem_forward_dest,
    input  wire [31:0]  mem_forward_data,
    // EX 除法未完成时保持 ID/EX，不能覆盖当前除法指令。
    input  wire         ex_allow_in,
    // 无数据相关、无冲刷且 EX 可以接收新指令时为 1。
    // 数据相关时冻结 IF 并向 EX 注入气泡；EX 忙时保持 ID/EX。
    output wire         ready_go,

    // 反馈给 IF 的分支结果（组合逻辑）
    output wire         br_taken,
    output wire [31:0]  br_target,

    // ID/EX 寄存器输出，供 EX 阶段使用
    output reg          id_ex_valid,
    output reg  [31:0]  id_ex_pc,
    output reg  [31:0]  id_ex_rj_value,
    output reg  [31:0]  id_ex_rkd_value,
    output reg  [31:0]  id_ex_imm,
    output reg  [18:0]  id_ex_alu_op,
    output reg          id_ex_src1_is_pc,
    output reg          id_ex_src2_is_imm,
    output reg          id_ex_res_from_mem,
    output reg          id_ex_mem_we,
    output reg  [1:0]   id_ex_mem_size,
    output reg          id_ex_load_unsigned,
    output reg          id_ex_gr_we,
    output reg  [4:0]   id_ex_dest,
    // [81:78]: CSR读、CSR写、ertn、syscall；[77:64]: CSR编号；
    // [63:32]: 写掩码；[31:0]: 写数据。随指令传到 WB 提交。
    // [83:82]: {rdcntvh, rdcntvl}，其余位保持 exp12 布局。
    output reg  [83:0]  id_ex_csr_bus,
    // {异常有效, Ecode[5:0], BADV[31:0]}；本实验 EsubCode 均为零。
    output reg  [38:0]  id_ex_ex_bus
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
wire         inst_add_w     = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1] & op_19_15_d[0];
wire         inst_sub_w     = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1] & op_19_15_d[2];
wire         inst_slt       = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1] & op_19_15_d[4];
wire         inst_sltu      = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1] & op_19_15_d[5];
wire         inst_nor       = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1] & op_19_15_d[8];
wire         inst_and       = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1] & op_19_15_d[9];
wire         inst_or        = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1] & op_19_15_d[10];
wire         inst_xor       = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1] & op_19_15_d[11];
wire         inst_slli_w    = op_31_26_d[0] & op_25_22_d[1] & op_21_20_d[0] & op_19_15_d[1];
wire         inst_srli_w    = op_31_26_d[0] & op_25_22_d[1] & op_21_20_d[0] & op_19_15_d[9];
wire         inst_srai_w    = op_31_26_d[0] & op_25_22_d[1] & op_21_20_d[0] & op_19_15_d[17];
wire         inst_addi_w    = op_31_26_d[0] & op_25_22_d[10];
wire         inst_ld_w      = op_31_26_d[10] & op_25_22_d[2];
wire         inst_st_w      = op_31_26_d[10] & op_25_22_d[6];
// exp11：访存指令共用 op[31:26]，低四位区分访问宽度和符号扩展。
wire         inst_ld_b      = op_31_26_d[10] & op_25_22_d[0];
wire         inst_ld_h      = op_31_26_d[10] & op_25_22_d[1];
wire         inst_ld_bu     = op_31_26_d[10] & op_25_22_d[8];
wire         inst_ld_hu     = op_31_26_d[10] & op_25_22_d[9];
wire         inst_st_b      = op_31_26_d[10] & op_25_22_d[4];
wire         inst_st_h      = op_31_26_d[10] & op_25_22_d[5];
wire         inst_jirl      = op_31_26_d[19];
wire         inst_b         = op_31_26_d[20];
wire         inst_bl        = op_31_26_d[21];
wire         inst_beq       = op_31_26_d[22];
wire         inst_bne       = op_31_26_d[23];
wire         inst_blt       = op_31_26_d[24];
wire         inst_bge       = op_31_26_d[25];
wire         inst_bltu      = op_31_26_d[26];
wire         inst_bgeu      = op_31_26_d[27];
wire         inst_lu12i_w   = op_31_26_d[5] & ~inst[25];
wire         inst_pcaddu12i = op_31_26_d[7] & ~inst[25];

// exp10 新增的立即数、寄存器移位和乘除法指令。
wire         inst_slti     = op_31_26_d[0] & op_25_22_d[8];
wire         inst_sltui    = op_31_26_d[0] & op_25_22_d[9];
wire         inst_andi     = op_31_26_d[0] & op_25_22_d[13];
wire         inst_ori      = op_31_26_d[0] & op_25_22_d[14];
wire         inst_xori     = op_31_26_d[0] & op_25_22_d[15];
wire         inst_sll_w    = op_31_26_d[0] & op_25_22_d[0] &
                             op_21_20_d[1] & op_19_15_d[14];
wire         inst_srl_w    = op_31_26_d[0] & op_25_22_d[0] &
                             op_21_20_d[1] & op_19_15_d[15];
wire         inst_sra_w    = op_31_26_d[0] & op_25_22_d[0] &
                             op_21_20_d[1] & op_19_15_d[16];
wire         inst_mul_w    = op_31_26_d[0] & op_25_22_d[0] &
                             op_21_20_d[1] & op_19_15_d[24];
wire         inst_mulh_w   = op_31_26_d[0] & op_25_22_d[0] &
                             op_21_20_d[1] & op_19_15_d[25];
wire         inst_mulh_wu  = op_31_26_d[0] & op_25_22_d[0] &
                             op_21_20_d[1] & op_19_15_d[26];
wire         inst_div_w    = op_31_26_d[0] & op_25_22_d[0] &
                             op_21_20_d[2] & op_19_15_d[0];
wire         inst_mod_w    = op_31_26_d[0] & op_25_22_d[0] &
                             op_21_20_d[2] & op_19_15_d[1];
wire         inst_div_wu   = op_31_26_d[0] & op_25_22_d[0] &
                             op_21_20_d[2] & op_19_15_d[2];
wire         inst_mod_wu   = op_31_26_d[0] & op_25_22_d[0] &
                             op_21_20_d[2] & op_19_15_d[3];

// exp12：CSR 指令用 rj 字段区分读、写和掩码交换；syscall 的 code 不参与译码。
wire         inst_csrrd   = (inst[31:24] == 8'h04) && (rj == 5'd0);
wire         inst_csrwr   = (inst[31:24] == 8'h04) && (rj == 5'd1);
wire         inst_csrxchg = (inst[31:24] == 8'h04) && (rj != 5'd0) && (rj != 5'd1);
wire         inst_ertn    = (inst == 32'h0648_3800);
wire         inst_syscall = (inst[31:15] == 17'h00056);
wire         inst_break   = (inst[31:15] == 17'h00054);
wire         inst_rdcntvl = (inst[31:10] == 22'h000018) && (rj == 5'd0);
wire         inst_rdcntvh = (inst[31:10] == 22'h000019) && (rj == 5'd0);
wire         inst_rdcntid = (inst[31:10] == 22'h000018) && (rd == 5'd0) && (rj != 5'd0);
wire         csr_re       = inst_csrrd | inst_csrwr | inst_csrxchg | inst_rdcntid;
wire         csr_we       = inst_csrwr | inst_csrxchg;

// ALU 控制位：各位含义与 alu.v 的 alu_op 接口一致。
wire [18:0]  alu_op = {
    inst_mod_wu,   // [18] 无符号取余
    inst_div_wu,   // [17] 无符号除法
    inst_mod_w,    // [16] 有符号取余
    inst_div_w,    // [15] 有符号除法
    inst_mulh_wu,  // [14] 无符号乘法高位
    inst_mulh_w,   // [13] 有符号乘法高位
    inst_mul_w,    // [12] 乘法低位
    inst_lu12i_w,  // [11] 高位立即数
    (inst_srai_w | inst_sra_w),   // [10] 算术右移
    (inst_srli_w | inst_srl_w),   // [ 9] 逻辑右移
    (inst_slli_w | inst_sll_w),   // [ 8] 逻辑左移
    (inst_xor | inst_xori),       // [ 7] 按位异或
    (inst_or | inst_ori),         // [ 6] 按位或
    inst_nor,                     // [ 5] 按位或非
    (inst_and | inst_andi),       // [ 4] 按位与
    (inst_sltu | inst_sltui),     // [ 3] 无符号比较
    (inst_slt | inst_slti),       // [ 2] 有符号比较
    inst_sub_w,                   // [ 1] 减法
    (inst_add_w | inst_addi_w | inst_ld_w | inst_st_w |
     inst_ld_b | inst_ld_h | inst_ld_bu | inst_ld_hu |
     inst_st_b | inst_st_h |
     inst_jirl | inst_bl | inst_pcaddu12i) // [0] 加法
};

// 分支比较和存储指令以 rd 作为第二个源寄存器
wire         is_cond_branch = inst_beq | inst_bne | inst_blt | inst_bge |
                              inst_bltu | inst_bgeu;
wire         is_load = inst_ld_w | inst_ld_b | inst_ld_h | inst_ld_bu | inst_ld_hu;
wire         is_store = inst_st_w | inst_st_b | inst_st_h;
// 所有已支持指令的白名单，未命中的编码产生 INE，不能写入 rd。
wire         inst_valid = (|alu_op) | is_cond_branch | inst_b | csr_re |
                          inst_ertn | inst_syscall | inst_break |
                          inst_rdcntvl | inst_rdcntvh;
wire         adef = (|if_id_pc[1:0]) || ((current_plv == 2'd3) && if_id_pc[31]);
// 优先级：中断 > 取指地址错 > 译码异常；ALE 在 EX 检测。
wire         id_exception = has_int | adef | inst_syscall | inst_break | !inst_valid;
wire [5:0]   id_ecode = has_int ? 6'h00 : adef ? 6'h08 :
                       inst_syscall ? 6'h0b : inst_break ? 6'h0c : 6'h0d;
wire         src_reg_is_rd = is_cond_branch | is_store | csr_we;
wire         src1_is_pc    = inst_jirl | inst_bl | inst_pcaddu12i;
wire         src2_is_imm   = inst_slli_w | inst_srli_w | inst_srai_w |
                            inst_addi_w | is_load | is_store |
                            inst_lu12i_w | inst_jirl  | inst_bl     |
                            inst_pcaddu12i | inst_slti | inst_sltui |
                            inst_andi | inst_ori | inst_xori;

// jirl/bl 使用 PC + 4 作为链接地址；lu12i.w 将立即数放入高 20 位
wire [31:0]  imm = (inst_jirl | inst_bl) ? 32'd4 :
                    inst_lu12i_w          ? {i20, 12'b0} :
                    inst_pcaddu12i        ? {{12{i20[19]}}, i20, 12'b0} :
                    (inst_andi | inst_ori | inst_xori) ? {20'b0, i12} :
                                           {{20{i12[11]}}, i12};

// 分支偏移按字对齐：符号扩展后左移两位
wire [31:0]  br_offs = (inst_b | inst_bl) ? {{4{i26[25]}}, i26, 2'b0} :
                                            {{14{i16[15]}}, i16, 2'b0};
wire [31:0]  jirl_offs = {{14{i16[15]}}, i16, 2'b0};

// 后续阶段控制：访存结果选择、存储使能、通用寄存器写使能
wire         res_from_mem = is_load,
             mem_we = is_store,
             gr_we = inst_valid & ~is_store & ~is_cond_branch & ~inst_b &
                     ~inst_ertn & ~id_exception;
// 00：字节，01：半字，10：字；无符号标志仅对 load 有意义。
wire [1:0]   mem_size = (inst_ld_b | inst_ld_bu | inst_st_b) ? 2'b00 :
                        (inst_ld_h | inst_ld_hu | inst_st_h) ? 2'b01 : 2'b10;
wire         load_unsigned = inst_ld_bu | inst_ld_hu;

// bl 写入 r1；其余指令的目的寄存器来自 rd
wire [4:0]   dest      = inst_bl ? 5'd1 : inst_rdcntid ? rj : rd;
wire [4:0]   rf_raddr2 = src_reg_is_rd ? rd : rk;

// 寄存器堆读数据及分支比较
wire [31:0]  rj_rf_value,
             rkd_rf_value;
wire [31:0]  rj_value,
             rkd_value;
assign rj_value = (rj != 5'd0 && ex_forward_we && (ex_forward_dest == rj))
                ? ex_forward_data
                : (rj != 5'd0 && mem_forward_we && (mem_forward_dest == rj))
                ? mem_forward_data
                : (rj != 5'd0 && rf_we && (rf_waddr == rj))
                ? rf_wdata
                : rj_rf_value;
assign rkd_value = (rf_raddr2 != 5'd0 && ex_forward_we &&
                    (ex_forward_dest == rf_raddr2))
                 ? ex_forward_data
                 : (rf_raddr2 != 5'd0 && mem_forward_we &&
                    (mem_forward_dest == rf_raddr2))
                 ? mem_forward_data
                 : (rf_raddr2 != 5'd0 && rf_we && (rf_waddr == rf_raddr2))
                 ? rf_wdata
                 : rkd_rf_value;
wire         rj_eq_rd = (rj_value == rkd_value);
wire         rj_lt_rd  = $signed(rj_value) < $signed(rkd_value);
wire         rj_ltu_rd = rj_value < rkd_value;

// 只检查指令真正读取的源寄存器，避免把立即数字段误判成寄存器。
wire use_rj = inst_add_w | inst_sub_w | inst_slt | inst_sltu |
              inst_nor | inst_and | inst_or | inst_xor |
              inst_slli_w | inst_srli_w | inst_srai_w | inst_addi_w |
              inst_sll_w | inst_srl_w | inst_sra_w |
              inst_slti | inst_sltui | inst_andi | inst_ori | inst_xori |
              inst_mul_w | inst_mulh_w | inst_mulh_wu |
              inst_div_w | inst_mod_w | inst_div_wu | inst_mod_wu |
              is_load | is_store | inst_jirl | is_cond_branch | inst_csrxchg;
wire use_rkd = inst_add_w | inst_sub_w | inst_slt | inst_sltu |
               inst_nor | inst_and | inst_or | inst_xor |
               inst_sll_w | inst_srl_w | inst_sra_w |
               inst_mul_w | inst_mulh_w | inst_mulh_wu |
               inst_div_w | inst_mod_w | inst_div_wu | inst_mod_wu |
               is_store | is_cond_branch | csr_we;

// load 和 CSR 读结果都到 WB 才可用，EX/MEM 中的这些指令需要阻塞。
// ALU 结果从 EX、EX/MEM 前递，WB 结果从写回端口前递；r0 恒为零。
// 存储数据和分支操作数也必须检查。
wire hazard_rj = use_rj && (rj != 5'd0) &&
                 ((ex_pending_we  && ex_pending_dest  == rj) ||
                  (mem_pending_we && mem_pending_dest == rj));
wire hazard_rkd = use_rkd && (rf_raddr2 != 5'd0) &&
                  ((ex_pending_we  && ex_pending_dest  == rf_raddr2) ||
                   (mem_pending_we && mem_pending_dest == rf_raddr2));
// 较早的 CSR 写必须先提交，才能按新 PLV/IE/ECFG/ESTAT 判断异常。
// 异常指令无需等待普通操作数，但不能越过 EX 的较早指令。
assign ready_go = !flush && ex_allow_in && !csr_pending &&
                  !(resetn && if_id_valid && !id_exception && (hazard_rj || hazard_rkd));

// 寄存器堆：ID 提供读地址，WB 提供写使能、目的寄存器号和写回数据
regfile u_rf (
    .clk    (clk),
    .raddr1 (rj),
    .rdata1 (rj_rf_value),
    .raddr2 (rf_raddr2),
    .rdata2 (rkd_rf_value),
    .we     (rf_we),
    .waddr  (rf_waddr),
    .wdata  (rf_wdata)
);

// 有符号与无符号分支分别比较；只有有效且可以前进的指令才允许改写 PC。
assign br_taken = ((inst_beq & rj_eq_rd) |
                   (inst_bne & ~rj_eq_rd) |
                   (inst_blt & rj_lt_rd) |
                   (inst_bge & ~rj_lt_rd) |
                   (inst_bltu & rj_ltu_rd) |
                   (inst_bgeu & ~rj_ltu_rd) |
                   inst_jirl | inst_bl | inst_b) & if_id_valid & ready_go & resetn & ~id_exception;
assign br_target = (is_cond_branch | inst_bl | inst_b)
                 ? if_id_pc + br_offs
                 : rj_value + jirl_offs;

// ID/EX：操作数、目的寄存器号和控制位必须属于同一条指令。
always @(posedge clk) begin
    if (reset || flush)
        id_ex_valid <= 1'b0;
    else if (!ex_allow_in) begin
        // EX 正在执行多周期除法，保持本级流水寄存器。
    end else if (!ready_go)
        // 前端保持当前指令，后端继续前进；向 EX 注入一个无效槽。
        id_ex_valid <= 1'b0;
    else begin
        id_ex_valid        <= if_id_valid;
        id_ex_pc           <= if_id_pc;
        id_ex_rj_value     <= rj_value;
        id_ex_rkd_value    <= rkd_value;
        id_ex_imm          <= imm;
        id_ex_alu_op       <= id_exception ? 19'b0 : alu_op;
        id_ex_src1_is_pc   <= src1_is_pc;
        id_ex_src2_is_imm  <= src2_is_imm;
        id_ex_res_from_mem <= res_from_mem && !id_exception;
        id_ex_mem_we       <= mem_we && !id_exception;
        id_ex_mem_size     <= mem_size;
        id_ex_load_unsigned <= load_unsigned;
        id_ex_gr_we        <= gr_we;
        id_ex_dest         <= dest;
        id_ex_ex_bus       <= {id_exception, id_ecode, if_id_pc};
        id_ex_csr_bus      <= {inst_rdcntvh, inst_rdcntvl,
                               csr_re, csr_we && !id_exception,
                               inst_ertn && !id_exception, inst_syscall,
                               (inst_rdcntid ? 14'h0040 : inst[23:10]),
                               (inst_csrwr ? 32'hffff_ffff : rj_value),
                               rkd_value};
    end
end

endmodule
