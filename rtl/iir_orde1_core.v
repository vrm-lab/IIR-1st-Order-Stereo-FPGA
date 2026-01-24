`timescale 1ns / 1ps

// ============================================================================
// iir_orde1_core
// ---------------------------------------------------------------------------
// 1st-Order IIR Filter Core (Direct Form I)
// Fixed-point implementation in Q1.15 format
//
// Equation:
//   y[n] = a0*x[n] + a1*x[n-1] + b1*y[n-1]
//
// - Single-sample processing per clock when 'en' is asserted
// - One-cycle latency from input to output
// - Saturation applied to prevent Q1.15 overflow
// ============================================================================

module iir_orde1_core #(
    parameter integer ACC_W = 64  // Accumulator width for MAC operation
)(
    input  wire clk,
    input  wire rst,         // Synchronous reset (active high)
    input  wire en,          // Enable signal (sample processing valid)
    input  wire clear_state, // Clears internal filter state (x1, y1)

    input  wire signed [15:0] x_in,  // Input sample (Q1.15)
    output reg  signed [15:0] y_out, // Output sample (Q1.15)

    input  wire signed [15:0] a0,    // Feedforward coefficient a0 (Q1.15)
    input  wire signed [15:0] a1,    // Feedforward coefficient a1 (Q1.15)
    input  wire signed [15:0] b1     // Feedback coefficient b1 (Q1.15)
);

    // ------------------------------------------------------------------------
    // Internal State Registers
    // ------------------------------------------------------------------------
    reg signed [15:0] x1;  // Previous input sample x[n-1]
    reg signed [15:0] y1;  // Previous output sample y[n-1]

    // ------------------------------------------------------------------------
    // Internal Signals
    // ------------------------------------------------------------------------
    reg signed [ACC_W-1:0] acc_comb; // MAC accumulator (extended precision)
    reg signed [15:0]      y_next;   // Saturated output before register update

    // ------------------------------------------------------------------------
    // Sequential Logic
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            // Global reset: clear output and internal state
            x1    <= 0;
            y1    <= 0;
            y_out <= 0;

        end else if (en) begin
            if (clear_state) begin
                // Soft state clear without disabling the core
                x1    <= 0;
                y1    <= 0;
                y_out <= 0;

            end else begin
                // ------------------------------------------------------------
                // 1. Multiply-Accumulate (MAC)
                //    Blocking assignments are used intentionally to compute
                //    the full combinational result within this clock cycle.
                // ------------------------------------------------------------
                acc_comb = $signed(x_in) * a0 +
                           $signed(x1)   * a1 +
                           $signed(y1)   * b1;

                // ------------------------------------------------------------
                // 2. Saturation Logic (Q1.15)
                //    Result is right-shifted by 15 bits and clamped to
                //    signed 16-bit range to avoid overflow.
                // ------------------------------------------------------------
                if ((acc_comb >>> 15) > 32767)
                    y_next = 16'sd32767;
                else if ((acc_comb >>> 15) < -32768)
                    y_next = -16'sd32768;
                else
                    y_next = acc_comb[30:15];

                // ------------------------------------------------------------
                // 3. Output and State Update
                //    Non-blocking assignments ensure proper register timing.
                // ------------------------------------------------------------
                y_out <= y_next;
                x1    <= x_in;
                y1    <= y_next;
            end
        end
    end

endmodule
