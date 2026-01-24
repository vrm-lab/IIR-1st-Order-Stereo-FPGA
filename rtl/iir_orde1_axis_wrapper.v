`timescale 1ns / 1ps

// ============================================================================
// iir_orde1_axis_wrapper
// ---------------------------------------------------------------------------
// AXI-Stream + AXI-Lite wrapper for a stereo 1st-order IIR filter core.
//
// - Stereo data packed as {Left[15:0], Right[15:0]}
// - AXI-Lite used for runtime control and coefficient updates
// - One-sample-per-cycle throughput when enabled
// - One-cycle processing latency
// ============================================================================

module iir_orde1_axis_wrapper #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 4,
    parameter integer DATA_WIDTH         = 32  // Fixed 32-bit stereo stream
)(
    // ------------------------------------------------------------------------
    // Global Clock & Reset
    // ------------------------------------------------------------------------
    input  wire aclk,
    input  wire aresetn,  // Active-low reset

    // ------------------------------------------------------------------------
    // AXI4-Stream Slave Interface (Input)
    // [31:16] Left channel, [15:0] Right channel
    // ------------------------------------------------------------------------
    input  wire [DATA_WIDTH-1:0] s_axis_tdata,
    input  wire                  s_axis_tvalid,
    output wire                  s_axis_tready,
    input  wire                  s_axis_tlast,

    // ------------------------------------------------------------------------
    // AXI4-Stream Master Interface (Output)
    // ------------------------------------------------------------------------
    output wire [DATA_WIDTH-1:0] m_axis_tdata,
    output reg                   m_axis_tvalid,
    input  wire                  m_axis_tready,
    output reg                   m_axis_tlast,

    // ------------------------------------------------------------------------
    // AXI4-Lite Slave Interface (Control & Coefficients)
    // ------------------------------------------------------------------------
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire                          s_axi_awvalid,
    output wire                          s_axi_awready,
    input  wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input  wire [C_S_AXI_DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  wire                          s_axi_wvalid,
    output wire                          s_axi_wready,
    output wire [1:0]                    s_axi_bresp,
    output wire                          s_axi_bvalid,
    input  wire                          s_axi_bready,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire                          s_axi_arvalid,
    output wire                          s_axi_arready,
    output wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output wire [1:0]                    s_axi_rresp,
    output wire                          s_axi_rvalid,
    input  wire                          s_axi_rready
);

    // =========================================================================
    // 1. AXI-Lite Registers
    // =========================================================================
    // Register map:
    // 0x00 : Control   [0]=Enable, [1]=Clear state
    // 0x04 : a0 coefficient (Q1.15)
    // 0x08 : a1 coefficient (Q1.15)
    // 0x0C : b1 coefficient (Q1.15)

    reg [C_S_AXI_DATA_WIDTH-1:0] reg_ctrl;
    reg [C_S_AXI_DATA_WIDTH-1:0] reg_a0;
    reg [C_S_AXI_DATA_WIDTH-1:0] reg_a1;
    reg [C_S_AXI_DATA_WIDTH-1:0] reg_b1;

    // AXI-Lite handshake signals
    reg axi_awready;
    reg axi_wready;
    reg [1:0] axi_bresp;
    reg axi_bvalid;
    reg axi_arready;
    reg [C_S_AXI_DATA_WIDTH-1:0] axi_rdata;
    reg axi_rvalid;

    reg aw_en;  // Single outstanding write control

    // AXI-Lite outputs
    assign s_axi_awready = axi_awready;
    assign s_axi_wready  = axi_wready;
    assign s_axi_bresp   = axi_bresp;
    assign s_axi_bvalid  = axi_bvalid;
    assign s_axi_arready = axi_arready;
    assign s_axi_rdata   = axi_rdata;
    assign s_axi_rresp   = 2'b00;  // OKAY
    assign s_axi_rvalid  = axi_rvalid;

    // =========================================================================
    // 2. AXI-Lite Write Channel
    // =========================================================================
    always @(posedge aclk) begin
        if (!aresetn) begin
            axi_awready <= 1'b0;
            axi_wready  <= 1'b0;
            axi_bvalid  <= 1'b0;
            axi_bresp   <= 2'b0;
            aw_en       <= 1'b1;

            reg_ctrl    <= 32'h0000_0001; // Enabled by default
            reg_a0      <= 32'd0;
            reg_a1      <= 32'd0;
            reg_b1      <= 32'd0;
        end else begin
            // Address channel
            if (~axi_awready && s_axi_awvalid && aw_en) begin
                axi_awready <= 1'b1;
                aw_en       <= 1'b0;
            end else begin
                axi_awready <= 1'b0;
            end

            // Write data channel
            if (~axi_wready && s_axi_wvalid) begin
                axi_wready <= 1'b1;
            end else begin
                axi_wready <= 1'b0;
            end

            // Register write
            if (axi_awready && s_axi_awvalid &&
                axi_wready  && s_axi_wvalid &&
                ~axi_bvalid) begin

                axi_bvalid <= 1'b1;
                axi_bresp  <= 2'b00;

                case (s_axi_awaddr[3:2])
                    2'h0: reg_ctrl <= s_axi_wdata;
                    2'h1: reg_a0   <= s_axi_wdata;
                    2'h2: reg_a1   <= s_axi_wdata;
                    2'h3: reg_b1   <= s_axi_wdata;
                    default: ;
                endcase
            end else if (s_axi_bready && axi_bvalid) begin
                axi_bvalid <= 1'b0;
                aw_en      <= 1'b1;
            end
        end
    end

    // =========================================================================
    // 3. AXI-Lite Read Channel
    // =========================================================================
    always @(posedge aclk) begin
        if (!aresetn) begin
            axi_arready <= 1'b0;
            axi_rvalid  <= 1'b0;
            axi_rdata   <= 32'd0;
        end else begin
            if (~axi_arready && s_axi_arvalid)
                axi_arready <= 1'b1;
            else
                axi_arready <= 1'b0;

            if (axi_arready && s_axi_arvalid && ~axi_rvalid) begin
                axi_rvalid <= 1'b1;
                case (s_axi_araddr[3:2])
                    2'h0: axi_rdata <= reg_ctrl;
                    2'h1: axi_rdata <= reg_a0;
                    2'h2: axi_rdata <= reg_a1;
                    2'h3: axi_rdata <= reg_b1;
                    default: axi_rdata <= 32'd0;
                endcase
            end else if (axi_rvalid && s_axi_rready) begin
                axi_rvalid <= 1'b0;
            end
        end
    end

    // =========================================================================
    // 4. Stereo IIR Core Integration
    // =========================================================================
    wire soft_enable_bit = reg_ctrl[0];
    wire soft_clear      = reg_ctrl[1];
    wire core_reset      = ~aresetn;

    // AXI-Stream handshake condition
    wire axis_handshake_ok =
        s_axis_tvalid && (m_axis_tready || !m_axis_tvalid);

    wire core_enable_signal =
        axis_handshake_ok && soft_enable_bit;

    assign s_axis_tready =
        (m_axis_tready || !m_axis_tvalid) && soft_enable_bit;

    // Input sample unpacking
    wire signed [15:0] data_in_L = s_axis_tdata[31:16];
    wire signed [15:0] data_in_R = s_axis_tdata[15:0];

    wire signed [15:0] data_out_L;
    wire signed [15:0] data_out_R;

    // Left channel core
    iir_orde1_core #(.ACC_W(64)) core_left (
        .clk        (aclk),
        .rst        (core_reset),
        .en         (core_enable_signal),
        .clear_state(soft_clear),
        .x_in       (data_in_L),
        .y_out      (data_out_L),
        .a0         (reg_a0[15:0]),
        .a1         (reg_a1[15:0]),
        .b1         (reg_b1[15:0])
    );

    // Right channel core
    iir_orde1_core #(.ACC_W(64)) core_right (
        .clk        (aclk),
        .rst        (core_reset),
        .en         (core_enable_signal),
        .clear_state(soft_clear),
        .x_in       (data_in_R),
        .y_out      (data_out_R),
        .a0         (reg_a0[15:0]),
        .a1         (reg_a1[15:0]),
        .b1         (reg_b1[15:0])
    );

    // =========================================================================
    // 5. AXI-Stream Output Control
    // =========================================================================
    always @(posedge aclk) begin
        if (!aresetn) begin
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
        end else if (m_axis_tready || !m_axis_tvalid) begin
            m_axis_tvalid <= s_axis_tvalid && soft_enable_bit;
            m_axis_tlast  <= s_axis_tlast;
        end
    end

    // Output sample packing
    assign m_axis_tdata = {data_out_L, data_out_R};

endmodule
