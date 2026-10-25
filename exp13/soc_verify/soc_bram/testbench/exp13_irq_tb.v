`timescale 1ns / 1ps
// Exercise the real CPU's eight hardware interrupt inputs. The supplied func
// suite covers software/timer interrupts but its SoC ties these inputs low.
module exp13_irq_tb;
reg clk = 0;
always #5 clk = ~clk;
reg resetn = 0;
reg [7:0] hw_int = 0;
wire inst_en, data_en;
wire [3:0] inst_we, data_we;
wire [31:0] inst_addr, inst_wdata, data_addr, data_wdata;
reg [31:0] inst_rdata = 0;
wire [31:0] wb_pc, wb_data;
wire [3:0] wb_we;
wire [4:0] wb_num;
reg [31:0] rom [0:127];
reg [31:0] observed [0:31];
integer i, irq, mode, cycles, stores;

mycpu_top dut (
    .clk(clk), .resetn(resetn), .hw_int_in(hw_int),
    .inst_sram_en(inst_en), .inst_sram_we(inst_we),
    .inst_sram_addr(inst_addr), .inst_sram_wdata(inst_wdata),
    .inst_sram_rdata(inst_rdata), .data_sram_en(data_en),
    .data_sram_we(data_we), .data_sram_addr(data_addr),
    .data_sram_wdata(data_wdata), .data_sram_rdata(32'b0),
    .debug_wb_pc(wb_pc), .debug_wb_rf_we(wb_we),
    .debug_wb_rf_wnum(wb_num), .debug_wb_rf_wdata(wb_data)
);
always @(posedge clk) begin
    if (inst_en) inst_rdata <= rom[inst_addr[8:2]];
    if (resetn && |wb_we) observed[wb_num] = wb_data;
    if (resetn && data_en && |data_we) stores = stores + 1;
end

function [31:0] addi;
    input [4:0] rd;
    input [11:0] imm;
    begin addi = 32'h02800000 | {10'b0, imm, 5'b0, rd}; end
endfunction
function [31:0] csr_read;
    input [4:0] rd;
    input [13:0] num;
    begin csr_read = 32'h04000000 | {8'b0, num, 5'b0, rd}; end
endfunction
function [31:0] csr_write;
    input [4:0] rd;
    input [13:0] num;
    begin csr_write = csr_read(rd, num) | 32'h20; end
endfunction

task prepare;
    input [11:0] mask;
    input enable_ie;
    begin
        @(negedge clk);
        resetn = 0;
        hw_int = 0;
        stores = 0;
        for (i=0; i<32; i=i+1) observed[i] = 0;
        for (i=0; i<128; i=i+1) rom[i] = 32'h50000000;
        rom[0] = 32'h1438000c;  // lu12i.w r12, 0x1c000
        rom[1] = 32'h0384018c;  // ori r12, r12, 0x100
        rom[2] = csr_write(12, 14'hc);
        rom[3] = addi(13, enable_ie ? 12'hc : 12'h8);
        rom[4] = csr_write(13, 14'h0);
        rom[5] = addi(14, mask);
        rom[6] = csr_write(14, 14'h4);
        rom[7] = addi(25, 12'h55);
        rom[8] = 32'h50000000; // interrupt the branch at 0x1c000020
        rom[64] = csr_read(20, 14'h6);
        rom[65] = csr_read(21, 14'h5);
        rom[66] = csr_read(22, 14'h1);
        rom[67] = csr_read(23, 14'h0);
        rom[68] = addi(24, 12'h1);
        repeat (4) @(negedge clk);
        resetn = 1;
    end
endtask

task wait_handler;
    begin
        cycles = 0;
        while (observed[24] != 1 && cycles < 100) begin
            @(negedge clk);
            cycles = cycles + 1;
        end
        if (observed[24] !== 1) $fatal(1, "No interrupt handler");
    end
endtask

initial begin
    // Each line: ECFG mask blocks it; CRMD.IE blocks it; then enabled entry.
    for (irq=0; irq<8; irq=irq+1) begin
        for (mode=0; mode<3; mode=mode+1) begin
            prepare(mode == 0 ? 12'b0 : (12'b1 << (irq+2)), mode != 1);
            repeat (60) @(negedge clk);
            if (observed[25] !== 32'h55) $fatal(1, "Initialization did not retire");
            // A different, masked line must not trap.
            hw_int = 8'b1 << ((irq+1)%8);
            repeat (40) @(negedge clk);
            if (observed[24] !== 0) $fatal(1, "Masked IRQ trapped");
            hw_int = 8'b1 << irq;
            if (mode == 2) begin
                wait_handler;
                if (observed[20] !== 32'h1c000020 || observed[21][21:16] !== 6'h0 ||
                    observed[21][9:2] !== (8'b1 << irq) ||
                    observed[22][2:0] !== 3'h4 || observed[23][2:0] !== 3'h0)
                    $fatal(1, "Incorrect interrupt state for line %0d", irq);
            end else begin
                repeat (60) @(negedge clk);
                if (observed[24] !== 0) $fatal(1, "Disabled IRQ trapped");
            end
        end
        $display("Hardware IRQ %0d: mask, IE and exception state PASS", irq);
    end

    // IRQ already pending as ECFG is enabled: the very next instruction is a
    // store, followed by another store. Neither may reach data SRAM.
    prepare(12'h4, 1'b1);
    rom[7] = 32'h29800000; // st.w r0, r0, 0
    rom[8] = 32'h29801000; // st.w r0, r0, 4
    hw_int = 8'h1;
    wait_handler;
    if (stores != 0 || observed[20] !== 32'h1c00001c)
        $fatal(1, "Interrupt/store precision failed");
    $display("Pending IRQ after CSR write: precise store cancellation PASS");
    $display("EXP13_IRQ_PASS");
    $finish;
end
initial begin #1000000; $fatal(1, "IRQ test timeout"); end
endmodule
