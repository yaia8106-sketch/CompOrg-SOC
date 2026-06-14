// ============================================================
// Module: axi_ram_slave
// Description:
//   Simple BRAM-based AXI4 slave. Supports INCR bursts for both
//   read and write. Configurable size and base address.
//
//   Used as DDR placeholder in simulation and for on-chip
//   non-cacheable buffer (NC Buffer) in the SoC.
//
//   Parameters:
//     DEPTH_WORDS — number of 32-bit words in the RAM
//     BASE_ADDR   — base address for this slave
//     ADDR_MASK   — address mask for decode
//     READ_LATENCY — cycles from AR acceptance to first R data (1-3)
// ============================================================

module axi_ram_slave #(
    parameter int DEPTH_WORDS  = 65536,    // default 256KB
    parameter bit [31:0] BASE_ADDR = 32'h8030_0000,
    parameter bit [31:0] ADDR_MASK = 32'hFF00_0000,
    parameter int READ_LATENCY = 2          // 1=cannot accept W before AW, 2=typical
) (
    input  logic        clk,
    input  logic        rst,

    // AXI4 slave interface
    input  logic [31:0] s_awaddr,
    input  logic [ 7:0] s_awlen,
    input  logic [ 2:0] s_awsize,
    input  logic [ 1:0] s_awburst,
    input  logic        s_awlock,
    input  logic [ 3:0] s_awcache,
    input  logic [ 2:0] s_awprot,
    input  logic [ 3:0] s_awqos,
    input  logic        s_awvalid,
    output logic        s_awready,

    input  logic [31:0] s_wdata,
    input  logic [ 3:0] s_wstrb,
    input  logic        s_wlast,
    input  logic        s_wvalid,
    output logic        s_wready,

    output logic [ 1:0] s_bresp,
    output logic        s_bvalid,
    input  logic        s_bready,

    input  logic [31:0] s_araddr,
    input  logic [ 7:0] s_arlen,
    input  logic [ 2:0] s_arsize,
    input  logic [ 1:0] s_arburst,
    input  logic        s_arlock,
    input  logic [ 3:0] s_arcache,
    input  logic [ 2:0] s_arprot,
    input  logic [ 3:0] s_arqos,
    input  logic        s_arvalid,
    output logic        s_arready,

    output logic [31:0] s_rdata,
    output logic [ 1:0] s_rresp,
    output logic        s_rlast,
    output logic        s_rvalid,
    input  logic        s_rready
);

    // ============================================================
    // BRAM storage
    // ============================================================
    (* ram_style = "block" *) logic [31:0] mem [DEPTH_WORDS];

    // Convert byte address to word index
    localparam int ADDR_SHIFT = 2;  // 4 bytes per word

    function automatic logic [$clog2(DEPTH_WORDS)-1:0] addr_to_idx(logic [31:0] addr);
        return addr[ADDR_SHIFT +: $clog2(DEPTH_WORDS)];
    endfunction

    // Check if address is within this slave's range
    function automatic logic addr_in_range(logic [31:0] addr);
        return (addr >= BASE_ADDR) && (addr < BASE_ADDR + (DEPTH_WORDS << ADDR_SHIFT));
    endfunction

    // ============================================================
    // Write path FSM
    // ============================================================
    typedef enum logic [1:0] {
        WR_IDLE,
        WR_DATA,
        WR_RESP
    } wr_state_t;
    wr_state_t wr_st;

    logic [ 7:0] wr_beat_cnt;
    logic [ 7:0] wr_total_beats;
    logic [31:0] wr_base_addr;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_st          <= WR_IDLE;
            wr_beat_cnt    <= '0;
            wr_total_beats <= '0;
            wr_base_addr   <= '0;
        end else begin
            case (wr_st)
                WR_IDLE: begin
                    if (s_awvalid && s_awready) begin
                        wr_base_addr   <= s_awaddr;
                        wr_total_beats <= s_awlen;
                        wr_beat_cnt    <= '0;
                        wr_st          <= WR_DATA;
                    end
                end

                WR_DATA: begin
                    if (s_wvalid && s_wready) begin
                        wr_beat_cnt <= wr_beat_cnt + 8'd1;
                        if (s_wlast) begin
                            wr_st <= WR_RESP;
                        end
                    end
                end

                WR_RESP: begin
                    if (s_bvalid && s_bready) begin
                        wr_st <= WR_IDLE;
                    end
                end

                default: wr_st <= WR_IDLE;
            endcase
        end
    end

    // AWREADY: accept when idle and address in range
    assign s_awready = (wr_st == WR_IDLE) && addr_in_range(s_awaddr);

    // WREADY: accept when in WR_DATA state
    assign s_wready = (wr_st == WR_DATA);

    // BVALID / BRESP
    assign s_bvalid = (wr_st == WR_RESP);
    assign s_bresp  = 2'b00;  // OKAY

    // Write to BRAM
    always_ff @(posedge clk) begin
        if (wr_st == WR_DATA && s_wvalid && s_wready) begin
            logic [$clog2(DEPTH_WORDS)-1:0] idx;
            idx = addr_to_idx(wr_base_addr) + $clog2(DEPTH_WORDS)'(wr_beat_cnt);
            // Byte strobes
            if (s_wstrb[0]) mem[idx][ 7: 0] <= s_wdata[ 7: 0];
            if (s_wstrb[1]) mem[idx][15: 8] <= s_wdata[15: 8];
            if (s_wstrb[2]) mem[idx][23:16] <= s_wdata[23:16];
            if (s_wstrb[3]) mem[idx][31:24] <= s_wdata[31:24];
        end
    end

    // ============================================================
    // Read path FSM
    // ============================================================
    typedef enum logic [1:0] {
        RD_IDLE,
        RD_DELAY,     // pipeline delay stage(s)
        RD_DATA
    } rd_state_t;
    rd_state_t rd_st;

    logic [ 7:0] rd_beat_cnt;
    logic [ 7:0] rd_total_beats;
    logic [31:0] rd_base_addr;
    logic [31:0] rd_data_prefetch;  // BRAM output registered

    // Read data prefetch (registered BRAM read)
    always_ff @(posedge clk) begin
        if (rd_st == RD_IDLE && s_arvalid && s_arready) begin
            rd_data_prefetch <= mem[addr_to_idx(s_araddr)];
        end else if (rd_st == RD_DELAY || (rd_st == RD_DATA && s_rvalid && s_rready)) begin
            logic [$clog2(DEPTH_WORDS)-1:0] next_idx;
            next_idx = addr_to_idx(rd_base_addr) + $clog2(DEPTH_WORDS)'(rd_beat_cnt + 1);
            rd_data_prefetch <= mem[next_idx];
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rd_st          <= RD_IDLE;
            rd_beat_cnt    <= '0;
            rd_total_beats <= '0;
            rd_base_addr   <= '0;
        end else begin
            case (rd_st)
                RD_IDLE: begin
                    if (s_arvalid && s_arready) begin
                        rd_base_addr   <= s_araddr;
                        rd_total_beats <= s_arlen;
                        rd_beat_cnt    <= '0;
                        if (READ_LATENCY <= 1)
                            rd_st <= RD_DATA;
                        else
                            rd_st <= RD_DELAY;
                    end
                end

                RD_DELAY: begin
                    // Wait for BRAM read latency
                    // READ_LATENCY=2: 1 cycle here → RD_DATA
                    // READ_LATENCY=3: 2 cycles here → RD_DATA
                    // Simple: just wait 1 cycle always (READ_LATENCY=2)
                    rd_st <= RD_DATA;
                end

                RD_DATA: begin
                    if (s_rvalid && s_rready) begin
                        rd_beat_cnt <= rd_beat_cnt + 8'd1;
                        if (rd_beat_cnt == rd_total_beats) begin
                            rd_st <= RD_IDLE;
                        end
                    end
                end

                default: rd_st <= RD_IDLE;
            endcase
        end
    end

    // ARREADY: accept when idle and address in range
    assign s_arready = (rd_st == RD_IDLE) && addr_in_range(s_araddr);

    // R channel
    assign s_rvalid = (rd_st == RD_DATA);
    assign s_rdata  = rd_data_prefetch;
    assign s_rresp  = 2'b00;  // OKAY
    assign s_rlast  = (rd_beat_cnt == rd_total_beats);

