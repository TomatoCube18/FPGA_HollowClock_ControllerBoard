/********************************Copyright Statement**************************************
**
** TomatoCube & Minoyo
**
**------------------------------------Project Information --------------------------------
** Module  : neopixel_driver
** Board   : TomatoCube ICE40 HollowClock Dev Board
** Purpose : Drives 2 chained NeoPixel addressable LEDs on NEO_OUT (pin 7).
**           Continuously transmits the current colour for both LEDs.
**           bit_index 0–23  → LED 0 (pixel0 green/red/blue)
**           bit_index 24–47 → LED 1 (pixel1 green/red/blue)
**
** Ports:
**   p0_red/green/blue - 8-bit colour for LED 0
**   p1_red/green/blue - 8-bit colour for LED 1
**   rst               - Active-HIGH reset 
**   din               - Connect to NEO_OUT pin
**
**---------------------------Related Information of Modified Files------------------------
** File Modifier        : Percy Chen
** Modification Date    : 1st June 2026       
** Modification Content :
******************************************************************************************/

module neopixel_driver (
    input  wire       clk,
    input  wire       rst,          // Active-HIGH reset
    input  wire [7:0] p0_red,
    input  wire [7:0] p0_green,
    input  wire [7:0] p0_blue,
    input  wire [7:0] p1_red,
    input  wire [7:0] p1_green,
    input  wire [7:0] p1_blue,
    output reg        din           // Connect to NEO_OUT
);

    // -------------------------------------------------------------------------
    // Timing constants at 12 MHz (1 cycle = 83.33 ns)
    // -------------------------------------------------------------------------
    localparam T_TOTAL      = 4'd15;   // 1.25 µs per bit
    localparam T0H          = 4'd4;    // ~333 ns - bit '0' high time
    localparam T1H          = 4'd11;   // ~917 ns - bit '1' high time
    localparam RESET_CYCLES = 12'd3500; // ~292 µs reset/latch

    // -------------------------------------------------------------------------
    // FSM states
    // -------------------------------------------------------------------------
    localparam ST_RESET = 1'b0;
    localparam ST_SEND  = 1'b1;

    reg        state       = ST_RESET;
    reg [11:0] reset_count = 12'd0;
    reg [3:0]  cycle_count = 4'd0;
    reg [5:0]  bit_index   = 6'd0;

    // -------------------------------------------------------------------------
    // GRB data for both pixels (assembled combinationally)
    // bit_index 0–23  → pixel 0 GRB
    // bit_index 24–47 → pixel 1 GRB
    // -------------------------------------------------------------------------
    wire [23:0] grb0 = {p0_green, p0_red, p0_blue};
    wire [23:0] grb1 = {p1_green, p1_red, p1_blue};

    // Select the correct GRB word and bit position combinationally
    // No pipeline delay - cur_bit is always valid on the current clock edge
    wire [5:0]  led_bit = (bit_index < 6'd24) ? bit_index : (bit_index - 6'd24);
    wire        cur_bit = (bit_index < 6'd24) ? grb0[23 - led_bit]
                                              : grb1[23 - led_bit];

    // -------------------------------------------------------------------------
    // Main FSM
    // -------------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state       <= ST_RESET;
            din         <= 1'b0;
            reset_count <= 12'd0;
            cycle_count <= 4'd0;
            bit_index   <= 6'd0;
        end else begin
            case (state)

                // ----- RESET / LATCH phase -----
                // Hold data line low for RESET_CYCLES to latch previous frame
                // and signal start of the next frame to the LED chain.
                ST_RESET: begin
                    din <= 1'b0;
                    if (reset_count < RESET_CYCLES - 1) begin
                        reset_count <= reset_count + 1'b1;
                    end else begin
                        reset_count <= 12'd0;
                        cycle_count <= 4'd0;
                        bit_index   <= 6'd0;
                        state       <= ST_SEND;
                    end
                end

                // ----- SEND phase -----
                // Transmit 48 bits (24 for LED 0, then 24 for LED 1).
                // Each bit slot is T_TOTAL cycles. High time encodes the bit:
                //   bit '1' → high for T1H cycles, then low
                //   bit '0' → high for T0H cycles, then low
                ST_SEND: begin
                    din <= cur_bit ? (cycle_count < T1H)
                                   : (cycle_count < T0H);

                    if (cycle_count == T_TOTAL - 1) begin
                        cycle_count <= 4'd0;
                        if (bit_index == 6'd47) begin
                            bit_index <= 6'd0;
                            state     <= ST_RESET;
                            din       <= 1'b0;
                        end else begin
                            bit_index <= bit_index + 1'b1;
                        end
                    end else begin
                        cycle_count <= cycle_count + 1'b1;
                    end
                end

                default: begin
                    state <= ST_RESET;
                    din   <= 1'b0;
                end

            endcase
        end
    end

endmodule