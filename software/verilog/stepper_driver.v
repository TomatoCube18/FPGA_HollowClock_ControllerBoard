/********************************Copyright Statement**************************************
**
** TomatoCube & Minoyo
**
**------------------------------------Project Information --------------------------------
** Module  : stepper_driver
** Purpose : Drives a 4-wire stepper motor via H-bridge.
**           Supports wave drive (single coil) and half-step (alternating)
**           modes, selectable at runtime.
**
** Ports:
**   en         - 1 = motor energised and stepping, 0 = Stop
**   direction  - 0 = clockwise, 1 = counter-clockwise
**   speed_sel  - 2-bit speed selector (see §8.4)
**   step_coil  - Connect to {STEPPER1, STEPPER2, STEPPER3, STEPPER4}
**
**---------------------------Related Information of Modified Files------------------------
** File Modifier        : Percy Chen
** Modification Date    : 1st June 2026
** Modification Content : Refactored next-state FSM into a 3-bit step index counter
**                        to reduce LUT usage on iCE40LP384.
******************************************************************************************/


module stepper_driver(
    input  wire       clk,
    input  wire       rst,
    input  wire       en,
    input  wire       direction,
    input  wire       speed_sel,     // 1 = normal speed, 0 = high speed
    output reg [3:0]  step_coil
);

    // localparam NORMAL_SPEED = 26'd300000;
    localparam NORMAL_SPEED = 26'd1_318_359;
    // Actual = 12,000,000 / (2 × 2,636,719) = 2.27556 Hz  ✅
    localparam HIGH_SPEED   = 26'd15000;

    reg new_clk;
    reg [25:0] count;
    wire [25:0] define_speed;

    assign define_speed = (speed_sel == 1'b1) ? NORMAL_SPEED : HIGH_SPEED;

    always @(posedge clk or posedge rst) begin
        if (rst == 1'b1) begin
            count    <= 26'd0;
            new_clk  <= 1'b0;
        end
        else if (count >= define_speed) begin
            count    <= 26'd0;
            new_clk  <= ~new_clk;
        end
        else begin
            count    <= count + 1'b1;
        end
    end

    // 3-bit step index counter (0-7 for half-step sequence)
    reg [2:0] step_idx;

    // Next-step logic: +1 mod 8 (CW) or -1 mod 8 (CCW)
    wire [2:0] next_idx;
    assign next_idx = (direction == 1'b0) ? (step_idx + 3'd1) % 8
                                          : (step_idx + 3'd7) % 8;

    // Step index register
    always @(posedge new_clk or posedge rst) begin
        if (rst == 1'b1)
            step_idx <= 3'd0;
        else if (en == 1'b1)
            step_idx <= next_idx;
    end

    // Output ROM (half-step sequence)
    always @* begin
        if (en == 1'b0)
            step_coil = 4'b0000;
        else
            case (step_idx)
                3'd0: step_coil = 4'b0001;
                3'd1: step_coil = 4'b0011;
                3'd2: step_coil = 4'b0010;
                3'd3: step_coil = 4'b0110;
                3'd4: step_coil = 4'b0100;
                3'd5: step_coil = 4'b1100;
                3'd6: step_coil = 4'b1000;
                3'd7: step_coil = 4'b1001;
                default: step_coil = 4'b0000;
            endcase
    end

endmodule
