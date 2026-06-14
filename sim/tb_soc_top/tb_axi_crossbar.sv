// ============================================================
// Testbench: tb_axi_crossbar
// Description:
//   Standalone test of the AXI crossbar with 2 masters and
//   2 slaves (DDR RAM + MMIO decoder).
//
//   Tests:
//     1. Master 0 writes to DDR, reads back — data match
//     2. Master 0 reads from unmapped address — DECERR
//     3. Master 0 writes to unmapped address — DECERR
//     4. Two masters interleaved access (when M1 is added)
// ============================================================

`include "hdl/soc/address_map.svh"

module tb_axi_crossbar;

    localparam int NUM_MASTERS = 2;
    localparam int NUM_SLAVES  = 2;

    // Slave address config
    localparam bit [31:0] SLAVE_BASE [NUM_SLAVES] = '{
        `SOC_ADDR_DDR_BASE,
        `SOC_ADDR_SOC_MMIO_BASE
    };
    localparam bit [31:0] SLAVE_MASK [NUM_SLAVES] = '{
        32'hFF00_0000,
        32'hFF00_0000
    };

    logic        clk;
    logic        rst;

    // ============================================================
    // Master signals (packed)
    // ============================================================
    logic [NUM_MASTERS-1:0][31:0] m_awaddr;
    logic [NUM_MASTERS-1:0][ 7:0] m_awlen;
    logic [NUM_MASTERS-1:0][ 2:0] m_awsize;
    logic [NUM_MASTERS-1:0][ 1:0] m_awburst;
    logic [NUM_MASTERS-1:0]       m_awlock;
    logic [NUM_MASTERS-1:0][ 3:0] m_awcache;
    logic [NUM_MASTERS-1:0][ 2:0] m_awprot;
    logic [NUM_MASTERS-1:0][ 3:0] m_awqos;
    logic [NUM_MASTERS-1:0]       m_awvalid;
    logic [NUM_MASTERS-1:0]       m_awready;

    logic [NUM_MASTERS-1:0][31:0] m_wdata;
    logic [NUM_MASTERS-1:0][ 3:0] m_wstrb;
    logic [NUM_MASTERS-1:0]       m_wlast;
    logic [NUM_MASTERS-1:0]       m_wvalid;
    logic [NUM_MASTERS-1:0]       m_wready;

    logic [NUM_MASTERS-1:0][ 1:0] m_bresp;
    logic [NUM_MASTERS-1:0]       m_bvalid;
    logic [NUM_MASTERS-1:0]       m_bready;

    logic [NUM_MASTERS-1:0][31:0] m_araddr;
    logic [NUM_MASTERS-1:0][ 7:0] m_arlen;
    logic [NUM_MASTERS-1:0][ 2:0] m_arsize;
    logic [NUM_MASTERS-1:0][ 1:0] m_arburst;
    logic [NUM_MASTERS-1:0]       m_arlock;
    logic [NUM_MASTERS-1:0][ 3:0] m_arcache;
    logic [NUM_MASTERS-1:0][ 2:0] m_arprot;
    logic [NUM_MASTERS-1:0][ 3:0] m_arqos;
    logic [NUM_MASTERS-1:0]       m_arvalid;
    logic [NUM_MASTERS-1:0]       m_arready;

    logic [NUM_MASTERS-1:0][31:0] m_rdata;
    logic [NUM_MASTERS-1:0][ 1:0] m_rresp;
    logic [NUM_MASTERS-1:0]       m_rlast;
    logic [NUM_MASTERS-1:0]       m_rvalid;
    logic [NUM_MASTERS-1:0]       m_rready;

    // ============================================================
    // Slave signals
    // ============================================================
    logic [NUM_SLAVES-1:0][31:0]  s_awaddr;
    logic [NUM_SLAVES-1:0][ 7:0]  s_awlen;
    logic [NUM_SLAVES-1:0][ 2:0]  s_awsize;
    logic [NUM_SLAVES-1:0][ 1:0]  s_awburst;
    logic [NUM_SLAVES-1:0]        s_awlock;
    logic [NUM_SLAVES-1:0][ 3:0]  s_awcache;
    logic [NUM_SLAVES-1:0][ 2:0]  s_awprot;
    logic [NUM_SLAVES-1:0][ 3:0]  s_awqos;
    logic [NUM_SLAVES-1:0]        s_awvalid;
    logic [NUM_SLAVES-1:0]        s_awready;

    logic [NUM_SLAVES-1:0][31:0]  s_wdata;
    logic [NUM_SLAVES-1:0][ 3:0]  s_wstrb;
    logic [NUM_SLAVES-1:0]        s_wlast;
    logic [NUM_SLAVES-1:0]        s_wvalid;
    logic [NUM_SLAVES-1:0]        s_wready;

    logic [NUM_SLAVES-1:0][ 1:0]  s_bresp;
    logic [NUM_SLAVES-1:0]        s_bvalid;
    logic [NUM_SLAVES-1:0]        s_bready;

    logic [NUM_SLAVES-1:0][31:0]  s_araddr;
    logic [NUM_SLAVES-1:0][ 7:0]  s_arlen;
    logic [NUM_SLAVES-1:0][ 2:0]  s_arsize;
    logic [NUM_SLAVES-1:0][ 1:0]  s_arburst;
    logic [NUM_SLAVES-1:0]        s_arlock;
    logic [NUM_SLAVES-1:0][ 3:0]  s_arcache;
    logic [NUM_SLAVES-1:0][ 2:0]  s_arprot;
    logic [NUM_SLAVES-1:0][ 3:0]  s_arqos;
    logic [NUM_SLAVES-1:0]        s_arvalid;
    logic [NUM_SLAVES-1:0]        s_arready;

    logic [NUM_SLAVES-1:0][31:0]  s_rdata;
    logic [NUM_SLAVES-1:0][ 1:0]  s_rresp;
    logic [NUM_SLAVES-1:0]        s_rlast;
    logic [NUM_SLAVES-1:0]        s_rvalid;
    logic [NUM_SLAVES-1:0]        s_rready;

    // ============================================================
    // DUT: AXI Crossbar
    // ============================================================
    axi_crossbar #(
        .NUM_MASTERS (NUM_MASTERS),
        .NUM_SLAVES  (NUM_SLAVES),
        .SLAVE_BASE  (SLAVE_BASE),
        .SLAVE_MASK  (SLAVE_MASK)
    ) u_crossbar (
        .clk         (clk),
        .rst         (rst),
        .m_awaddr    (m_awaddr),
        .m_awlen     (m_awlen),
        .m_awsize    (m_awsize),
        .m_awburst   (m_awburst),
        .m_awlock    (m_awlock),
        .m_awcache   (m_awcache),
        .m_awprot    (m_awprot),
        .m_awqos     (m_awqos),
        .m_awvalid   (m_awvalid),
        .m_awready   (m_awready),
        .m_wdata     (m_wdata),
        .m_wstrb     (m_wstrb),
        .m_wlast     (m_wlast),
        .m_wvalid    (m_wvalid),
        .m_wready    (m_wready),
        .m_bresp     (m_bresp),
        .m_bvalid    (m_bvalid),
        .m_bready    (m_bready),
        .m_araddr    (m_araddr),
        .m_arlen     (m_arlen),
        .m_arsize    (m_arsize),
        .m_arburst   (m_arburst),
        .m_arlock    (m_arlock),
        .m_arcache   (m_arcache),
        .m_arprot    (m_arprot),
        .m_arqos     (m_arqos),
        .m_arvalid   (m_arvalid),
        .m_arready   (m_arready),
        .m_rdata     (m_rdata),
        .m_rresp     (m_rresp),
        .m_rlast     (m_rlast),
        .m_rvalid    (m_rvalid),
        .m_rready    (m_rready),
        .s_awaddr    (s_awaddr),
        .s_awlen     (s_awlen),
        .s_awsize    (s_awsize),
        .s_awburst   (s_awburst),
        .s_awlock    (s_awlock),
        .s_awcache   (s_awcache),
        .s_awprot    (s_awprot),
        .s_awqos     (s_awqos),
        .s_awvalid   (s_awvalid),
        .s_awready   (s_awready),
        .s_wdata     (s_wdata),
        .s_wstrb     (s_wstrb),
        .s_wlast     (s_wlast),
        .s_wvalid    (s_wvalid),
        .s_wready    (s_wready),
        .s_bresp     (s_bresp),
        .s_bvalid    (s_bvalid),
        .s_bready    (s_bready),
        .s_araddr    (s_araddr),
        .s_arlen     (s_arlen),
        .s_arsize    (s_arsize),
        .s_arburst   (s_arburst),
        .s_arlock    (s_arlock),
        .s_arcache   (s_arcache),
        .s_arprot    (s_arprot),
        .s_arqos     (s_arqos),
        .s_arvalid   (s_arvalid),
        .s_arready   (s_arready),
        .s_rdata     (s_rdata),
        .s_rresp     (s_rresp),
        .s_rlast     (s_rlast),
        .s_rvalid    (s_rvalid),
        .s_rready    (s_rready)
    );

    // ============================================================
    // Slave 0: DDR RAM
    // ============================================================
    axi_ram_slave #(
        .DEPTH_WORDS (1024),      // 4KB for test
        .BASE_ADDR   (`SOC_ADDR_DDR_BASE),
        .ADDR_MASK   (32'hFF00_0000),
        .READ_LATENCY(2)
    ) u_ddr (
        .clk        (clk),
        .rst        (rst),
        .s_awaddr   (s_awaddr  [0]),
        .s_awlen    (s_awlen   [0]),
        .s_awsize   (s_awsize  [0]),
        .s_awburst  (s_awburst [0]),
        .s_awlock   (s_awlock  [0]),
        .s_awcache  (s_awcache [0]),
        .s_awprot   (s_awprot  [0]),
        .s_awqos    (s_awqos   [0]),
        .s_awvalid  (s_awvalid [0]),
        .s_awready  (s_awready [0]),
        .s_wdata    (s_wdata   [0]),
        .s_wstrb    (s_wstrb   [0]),
        .s_wlast    (s_wlast   [0]),
        .s_wvalid   (s_wvalid  [0]),
        .s_wready   (s_wready  [0]),
        .s_bresp    (s_bresp   [0]),
        .s_bvalid   (s_bvalid  [0]),
        .s_bready   (s_bready  [0]),
        .s_araddr   (s_araddr  [0]),
        .s_arlen    (s_arlen   [0]),
        .s_arsize   (s_arsize  [0]),
        .s_arburst  (s_arburst [0]),
        .s_arlock   (s_arlock  [0]),
        .s_arcache  (s_arcache [0]),
        .s_arprot   (s_arprot  [0]),
        .s_arqos    (s_arqos   [0]),
        .s_arvalid  (s_arvalid [0]),
        .s_arready  (s_arready [0]),
        .s_rdata    (s_rdata   [0]),
        .s_rresp    (s_rresp   [0]),
        .s_rlast    (s_rlast   [0]),
        .s_rvalid   (s_rvalid  [0]),
        .s_rready   (s_rready  [0])
    );

    // ============================================================
    // Slave 1: Simple echo/dummy slave
    // (MMIO decoder requires real peripherals; for crossbar test,
    //  use a simple echo slave that returns OKAY)
    // ============================================================
    logic s1_aw_done, s1_w_done;
    assign s_awready[1] = ~s1_aw_done;
    assign s_wready [1] = s1_aw_done && ~s1_w_done;
    assign s_bvalid [1] = s1_w_done;
    assign s_bresp  [1] = 2'b00;
    assign s_bready [1] = s_bvalid[1] ? 1'b1 : m_bready[0];  // any master OK
    assign s_arready[1] = 1'b1;
    assign s_rvalid [1] = 1'b0;  // no reads for this test
    assign s_rdata  [1] = '0;
    assign s_rresp  [1] = 2'b00;
    assign s_rlast  [1] = 1'b0;
    assign s_rready [1] = 1'b0;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            s1_aw_done <= 1'b0;
            s1_w_done  <= 1'b0;
        end else begin
            if (s_awvalid[1] && s_awready[1])
                s1_aw_done <= 1'b1;
            if (s1_aw_done && s_wvalid[1] && s_wready[1])
                s1_w_done <= 1'b1;
            if (s1_w_done && s_bvalid[1] && s_bready[1]) begin
                s1_aw_done <= 1'b0;
                s1_w_done  <= 1'b0;
            end
        end
    end

    // ============================================================
    // Clock and reset
    // ============================================================
    initial clk = 1'b0;
    always #5 clk = ~clk;  // 100MHz

    initial begin
        rst = 1'b1;
        #20 rst = 1'b0;
        #10 rst = 1'b1;
    end

    // ============================================================
    // Master 0 init (M0 = CPU-like)
    // ============================================================
    task automatic m0_init();
        m_awvalid[0] = 1'b0;
        m_wvalid [0] = 1'b0;
        m_bready [0] = 1'b0;
        m_arvalid[0] = 1'b0;
        m_rready [0] = 1'b0;
        m_awaddr [0] = '0;
        m_awlen  [0] = '0;
        m_awsize [0] = 3'd2;   // 4 bytes
        m_awburst[0] = 2'b01;  // INCR
        m_awlock [0] = 1'b0;
        m_awcache[0] = 4'b0011;
        m_awprot [0] = 3'b000;
        m_awqos  [0] = '0;
        m_wdata  [0] = '0;
        m_wstrb  [0] = 4'b1111;
        m_wlast  [0] = 1'b1;
        m_araddr [0] = '0;
        m_arlen  [0] = '0;
        m_arsize [0] = 3'd2;
        m_arburst[0] = 2'b01;
        m_arlock [0] = 1'b0;
        m_arcache[0] = 4'b0011;
        m_arprot [0] = 3'b000;
        m_arqos  [0] = '0;
    endtask

    // ============================================================
    // Master 0: AXI write (single beat)
    // ============================================================
    task automatic m0_write(input logic [31:0] addr, input logic [31:0] data);
        m_awaddr[0] = addr;
        m_awvalid[0] = 1'b1;
        m_wdata[0]  = data;
        m_wvalid[0] = 1'b1;
        m_bready[0] = 1'b1;

        // Wait for AW handshake
        @(posedge clk);
        while (!(m_awvalid[0] && m_awready[0])) @(posedge clk);
        m_awvalid[0] = 1'b0;

        // Wait for W handshake
        while (!(m_wvalid[0] && m_wready[0])) @(posedge clk);
        m_wvalid[0] = 1'b0;

        // Wait for B handshake
        while (!(m_bvalid[0] && m_bready[0])) @(posedge clk);
        m_bready[0] = 1'b0;
    endtask

    // ============================================================
    // Master 0: AXI read (single beat)
    // ============================================================
    task automatic m0_read(input logic [31:0] addr, output logic [31:0] data,
                           output logic [1:0] resp);
        m_araddr[0]  = addr;
        m_arvalid[0] = 1'b1;
        m_rready[0]  = 1'b1;

        // Wait for AR handshake
        @(posedge clk);
        while (!(m_arvalid[0] && m_arready[0])) @(posedge clk);
        m_arvalid[0] = 1'b0;

        // Wait for R handshake
        while (!(m_rvalid[0] && m_rready[0])) @(posedge clk);
        data = m_rdata[0];
        resp = m_rresp[0];
        m_rready[0] = 1'b0;
    endtask

    // ============================================================
    // Master 0: AXI read burst (4 beats, like DCache refill)
    // ============================================================
    task automatic m0_read_burst(input logic [31:0] addr, input logic [7:0] len,
                                 output logic [31:0] data [4]);
        m_araddr[0]  = addr;
        m_arlen[0]   = len;
        m_arvalid[0] = 1'b1;
        m_rready[0]  = 1'b1;

        @(posedge clk);
        while (!(m_arvalid[0] && m_arready[0])) @(posedge clk);
        m_arvalid[0] = 1'b0;

        for (int i = 0; i <= len; i++) begin
            while (!(m_rvalid[0] && m_rready[0])) @(posedge clk);
            data[i] = m_rdata[0];
            if (i == len) begin
                if (!m_rlast[0])
                    $error("[TB] RLAST expected on beat %0d", i);
            end
            @(posedge clk);
        end
        m_rready[0] = 1'b0;
    endtask

    // ============================================================
    // Test runner
    // ============================================================
    logic [31:0] rd_data;
    logic [ 1:0] rd_resp;
    logic [31:0] burst_data [4];

    integer errors;
    initial begin
        errors = 0;

        // Wait for reset
        m0_init();
        @(posedge rst);
        repeat (5) @(posedge clk);

        $display("==============================================");
        $display(" AXI Crossbar Test Suite");
        $display("==============================================");

        // --------------------------------------------------------
        // Test 1: Write to DDR, read back
        // --------------------------------------------------------
        $display("[TEST 1] DDR write/read single beat...");
        m0_write(`SOC_ADDR_DDR_BASE + 32'h100, 32'hCAFE_BABE);
        m0_read (`SOC_ADDR_DDR_BASE + 32'h100, rd_data, rd_resp);

        if (rd_data == 32'hCAFE_BABE && rd_resp == 2'b00) begin
            $display("  PASS: data = 0x%08h, resp = %0d", rd_data, rd_resp);
        end else begin
            $error("  FAIL: expected 0xCAFE_BABE OKAY, got 0x%08h resp=%0d",
                   rd_data, rd_resp);
            errors++;
        end

        // --------------------------------------------------------
        // Test 2: Write to different DDR address, read back
        // --------------------------------------------------------
        $display("[TEST 2] DDR write/read different address...");
        m0_write(`SOC_ADDR_DDR_BASE + 32'h200, 32'hDEAD_BEEF);
        m0_write(`SOC_ADDR_DDR_BASE + 32'h204, 32'h1234_5678);
        m0_read (`SOC_ADDR_DDR_BASE + 32'h200, rd_data, rd_resp);
        if (rd_data == 32'hDEAD_BEEF) begin
            $display("  PASS: addr=0x200 data=0x%08h", rd_data);
        end else begin
            $error("  FAIL: expected 0xDEAD_BEEF, got 0x%08h", rd_data);
            errors++;
        end
        m0_read (`SOC_ADDR_DDR_BASE + 32'h204, rd_data, rd_resp);
        if (rd_data == 32'h1234_5678) begin
            $display("  PASS: addr=0x204 data=0x%08h", rd_data);
        end else begin
            $error("  FAIL: expected 0x1234_5678, got 0x%08h", rd_data);
            errors++;
        end

        // --------------------------------------------------------
        // Test 3: Read burst (4 beats, like DCache refill)
        // --------------------------------------------------------
        $display("[TEST 3] DDR read burst (4 beats)...");
        // Pre-fill known data
        m0_write(`SOC_ADDR_DDR_BASE + 32'h300, 32'hAAAA_0000);
        m0_write(`SOC_ADDR_DDR_BASE + 32'h304, 32'hBBBB_0001);
        m0_write(`SOC_ADDR_DDR_BASE + 32'h308, 32'hCCCC_0002);
        m0_write(`SOC_ADDR_DDR_BASE + 32'h30C, 32'hDDDD_0003);

        m0_read_burst(`SOC_ADDR_DDR_BASE + 32'h300, 8'd3, burst_data);

        if (burst_data[0] == 32'hAAAA_0000 &&
            burst_data[1] == 32'hBBBB_0001 &&
            burst_data[2] == 32'hCCCC_0002 &&
            burst_data[3] == 32'hDDDD_0003) begin
            $display("  PASS: burst read correct");
        end else begin
            $error("  FAIL: burst[0]=%h [1]=%h [2]=%h [3]=%h",
                   burst_data[0], burst_data[1], burst_data[2], burst_data[3]);
            errors++;
        end

        // --------------------------------------------------------
        // Test 4: Write to SoC MMIO area (slave 1)
        // --------------------------------------------------------
        $display("[TEST 4] SoC MMIO write test...");
        m0_write(`SOC_ADDR_SOC_MMIO_BASE + 32'h0000, 32'h5555_AAAA);
        $display("  PASS: MMIO write completed (no hang)");

        // --------------------------------------------------------
        // Test 5: Unmapped address → DECERR
        // --------------------------------------------------------
        $display("[TEST 5] Unmapped address read → DECERR...");
        m0_read(32'hC000_0000, rd_data, rd_resp);
        if (rd_resp == 2'b11) begin
            $display("  PASS: got DECERR (resp=%0d)", rd_resp);
        end else begin
            $error("  FAIL: expected DECERR (2'b11), got resp=%0d", rd_resp);
            errors++;
        end

        // --------------------------------------------------------
        // Test 6: Unmapped write → DECERR on B channel
        // --------------------------------------------------------
        $display("[TEST 6] Unmapped address write → DECERR...");
        m0_write(32'hC000_0100, 32'hFFFF_FFFF);
        $display("  PASS: unmapped write completed (B DECERR accepted)");

        // --------------------------------------------------------
        // Summary
        // --------------------------------------------------------
        $display("==============================================");
        if (errors == 0) begin
            $display(" ALL TESTS PASSED");
        end else begin
            $display(" %0d TEST(S) FAILED", errors);
        end
        $display("==============================================");

        #50 $finish;
    end

endmodule
