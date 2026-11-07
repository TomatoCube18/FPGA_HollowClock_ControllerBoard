/********************************Copyright Statement**************************************
**
** TomatoCube & Minoyo
**
**------------------------------------Project Information --------------------------------
** Module   : top
** Board    : TomatoCube ICE40 HollowClock Dev Board
** Toolchain: APIO
** Purpose  : Running Clock Program with NEC IR Remote Decoder
**            Operations: Switch2 → Move Clock Time FWD Switch2 → Move Clock Time BCKWD.
**                        IR_Power_BTN1 → Toggle NeoPixel 
**                        IR_Power_BTN2 & IR_Power_BTN3 → Cycle through NeoPixel Colors
**
**---------------------------Related Information of Modified Files------------------------
** File Modifier        : Percy Chen
** Modification Date    : 26th October 2026       
** Modification Content :
******************************************************************************************/

module top (
    input  wire CLK_IN,      // FPGA clock input
    
    input  wire RST_IN,      // reset input
    input  wire SW2_IN,      // Hi-Speed Input Switch
    input  wire SW3_IN,      // Reverse + Hi-Speed Input Switch
    
    input  wire IR_IN,       // IR Input Pin
    
    output wire NEO_OUT,     // NeoPixel Output
    
    output wire STEPPER1,    // motor output 1
    output wire STEPPER2,    // motor output 2
    output wire STEPPER3,    // motor output 3
    output wire STEPPER4,    // motor output 4
    
    output wire LED1,        // led1 output
    output wire LED2,        // led2 output
    output wire LED3         // led3 output
);

    wire step_clk;
    wire [3:0] motor_signal;

    // =========================================================
    // Switch logic — both switches asserted LOW
    // speed_sel: HIGH when either SW2 or SW3 is pressed
    // dir:       LOW (reverse) when SW3 pressed, HIGH (forward) otherwise
    // =========================================================
    wire speed_sel = ~SW2_IN | ~SW3_IN;  // either switch = high speed
    wire dir       =  SW2_IN;            // SW2 pressed (LOW) = reverse

    wire ir_pwr;
    wire ir_prev;
    wire ir_next;

    // =========================================================
    // Power state — toggled by ir_pwr
    // Remembers last color when powered off
    // =========================================================
    reg power_on = 1'b0;

    always @(posedge CLK_IN or negedge RST_IN) begin
        if (!RST_IN)
            power_on <= 1'b0;
        else if (ir_pwr)
            power_on <= ~power_on;
    end

    // =========================================================
    // Color State Machine
    // 1 = Warm White
    // 2 = Orange
    // 3 = Cool Blue
    // color_state never goes to 0 — power_on handles OFF
    // =========================================================
    reg [1:0] color_state = 2'd1;

    always @(posedge CLK_IN or negedge RST_IN) begin
        if (!RST_IN) begin
            color_state <= 2'd1;
        end else begin
            if (ir_next) begin
                // Cycle forward: 1 -> 2 -> 3 -> 1
                if (color_state == 2'd3)
                    color_state <= 2'd1;
                else
                    color_state <= color_state + 1'b1;
            end else if (ir_prev) begin
                // Cycle backward: 1 -> 3 -> 2 -> 1
                if (color_state == 2'd1)
                    color_state <= 2'd3;
                else
                    color_state <= color_state - 1'b1;
            end
        end
    end

    // =========================================================
    // RGB output — gated by power_on
    // When off, send black (0,0,0) regardless of color_state
    // =========================================================
    reg [7:0] red   = 8'h00;
    reg [7:0] green = 8'h00;
    reg [7:0] blue  = 8'h00;

    always @(posedge CLK_IN or negedge RST_IN) begin
        if (!RST_IN) begin
            red   <= 8'h00;
            green <= 8'h00;
            blue  <= 8'h00;
        end else begin
            if (!power_on) begin
                // Power off — send black
                red   <= 8'h00;
                green <= 8'h00;
                blue  <= 8'h00;
            end else begin
                // Power on — output current color
                case (color_state)
                    2'd1: begin red <= 8'h40; green <= 8'h20; blue <= 8'h00; end  // Gold Yellow
                    2'd2: begin red <= 8'h40; green <= 8'h40; blue <= 8'h00; end  // Dark Yellow
                    2'd3: begin red <= 8'h00; green <= 8'h00; blue <= 8'h40; end  // Dark Blue
                    default: begin red <= 8'h00; green <= 8'h00; blue <= 8'h00; end
                endcase
            end
        end
    end

    

    neopixel_driver u_np (
        .clk        (CLK_IN),
        .rst        (~RST_IN),          // Active-HIGH reset
        .p0_red     (red),
        .p0_green   (green),
        .p0_blue    (blue),
        .p1_red     (red),
        .p1_green   (green),
        .p1_blue    (blue),
        .din        (NEO_OUT)           // Connect to NEO_OUT
    );

    IR_Receiver #(
        .CMD_1(8'h02),
        .CMD_2(8'h98),
        .CMD_3(8'h18)
        )ir_inst (
        .clk   (CLK_IN),
        .rst   (~RST_IN),
        //.rst   (1'b0),
        .ir_in (IR_IN),        // Asserted LOW from IR receiver module
        .btn1  (ir_pwr),
        .btn2  (ir_prev),
        .btn3  (ir_next)
    );


    stepper_driver u_stepper(
        .clk        (CLK_IN),
        .rst        (~RST_IN),
        .en         (1'b1),
        .direction  (~dir),
        .speed_sel  (~speed_sel),     // 1 = normal speed, 0 = high speed
        .step_coil  (motor_signal)
    );

    // Break out the 4-bit motor signal bus to individual pins
    assign STEPPER1 = motor_signal[0];
    assign STEPPER2 = motor_signal[1];
    assign STEPPER3 = motor_signal[2];
    assign STEPPER4 = motor_signal[3];

    assign LED1 = ~motor_signal[0];
    assign LED2 = ~motor_signal[1];
    assign LED3 = ~motor_signal[2];

endmodule