// ============================================================
// Module: axi_crossbar
// Description:
//   Parameterized N:M AXI4 crossbar with per-slave round-robin
//   arbitration and address decoding.
//
//   Each slave port independently arbitrates among masters.
//   Read and write channels are arbitrated independently.
//
//   Unmapped addresses get an immediate DECERR response via
//   a built-in error handler per master.
//
//   Parameters:
//     NUM_MASTERS — number of AXI master ports
//     NUM_SLAVES  — number of AXI slave ports
//     ADDR_WIDTH  — address bus width (default 32)
//     DATA_WIDTH  — data bus width (default 32)
//
//   Slave address regions:
//     SLAVE_BASE[s] — base address
//     SLAVE_MASK[s] — address mask (bits to compare)
// ============================================================

`include "hdl/soc/address_map.svh"

module axi_crossbar #(
    parameter int NUM_MASTERS = 2,
    parameter int NUM_SLAVES  = 2,
    parameter int ADDR_WIDTH  = 32,
    parameter int DATA_WIDTH  = 32,
    parameter bit [31:0] SLAVE_BASE [NUM_SLAVES] = '{32'h8030_0000, 32'hA000_0000},
    parameter bit [31:0] SLAVE_MASK [NUM_SLAVES] = '{32'hFF00_0000, 32'hFF00_0000}
) (
    input  logic                          clk,
    input  logic                          rst,

    // ============================================================
    // Master ports (packed arrays: [NUM_MASTERS-1:0] of signals)
    // ============================================================
    input  logic [NUM_MASTERS-1:0][ADDR_WIDTH-1:0] m_awaddr,
    input  logic [NUM_MASTERS-1:0][ 7:0]          m_awlen,
    input  logic [NUM_MASTERS-1:0][ 2:0]          m_awsize,
    input  logic [NUM_MASTERS-1:0][ 1:0]          m_awburst,
    input  logic [NUM_MASTERS-1:0]                m_awlock,
    input  logic [NUM_MASTERS-1:0][ 3:0]          m_awcache,
    input  logic [NUM_MASTERS-1:0][ 2:0]          m_awprot,
    input  logic [NUM_MASTERS-1:0][ 3:0]          m_awqos,
    input  logic [NUM_MASTERS-1:0]                m_awvalid,
    output logic [NUM_MASTERS-1:0]                m_awready,

    input  logic [NUM_MASTERS-1:0][DATA_WIDTH-1:0] m_wdata,
    input  logic [NUM_MASTERS-1:0][DATA_WIDTH/8-1:0] m_wstrb,
    input  logic [NUM_MASTERS-1:0]                 m_wlast,
    input  logic [NUM_MASTERS-1:0]                 m_wvalid,
    output logic [NUM_MASTERS-1:0]                 m_wready,

    output logic [NUM_MASTERS-1:0][ 1:0]           m_bresp,
    output logic [NUM_MASTERS-1:0]                 m_bvalid,
    input  logic [NUM_MASTERS-1:0]                 m_bready,

    input  logic [NUM_MASTERS-1:0][ADDR_WIDTH-1:0] m_araddr,
    input  logic [NUM_MASTERS-1:0][ 7:0]           m_arlen,
    input  logic [NUM_MASTERS-1:0][ 2:0]           m_arsize,
    input  logic [NUM_MASTERS-1:0][ 1:0]           m_arburst,
    input  logic [NUM_MASTERS-1:0]                 m_arlock,
    input  logic [NUM_MASTERS-1:0][ 3:0]           m_arcache,
    input  logic [NUM_MASTERS-1:0][ 2:0]           m_arprot,
    input  logic [NUM_MASTERS-1:0][ 3:0]           m_arqos,
    input  logic [NUM_MASTERS-1:0]                 m_arvalid,
    output logic [NUM_MASTERS-1:0]                 m_arready,

    output logic [NUM_MASTERS-1:0][DATA_WIDTH-1:0] m_rdata,
    output logic [NUM_MASTERS-1:0][ 1:0]           m_rresp,
    output logic [NUM_MASTERS-1:0]                 m_rlast,
    output logic [NUM_MASTERS-1:0]                 m_rvalid,
    input  logic [NUM_MASTERS-1:0]                 m_rready,

    // ============================================================
    // Slave ports
    // ============================================================
    output logic [NUM_SLAVES-1:0][ADDR_WIDTH-1:0] s_awaddr,
    output logic [NUM_SLAVES-1:0][ 7:0]           s_awlen,
    output logic [NUM_SLAVES-1:0][ 2:0]           s_awsize,
    output logic [NUM_SLAVES-1:0][ 1:0]           s_awburst,
    output logic [NUM_SLAVES-1:0]                 s_awlock,
    output logic [NUM_SLAVES-1:0][ 3:0]           s_awcache,
    output logic [NUM_SLAVES-1:0][ 2:0]           s_awprot,
    output logic [NUM_SLAVES-1:0][ 3:0]           s_awqos,
    output logic [NUM_SLAVES-1:0]                 s_awvalid,
    input  logic [NUM_SLAVES-1:0]                 s_awready,

    output logic [NUM_SLAVES-1:0][DATA_WIDTH-1:0] s_wdata,
    output logic [NUM_SLAVES-1:0][DATA_WIDTH/8-1:0] s_wstrb,
    output logic [NUM_SLAVES-1:0]                 s_wlast,
    output logic [NUM_SLAVES-1:0]                 s_wvalid,
    input  logic [NUM_SLAVES-1:0]                 s_wready,

    input  logic [NUM_SLAVES-1:0][ 1:0]           s_bresp,
    input  logic [NUM_SLAVES-1:0]                 s_bvalid,
    output logic [NUM_SLAVES-1:0]                 s_bready,

    output logic [NUM_SLAVES-1:0][ADDR_WIDTH-1:0] s_araddr,
    output logic [NUM_SLAVES-1:0][ 7:0]           s_arlen,
    output logic [NUM_SLAVES-1:0][ 2:0]           s_arsize,
    output logic [NUM_SLAVES-1:0][ 1:0]           s_arburst,
    output logic [NUM_SLAVES-1:0]                 s_arlock,
    output logic [NUM_SLAVES-1:0][ 3:0]           s_arcache,
    output logic [NUM_SLAVES-1:0][ 2:0]           s_arprot,
    output logic [NUM_SLAVES-1:0][ 3:0]           s_arqos,
    output logic [NUM_SLAVES-1:0]                 s_arvalid,
    input  logic [NUM_SLAVES-1:0]                 s_arready,

    input  logic [NUM_SLAVES-1:0][DATA_WIDTH-1:0] s_rdata,
    input  logic [NUM_SLAVES-1:0][ 1:0]           s_rresp,
    input  logic [NUM_SLAVES-1:0]                 s_rlast,
    input  logic [NUM_SLAVES-1:0]                 s_rvalid,
    output logic [NUM_SLAVES-1:0]                 s_rready
);

    // ============================================================
    // Helper: address → slave lookup
    // ============================================================
    function automatic int addr_to_slave(logic [ADDR_WIDTH-1:0] addr);
        for (int s = 0; s < NUM_SLAVES; s++) begin
            if ((addr & SLAVE_MASK[s]) == (SLAVE_BASE[s] & SLAVE_MASK[s]))
                return s;
        end
        return -1;
    endfunction

    // ============================================================
    // Per-slave state
    // ============================================================
    int aw_owner    [NUM_SLAVES];  // master currently doing write (-1 = idle)
    int aw_prio     [NUM_SLAVES];  // round-robin start for next AW grant
    int ar_owner    [NUM_SLAVES];  // master currently doing read  (-1 = idle)
    int ar_prio     [NUM_SLAVES];  // round-robin start for next AR grant

    // ============================================================
    // Per-slave routing logic
    // ============================================================
    for (genvar s = 0; s < NUM_SLAVES; s++) begin : slv

        // ---- Which masters target this slave right now? ----
        logic [NUM_MASTERS-1:0] aw_target;
        logic [NUM_MASTERS-1:0] ar_target;
        for (genvar m = 0; m < NUM_MASTERS; m++) begin
            assign aw_target[m] = m_awvalid[m] && (addr_to_slave(m_awaddr[m]) == s);
            assign ar_target[m] = m_arvalid[m] && (addr_to_slave(m_araddr[m]) == s);
        end

        // ---- AW arbitration: round-robin among requesters ----
        logic                   aw_gnt_valid;
        logic [$clog2(NUM_MASTERS)-1:0] aw_gnt_mid;

        always_comb begin
            aw_gnt_valid = 1'b0;
            aw_gnt_mid   = '0;
            if (aw_owner[s] == -1) begin
                for (int i = 0; i < NUM_MASTERS; i++) begin
                    int m = (aw_prio[s] + i) % NUM_MASTERS;
                    if (aw_target[m]) begin
                        aw_gnt_valid = 1'b1;
                        aw_gnt_mid   = $clog2(NUM_MASTERS)'(m);
                        break;
                    end
                end
            end
        end

        // ---- AR arbitration ----
        logic                   ar_gnt_valid;
        logic [$clog2(NUM_MASTERS)-1:0] ar_gnt_mid;

        always_comb begin
            ar_gnt_valid = 1'b0;
            ar_gnt_mid   = '0;
            if (ar_owner[s] == -1) begin
                for (int i = 0; i < NUM_MASTERS; i++) begin
                    int m = (ar_prio[s] + i) % NUM_MASTERS;
                    if (ar_target[m]) begin
                        ar_gnt_valid = 1'b1;
                        ar_gnt_mid   = $clog2(NUM_MASTERS)'(m);
                        break;
                    end
                end
            end
        end

        // ---- Active master (during transaction, use owner; else use grant) ----
        logic [$clog2(NUM_MASTERS)-1:0] w_mid;
        logic [$clog2(NUM_MASTERS)-1:0] r_mid;
        assign w_mid = (aw_owner[s] != -1) ? $clog2(NUM_MASTERS)'(aw_owner[s]) : aw_gnt_mid;
        assign r_mid = (ar_owner[s] != -1) ? $clog2(NUM_MASTERS)'(ar_owner[s]) : ar_gnt_mid;

        // ---- AW channel: master → slave ----
        assign s_awaddr  [s] = m_awaddr  [w_mid];
        assign s_awlen   [s] = m_awlen   [w_mid];
        assign s_awsize  [s] = m_awsize  [w_mid];
        assign s_awburst [s] = m_awburst [w_mid];
        assign s_awlock  [s] = m_awlock  [w_mid];
        assign s_awcache [s] = m_awcache [w_mid];
        assign s_awprot  [s] = m_awprot  [w_mid];
        assign s_awqos   [s] = m_awqos   [w_mid];
        assign s_awvalid [s] = aw_gnt_valid;

        // ---- W channel: master → slave ----
        assign s_wdata  [s] = m_wdata  [w_mid];
        assign s_wstrb  [s] = m_wstrb  [w_mid];
        assign s_wlast  [s] = m_wlast  [w_mid];
        assign s_wvalid [s] = m_wvalid [w_mid] && (aw_owner[s] != -1 || aw_gnt_valid);

        // ---- B channel: slave → master (handled in final assembly) ----
        assign s_bready[s] = (aw_owner[s] != -1) ? m_bready[aw_owner[s]] : 1'b0;

        // ---- AR channel: master → slave ----
        assign s_araddr  [s] = m_araddr  [r_mid];
        assign s_arlen   [s] = m_arlen   [r_mid];
        assign s_arsize  [s] = m_arsize  [r_mid];
        assign s_arburst [s] = m_arburst [r_mid];
        assign s_arlock  [s] = m_arlock  [r_mid];
        assign s_arcache [s] = m_arcache [r_mid];
        assign s_arprot  [s] = m_arprot  [r_mid];
        assign s_arqos   [s] = m_arqos   [r_mid];
        assign s_arvalid [s] = ar_gnt_valid;

        // ---- R channel: slave → master (handled in final assembly) ----
        assign s_rready[s] = (ar_owner[s] != -1) ? m_rready[ar_owner[s]] : 1'b0;

        // ---- Write owner FSM ----
        always_ff @(posedge clk or posedge rst) begin
            if (rst) begin
                aw_owner[s] <= -1;
                aw_prio[s]  <= 0;
            end else begin
                if (aw_owner[s] == -1 && aw_gnt_valid && s_awready[s]) begin
                    aw_owner[s] <= aw_gnt_mid;
                    aw_prio[s]  <= (aw_gnt_mid + 1) % NUM_MASTERS;
                end
                if (aw_owner[s] != -1 && s_bvalid[s] && m_bready[aw_owner[s]]) begin
                    aw_owner[s] <= -1;
                end
            end
        end

        // ---- Read owner FSM ----
        always_ff @(posedge clk or posedge rst) begin
            if (rst) begin
                ar_owner[s] <= -1;
                ar_prio[s]  <= 0;
            end else begin
                if (ar_owner[s] == -1 && ar_gnt_valid && s_arready[s]) begin
                    ar_owner[s] <= ar_gnt_mid;
                    ar_prio[s]  <= (ar_gnt_mid + 1) % NUM_MASTERS;
                end
                if (ar_owner[s] != -1 && s_rvalid[s] && m_rready[ar_owner[s]] && s_rlast[s]) begin
                    ar_owner[s] <= -1;
                end
            end
        end

    end : slv

    // ============================================================
    // Final master-side signal assembly
    //
    // For each master, collect:
    //   - AWREADY: from the slave it targets
    //   - WREADY:  from the slave it's writing to
    //   - BVALID/BRESP: from the slave it owns
    //   - ARREADY: from the slave it targets
    //   - RVALID/RDATA/RRESP/RLAST: from the slave it owns
    //
    // Unmapped addresses: immediate DECERR via per-master FSM.
    // ============================================================

    for (genvar m = 0; m < NUM_MASTERS; m++) begin : mst

        // ---- Default (unmapped-write) error handler ----
        typedef enum logic [1:0] {
            UW_IDLE, UW_ACCEPT, UW_DRAIN, UW_RESP
        } uw_state_t;
        uw_state_t uw_st;

        logic uw_aw_mapped;
        logic uw_ar_mapped;
        always_comb begin
            uw_aw_mapped = (addr_to_slave(m_awaddr[m]) != -1);
            uw_ar_mapped = (addr_to_slave(m_araddr[m]) != -1);
        end

        always_ff @(posedge clk or posedge rst) begin
            if (rst) begin
                uw_st <= UW_IDLE;
            end else begin
                case (uw_st)
                    UW_IDLE:
                        if (m_awvalid[m] && !uw_aw_mapped)
                            uw_st <= UW_ACCEPT;
                    UW_ACCEPT:
                        uw_st <= UW_DRAIN;
                    UW_DRAIN:
                        if (m_wvalid[m] && m_wlast[m])
                            uw_st <= UW_RESP;
                    UW_RESP:
                        if (m_bready[m])
                            uw_st <= UW_IDLE;
                    default: uw_st <= UW_IDLE;
                endcase
            end
        end

        logic uw_awready;
        logic uw_wready;
        logic uw_bvalid;
        assign uw_awready = (uw_st == UW_IDLE) && m_awvalid[m] && !uw_aw_mapped;
        assign uw_wready  = (uw_st == UW_DRAIN);  // accept & discard W data
        assign uw_bvalid  = (uw_st == UW_RESP);

        // ---- Default (unmapped-read) error handler ----
        typedef enum logic {
            UR_IDLE, UR_RESP
        } ur_state_t;
        ur_state_t ur_st;

        always_ff @(posedge clk or posedge rst) begin
            if (rst) begin
                ur_st <= UR_IDLE;
            end else begin
                case (ur_st)
                    UR_IDLE:
                        if (m_arvalid[m] && !uw_ar_mapped)
                            ur_st <= UR_RESP;
                    UR_RESP:
                        if (m_rready[m])
                            ur_st <= UR_IDLE;
                    default: ur_st <= UR_IDLE;
                endcase
            end
        end

        logic ur_arready;
        logic ur_rvalid;
        assign ur_arready = (ur_st == UR_IDLE) && m_arvalid[m] && !uw_ar_mapped;
        assign ur_rvalid  = (ur_st == UR_RESP);

        // ---- Collect slave contributions for this master ----
        logic slv_awready;
        logic slv_wready;
        logic slv_bvalid;
        logic [1:0] slv_bresp;
        logic slv_arready;
        logic slv_rvalid;
        logic [DATA_WIDTH-1:0] slv_rdata;
        logic [1:0] slv_rresp;
        logic slv_rlast;

        always_comb begin
            slv_awready = 1'b0;
            slv_wready  = 1'b0;
            slv_bvalid  = 1'b0;
            slv_bresp   = 2'b00;
            slv_arready = 1'b0;
            slv_rvalid  = 1'b0;
            slv_rdata   = '0;
            slv_rresp   = 2'b00;
            slv_rlast   = 1'b0;

            for (int s = 0; s < NUM_SLAVES; s++) begin
                // AWREADY: if this master is granted on slave s
                if (slv[s].aw_gnt_valid && slv[s].aw_gnt_mid == m)
                    slv_awready = slv[s].s_awready[s];
                // WREADY: if this master owns write on slave s
                if (slv[s].aw_owner[s] == m)
                    slv_wready = slv[s].s_wready[s];
                else if (slv[s].aw_gnt_valid && slv[s].aw_gnt_mid == m)
                    slv_wready = slv[s].s_wready[s];
                // BVALID: if this master owns write on slave s
                if (slv[s].aw_owner[s] == m) begin
                    slv_bvalid = slv[s].s_bvalid[s];
                    slv_bresp  = slv[s].s_bresp[s];
                end
                // ARREADY: if this master is granted on slave s
                if (slv[s].ar_gnt_valid && slv[s].ar_gnt_mid == m)
                    slv_arready = slv[s].s_arready[s];
                // RVALID: if this master owns read on slave s
                if (slv[s].ar_owner[s] == m) begin
                    slv_rvalid = slv[s].s_rvalid[s];
                    slv_rdata  = slv[s].s_rdata[s];
                    slv_rresp  = slv[s].s_rresp[s];
                    slv_rlast  = slv[s].s_rlast[s];
                end
            end
        end

        // ---- Final master signals: slave OR unmapped handler ----
        assign m_awready[m] = slv_awready | uw_awready;
        assign m_wready [m] = slv_wready  | uw_wready;
        assign m_bvalid [m] = slv_bvalid  | uw_bvalid;
        assign m_bresp  [m] = slv_bvalid ? slv_bresp : 2'b11;  // DECERR for unmapped

        assign m_arready[m] = slv_arready | ur_arready;
        assign m_rvalid [m] = slv_rvalid  | ur_rvalid;
        assign m_rdata  [m] = slv_rvalid ? slv_rdata : 32'hDEAD_BEEF;
        assign m_rresp  [m] = slv_rvalid ? slv_rresp : 2'b11;
        assign m_rlast  [m] = slv_rvalid ? slv_rlast : 1'b1;   // single beat for DECERR

    end : mst

`ifndef SYNTHESIS
    // ============================================================
    // Assertions: no master should see both slave and unmapped
    // responses simultaneously.
    // ============================================================
    for (genvar m = 0; m < NUM_MASTERS; m++) begin : chk
        always @(posedge clk) begin
            if (rst) begin
                // skip
            end else begin
                // Check: slave bvalid and unmapped bvalid should not both be 1
                if (mst[m].slv_bvalid && mst[m].uw_bvalid)
                    $error("[CROSSBAR] Master %0d: slave and unmapped B valid collision", m);
                if (mst[m].slv_rvalid && mst[m].ur_rvalid)
                    $error("[CROSSBAR] Master %0d: slave and unmapped R valid collision", m);
            end
        end
    end
`endif

endmodule
