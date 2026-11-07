/********************************Copyright Statement**************************************
**
** TomatoCube & Minoyo
**
**------------------------------------Project Information --------------------------------
** Module   : top
** Board    : TomatoCube ICE40 HollowClock Dev Board
** Toolchain: APIO
** Purpose  : IR_Receiver Module
**            Operations: Decode 3 NEC pre-encoded IR Signal
**
**---------------------------Related Information of Modified Files------------------------
** File Modifier        : Percy Chen
** Modification Date    : 26th October 2026       
** Modification Content :
******************************************************************************************/

module IR_Receiver #(
    parameter [7:0] CMD_1 = 8'h02,
    parameter [7:0] CMD_2 = 8'h98,
    parameter [7:0] CMD_3 = 8'h18
) (
    input  wire clk,
    input  wire rst,
    input  wire ir_in,
    output reg  btn1,
    output reg  btn2,
    output reg  btn3
);

    // ============================================================
    // NEC Command bytes only — address bytes dropped to save LUTs
    // Bit reverse each byte of 40BF and 19E6
    // 40 = 0100 0000 reversed = 0000 0010 = 02
    // BF = 1011 1111 reversed = 1111 1101 = FD
    // 19 = 0001 1001 reversed = 1001 1000 = 98
    // E6 = 1110 0110 reversed = 0110 0111 = 67
    // 18 = 0001 1000 reversed = 0001 1000 = 18
    // E7 = 1110 0111 reversed = 1110 0111 = E7// Original full codes:
    //
    //   CODE_1 = 32'h00FF_02FD  → command byte = 8'h02
    //   CODE_2 = 32'h00FF_9867  → command byte = 8'h98
    //   CODE_3 = 32'h00FF_18E7  → command byte = 8'h18
    // ============================================================