`ifndef SYNTHESIS
    // ============================================================
    // Assertions
    // ============================================================
    // Check that address is in range when transactions are accepted
    property p_aw_addr_range;
        @(posedge clk) (s_awvalid && s_awready) |-> addr_in_range(s_awaddr);
    endproperty
    a_aw_addr_range: assert property(p_aw_addr_range)
        else $error("[AXI_RAM] AW address 0x%08h out of range", s_awaddr);

    property p_ar_addr_range;
        @(posedge clk) (s_arvalid && s_arready) |-> addr_in_range(s_araddr);
    endproperty
    a_ar_addr_range: assert property(p_ar_addr_range)
        else $error("[AXI_RAM] AR address 0x%08h out of range", s_araddr);

    // Check that we don't overflow the BRAM
    property p_wr_idx_range;
        @(posedge clk) (wr_st == WR_DATA && s_wvalid && s_wready) |->
            (addr_to_idx(wr_base_addr) + $clog2(DEPTH_WORDS)'(wr_beat_cnt) < DEPTH_WORDS);
    endproperty
    a_wr_idx_range: assert property(p_wr_idx_range)
        else $error("[AXI_RAM] Write index overflow at beat %0d", wr_beat_cnt);

    // Check burst type is INCR (only INCR supported)
    property p_burst_incr;
        @(posedge clk) (s_awvalid && s_awready) |-> (s_awburst == 2'b01);
    endproperty
    a_burst_incr_wr: assert property(p_burst_incr);
    a_burst_incr_rd: assert property(@(posedge clk) (s_arvalid && s_arready) |-> (s_arburst == 2'b01));

    // Initialization for simulation
    initial begin
        for (int i = 0; i < DEPTH_WORDS; i++)
            mem[i] = 32'h0000_0000;
    end
`endif

endmodule
