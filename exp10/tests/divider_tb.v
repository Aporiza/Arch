`timescale 1ns / 1ps

module divider_tb;
reg         clk = 1'b0;
reg         resetn = 1'b0;
reg         start = 1'b0;
reg         is_signed = 1'b0;
reg  [31:0] dividend = 32'b0;
reg  [31:0] divisor = 32'b0;
wire        complete;
wire [31:0] quotient;
wire [31:0] remainder;

always #5 clk = ~clk;

divider dut (
    .clk       (clk),
    .resetn    (resetn),
    .start     (start),
    .is_signed (is_signed),
    .dividend  (dividend),
    .divisor   (divisor),
    .complete  (complete),
    .quotient  (quotient),
    .remainder (remainder)
);

reg signed [31:0] signed_dividend;
reg signed [31:0] signed_divisor;
reg [31:0] expected_quotient;
reg [31:0] expected_remainder;
integer cycles;
integer i;

task check;
    input        signed_mode;
    input [31:0] lhs;
    input [31:0] rhs;
    begin
        signed_dividend = lhs;
        signed_divisor = rhs;
        if (rhs == 32'b0) begin
            expected_quotient = 32'hffff_ffff;
            expected_remainder = lhs;
        end else if (signed_mode && lhs == 32'h8000_0000 &&
                     rhs == 32'hffff_ffff) begin
            // LoongArch signed overflow case: INT_MIN / -1.
            expected_quotient = 32'h8000_0000;
            expected_remainder = 32'b0;
        end else if (signed_mode) begin
            expected_quotient = signed_dividend / signed_divisor;
            expected_remainder = signed_dividend % signed_divisor;
        end else begin
            expected_quotient = lhs / rhs;
            expected_remainder = lhs % rhs;
        end

        @(negedge clk);
        is_signed = signed_mode;
        dividend = lhs;
        divisor = rhs;
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        cycles = 0;
        while (!complete && cycles < 34) begin
            @(negedge clk);
            cycles = cycles + 1;
        end
        if (!complete || quotient !== expected_quotient ||
            remainder !== expected_remainder) begin
            $display("FAIL signed=%b lhs=%h rhs=%h q=%h expected=%h r=%h expected=%h cycles=%0d",
                     signed_mode, lhs, rhs, quotient, expected_quotient,
                     remainder, expected_remainder, cycles);
            $finish;
        end
    end
endtask

initial begin
    repeat (2) @(negedge clk);
    resetn = 1'b1;
    check(1'b1, 32'd13, 32'd5);
    check(1'b1, -32'd13, 32'd5);
    check(1'b1, 32'd13, -32'd5);
    check(1'b1, -32'd13, -32'd5);
    check(1'b1, 32'h8000_0000, -32'd1);
    check(1'b1, 32'h8000_0000, 32'd3);
    check(1'b0, 32'hffff_ffff, 32'd3);
    check(1'b0, 32'hffff_ffff, 32'h8000_0000);
    check(1'b1, 32'd9, 32'b0);
    check(1'b0, 32'hffff_ffff, 32'b0);
    for (i = 0; i < 100; i = i + 1) begin
        check(i[0], $random, $random);
    end
    $display("PASS: divider directed and random cases");
    $finish;
end

endmodule
