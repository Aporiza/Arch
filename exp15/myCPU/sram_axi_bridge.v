// 实验 15：两个类 SRAM 从端口合并为一个 AXI 主端口。
// 保守实现：全桥最多一笔未完成事务，数据端优先。读写不并发，
// 因此写响应 B 返回前不会发出任何读请求，也不做写到读前递。
// addr_ok 表示请求已进入桥内寄存器，不是外部 AXI 地址已经握手。
// CPU 在此后可以撤销/改变 req，桥仍负责完成原事务。
module sram_axi_bridge (
    input wire aclk,
    input wire aresetn,
    input wire inst_sram_req,
    input wire inst_sram_wr,
    input wire [1:0] inst_sram_size,
    input wire [3:0] inst_sram_wstrb,
    input wire [31:0] inst_sram_addr,
    input wire [31:0] inst_sram_wdata,
    output wire inst_sram_addr_ok,
    output wire inst_sram_data_ok,
    output wire [31:0] inst_sram_rdata,
    input wire data_sram_req,
    input wire data_sram_wr,
    input wire [1:0] data_sram_size,
    input wire [3:0] data_sram_wstrb,
    input wire [31:0] data_sram_addr,
    input wire [31:0] data_sram_wdata,
    output wire data_sram_addr_ok,
    output wire data_sram_data_ok,
    output wire [31:0] data_sram_rdata,

    output wire [3:0] arid,
    output wire [31:0] araddr,
    output wire [7:0] arlen,
    output wire [2:0] arsize,
    output wire [1:0] arburst,
    output wire [1:0] arlock,
    output wire [3:0] arcache,
    output wire [2:0] arprot,
    output wire arvalid,
    input wire arready,
    input wire [3:0] rid,
    input wire [31:0] rdata,
    input wire [1:0] rresp,
    input wire rlast,
    input wire rvalid,
    output wire rready,
    output wire [3:0] awid,
    output wire [31:0] awaddr,
    output wire [7:0] awlen,
    output wire [2:0] awsize,
    output wire [1:0] awburst,
    output wire [1:0] awlock,
    output wire [3:0] awcache,
    output wire [2:0] awprot,
    output wire awvalid,
    input wire awready,
    output wire [3:0] wid,
    output wire [31:0] wdata,
    output wire [3:0] wstrb,
    output wire wlast,
    output wire wvalid,
    input wire wready,
    input wire [3:0] bid,
    input wire [1:0] bresp,
    input wire bvalid,
    output wire bready
);
localparam IDLE = 3'd0, READ_ADDR = 3'd1, READ_DATA = 3'd2,
           WRITE_SEND = 3'd3, WRITE_RESP = 3'd4, RESPOND = 3'd5;
reg [2:0] state;
reg owner_data;
reg [31:0] addr_buf;
reg [1:0] size_buf;
reg [31:0] wdata_buf;
reg [3:0] wstrb_buf;
reg [31:0] rdata_buf;
reg aw_pending, w_pending;

// 请求在本地握手的上升沿被锁存。未选中的端口可以取消请求。
// 本 CPU 的取指端只读；inst_sram_wr=1 的请求不接受。
assign data_sram_addr_ok = aresetn && state == IDLE;
assign inst_sram_addr_ok = aresetn && state == IDLE &&
                           !data_sram_req && !inst_sram_wr;
wire take_data = data_sram_req && data_sram_addr_ok;
wire take_inst = inst_sram_req && inst_sram_addr_ok;
assign inst_sram_data_ok = aresetn && state == RESPOND && !owner_data;
assign data_sram_data_ok = aresetn && state == RESPOND && owner_data;
assign inst_sram_rdata = rdata_buf;
assign data_sram_rdata = rdata_buf;

// 单拍 INCR 事务。AXI3 风格端口与官方 soc_axi 一致。
assign arid = owner_data ? 4'd1 : 4'd0;
assign araddr = addr_buf;
assign arsize = {1'b0, size_buf};
assign arlen = 8'd0;
assign arburst = 2'b01;
assign arlock = 2'b00;
assign arcache = 4'b0;
assign arprot = 3'b0;
assign arvalid = aresetn && state == READ_ADDR;
assign rready = aresetn && state == READ_DATA;
assign awid = 4'd1;
assign awaddr = addr_buf;
assign awsize = {1'b0, size_buf};
assign awlen = 8'd0;
assign awburst = 2'b01;
assign awlock = 2'b00;
assign awcache = 4'b0;
assign awprot = 3'b0;
assign awvalid = aresetn && state == WRITE_SEND && aw_pending;
assign wid = 4'd1;
assign wdata = wdata_buf;
assign wstrb = wstrb_buf;
assign wlast = 1'b1;
assign wvalid = aresetn && state == WRITE_SEND && w_pending;
assign bready = aresetn && state == WRITE_RESP;

// valid 不依赖 ready 的组合输入，ready 不依赖 valid 的组合输入。
// AW/W 同时发起，各自握手后各自撤销；支持 AW 先到、W 先到及同拍。
// R 数据先缓存，下一拍才给 CPU 一个 data_ok，避免组合返回路径。
// 按教材表 8.4，当前实验不处理 rresp/bresp 总线错误。
always @(posedge aclk) begin
    if (!aresetn) begin
        state <= IDLE;
        owner_data <= 1'b0;
        addr_buf <= 32'b0;
        size_buf <= 2'b0;
        wdata_buf <= 32'b0;
        wstrb_buf <= 4'b0;
        rdata_buf <= 32'b0;
        aw_pending <= 1'b0;
        w_pending <= 1'b0;
    end else begin
        case (state)
            IDLE: if (take_data || take_inst) begin
                owner_data <= take_data;
                addr_buf <= take_data ? data_sram_addr : inst_sram_addr;
                size_buf <= take_data ? data_sram_size : inst_sram_size;
                if (take_data && data_sram_wr) begin
                    wdata_buf <= data_sram_wdata;
                    wstrb_buf <= data_sram_wstrb;
                    aw_pending <= 1'b1;
                    w_pending <= 1'b1;
                    state <= WRITE_SEND;
                end else
                    state <= READ_ADDR;
            end
            READ_ADDR: if (arvalid && arready)
                state <= READ_DATA;
            READ_DATA: if (rvalid && rready && rlast && rid == arid) begin
                rdata_buf <= rdata;
                state <= RESPOND;
            end
            WRITE_SEND: begin
                if (awvalid && awready) aw_pending <= 1'b0;
                if (wvalid && wready) w_pending <= 1'b0;
                if ((!aw_pending || awready) && (!w_pending || wready))
                    state <= WRITE_RESP;
            end
            WRITE_RESP: if (bvalid && bready && bid == 4'd1) begin
                rdata_buf <= 32'b0;
                state <= RESPOND;
            end
            RESPOND: state <= IDLE;
            default: state <= IDLE;
        endcase
    end
end
endmodule
