module decoder_2_4(
    input  wire [ 1:0] in,
    output wire [ 3:0] out
);

genvar i;
generate for (i=0; i<4; i=i+1) begin
    assign out[i] = (in == i);
end endgenerate

endmodule


// 32 位恢复除法器：每拍生成一位商，商和余数在 complete 时有效。
// start 只需保持一拍；运算期间调用方应保持对应指令和控制信息。
module divider (
    input  wire        clk,
    input  wire        resetn,
    input  wire        start,
    input  wire        is_signed,
    input  wire [31:0] dividend,
    input  wire [31:0] divisor,
    output reg         complete,
    output reg  [31:0] quotient,
    output reg  [31:0] remainder
);

reg         busy;
reg  [31:0] divisor_abs;
reg  [31:0] quotient_work;
reg  [32:0] remainder_work;
reg  [5:0]  count;
reg         quotient_negative;
reg         remainder_negative;

wire dividend_negative = is_signed && dividend[31];
wire divisor_negative  = is_signed && divisor[31];
wire [31:0] dividend_abs = dividend_negative ? -dividend : dividend;
wire [31:0] divisor_abs_in = divisor_negative ? -divisor : divisor;

wire [32:0] trial_remainder = {remainder_work[31:0], quotient_work[31]};
wire          subtract_ok = trial_remainder >= {1'b0, divisor_abs};
wire [32:0]   next_remainder = subtract_ok
                             ? trial_remainder - {1'b0, divisor_abs}
                             : trial_remainder;
wire [31:0]   next_quotient = {quotient_work[30:0], subtract_ok};

always @(posedge clk) begin
    if (!resetn) begin
        busy               <= 1'b0;
        complete           <= 1'b0;
        quotient           <= 32'b0;
        remainder          <= 32'b0;
        divisor_abs        <= 32'b0;
        quotient_work      <= 32'b0;
        remainder_work     <= 33'b0;
        count              <= 6'b0;
        quotient_negative  <= 1'b0;
        remainder_negative <= 1'b0;
    end else begin
        complete <= 1'b0;
        if (start && !busy) begin
            if (divisor == 32'b0) begin
                quotient  <= 32'hffff_ffff;
                remainder <= dividend;
                complete  <= 1'b1;
            end else begin
                busy               <= 1'b1;
                divisor_abs        <= divisor_abs_in;
                quotient_work      <= dividend_abs;
                remainder_work     <= 33'b0;
                count              <= 6'd32;
                quotient_negative  <= dividend_negative ^ divisor_negative;
                remainder_negative <= dividend_negative;
            end
        end else if (busy) begin
            quotient_work  <= next_quotient;
            remainder_work <= next_remainder;
            count          <= count - 6'd1;
            if (count == 6'd1) begin
                busy      <= 1'b0;
                complete  <= 1'b1;
                quotient  <= quotient_negative ? -next_quotient : next_quotient;
                remainder <= remainder_negative ? -next_remainder[31:0]
                                                : next_remainder[31:0];
            end
        end
    end
end

endmodule


module decoder_4_16(
    input  wire [ 3:0] in,
    output wire [15:0] out
);

genvar i;
generate for (i=0; i<16; i=i+1) begin
    assign out[i] = (in == i);
end endgenerate

endmodule


module decoder_5_32(
    input  wire [ 4:0] in,
    output wire [31:0] out
);

genvar i;
generate for (i=0; i<32; i=i+1) begin
    assign out[i] = (in == i);
end endgenerate

endmodule


module decoder_6_64(
    input  wire [ 5:0] in,
    output wire [63:0] out
);

genvar i;
generate for (i=0; i<64; i=i+1) begin
    assign out[i] = (in == i);
end endgenerate

endmodule