//    localparam [7:0] CMD_1 = 8'h02;
//    localparam [7:0] CMD_2 = 8'h98;
//    localparam [7:0] CMD_3 = 8'h18;

    // ============================================================
    // Timing @ 12MHz
    // Prescaler: 200 cycles per tick = 16.67us per tick
    // Coarser tick = smaller timer constants = fewer LUT comparators
    //
    // NEC timing in ticks (1 tick = 16.67us):
    //   Leader LOW  : 9ms    = 540 ticks  (window: 486 - 594)
    //   Leader HIGH : 4.5ms  = 270 ticks  (window: 243 - 297)
    //   Bit LOW     : 560us  = 34  ticks  (window: 20  - 50 )
    //   Bit threshold: 135us = 68  ticks
    //   Timeout     : 750 ticks = 12.5ms
    // 10-bit timer: max 1023 ticks = 17ms — fits all NEC pulses
    // ============================================================
    localparam PRESCALE        = 8'd200;
    localparam LEADER_LOW_MIN  = 10'd486;
    localparam LEADER_LOW_MAX  = 10'd594;
    localparam LEADER_HIGH_MIN = 10'd243;
    localparam LEADER_HIGH_MAX = 10'd297;
    localparam BIT_THRESHOLD   = 10'd68;
    localparam TIMEOUT         = 10'd750;

    // ============================================================
    // Prescaler
    // ============================================================
    reg [7:0] prescale_cnt = 8'd0;
    reg       tick         = 1'b0;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            prescale_cnt <= 8'd0;
            tick         <= 1'b0;
        end else begin
            if (prescale_cnt == PRESCALE - 1) begin
                prescale_cnt <= 8'd0;
                tick         <= 1'b1;
            end else begin
                prescale_cnt <= prescale_cnt + 1'b1;
                tick         <= 1'b0;
            end
        end
    end

    // ============================================================
    // Edge detection — separate always block, every clock cycle
    // Single stage sync (saves LUTs, acceptable for IR signal)
    // ============================================================
    // reg ir_sync = 1'b1;
    // reg ir_prev = 1'b1;
    // 
    // wire ir_fall = ( ir_prev & ~ir_sync);
    // wire ir_rise = (~ir_prev &  ir_sync);
    // 
    // always @(posedge clk or posedge rst) begin
    //     if (rst) begin
    //         ir_sync <= 1'b1;
    //         ir_prev <= 1'b1;
    //     end else begin
    //         ir_sync <= ir_in;
    //         ir_prev <= ir_sync;
    //     end
    // end

    // ============================================================
    // Edge detection — TWO separate always blocks
    // Sync stage completely isolated to prevent DFFE generation
    // ============================================================

    // Stage 1 — sync register alone, nothing else
    reg ir_sync = 1'b1;
    always @(posedge clk or posedge rst) begin
        if (rst) ir_sync <= 1'b1;
        else     ir_sync <= ir_in;
    end

    // Stage 2 — edge detect register alone, nothing else
    reg ir_prev = 1'b1;
    always @(posedge clk or posedge rst) begin
        if (rst) ir_prev <= 1'b1;
        else     ir_prev <= ir_sync;
    end

    wire ir_fall = ( ir_prev & ~ir_sync);
    wire ir_rise = (~ir_prev &  ir_sync);

    // ============================================================
    // States — 2-bit, 4 states
    // ============================================================
    localparam ST_IDLE   = 2'd0;
    localparam ST_LEADER = 2'd1;
    localparam ST_BIT    = 2'd2;
    localparam ST_DONE   = 2'd3;

    reg [1:0] state     = ST_IDLE;
    reg       phase     = 1'b0;
    reg [9:0] timer     = 10'd0;   // 10-bit: covers up to 17ms
    reg [7:0] cmd_reg   = 8'd0;    // 8-bit: command byte only
    reg [5:0] bit_count = 6'd0;    // counts all 32 bits

    reg match1 = 1'b0;
    reg match2 = 1'b0;
    reg match3 = 1'b0;

    // ============================================================
    // FSM
    // ============================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= ST_IDLE;
            phase     <= 1'b0;
            timer     <= 10'd0;
            cmd_reg   <= 8'd0;
            bit_count <= 6'd0;
            match1    <= 1'b0;
            match2    <= 1'b0;
            match3    <= 1'b0;
        end else begin
            match1 <= 1'b0;
            match2 <= 1'b0;
            match3 <= 1'b0;

            if (tick && state != ST_IDLE && state != ST_DONE)
                timer <= timer + 1'b1;

            case (state)

                // -------------------------------------------------
                // Wait for falling edge
                // -------------------------------------------------
                ST_IDLE: begin
                    if (ir_fall) begin
                        timer <= 10'd0;
                        phase <= 1'b0;
                        state <= ST_LEADER;
                    end
                end

                // -------------------------------------------------
                // Leader: phase 0 = 9ms LOW, phase 1 = 4.5ms HIGH
                // -------------------------------------------------
                ST_LEADER: begin
                    if (timer >= TIMEOUT) begin
                        state <= ST_IDLE;
                    end else if (!phase && ir_rise) begin
                        if (timer >= LEADER_LOW_MIN && timer <= LEADER_LOW_MAX) begin
                            timer <= 10'd0;
                            phase <= 1'b1;
                        end else begin
                            state <= ST_IDLE;
                        end
                    end else if (phase && ir_fall) begin
                        if (timer >= LEADER_HIGH_MIN && timer <= LEADER_HIGH_MAX) begin
                            timer     <= 10'd0;
                            phase     <= 1'b0;
                            bit_count <= 6'd0;
                            cmd_reg   <= 8'd0;
                            state     <= ST_BIT;
                        end else begin
                            state <= ST_IDLE;
                        end
                    end
                end

                // -------------------------------------------------
                // Bits 0-31: only store bits 16-23 (command byte)
                // bit_count 16-23 = command, 24-31 = ~command
                // We only capture bits 16-23 to save LUTs
                // -------------------------------------------------
                ST_BIT: begin
                    if (timer >= TIMEOUT) begin
                        state <= ST_IDLE;
                    end else if (!phase && ir_rise) begin
                        // End of bit LOW — reset timer, start HIGH
                        timer <= 10'd0;
                        phase <= 1'b1;
                    end else if (phase && ir_fall) begin
                        // Only shift into cmd_reg during command byte (bits 16-23)
                        if (bit_count >= 6'd16 && bit_count <= 6'd23) begin
                            cmd_reg <= {cmd_reg[6:0], (timer >= BIT_THRESHOLD ? 1'b1 : 1'b0)};
                        end
                        timer <= 10'd0;
                        phase <= 1'b0;
                        if (bit_count == 6'd31) begin
                            state <= ST_DONE;
                        end else begin
                            bit_count <= bit_count + 1'b1;
                        end
                    end else if (phase && timer >= 10'd300) begin
                        // No falling edge — end of frame, commit last bit
                        if (bit_count >= 6'd16 && bit_count <= 6'd23) begin
                            cmd_reg <= {cmd_reg[6:0], (timer >= BIT_THRESHOLD ? 1'b1 : 1'b0)};
                        end
                        if (bit_count == 6'd31) begin
                            state <= ST_DONE;
                        end else begin
                            state <= ST_IDLE;
                        end
                    end
                end

                // -------------------------------------------------
                // Compare command byte only — 8-bit compare
                // -------------------------------------------------
                ST_DONE: begin
                    match1 <= (cmd_reg == CMD_1);
                    match2 <= (cmd_reg == CMD_2);
                    match3 <= (cmd_reg == CMD_3);
                    state  <= ST_IDLE;
                end

                default: state <= ST_IDLE;

            endcase
        end
    end

    // ============================================================
    // btn outputs — separate always block, plain DFFSR flops
    // ============================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            btn1 <= 1'b0;
            btn2 <= 1'b0;
            btn3 <= 1'b0;
        end else begin
            btn1 <= match1;
            btn2 <= match2;
            btn3 <= match3;
        end
    end

endmodule