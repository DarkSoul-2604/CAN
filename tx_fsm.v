`timescale 1ns / 1ps

module tx_fsm (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        bit_tick,
    input  wire        tx_stall,
    input  wire        tx_req,
    input  wire        tx_abort,
    input  wire [10:0] tx_id,
    input  wire [3:0]  tx_dlc,
    input  wire [63:0] tx_data,
    input  wire [14:0] crc_computed,
    output reg         can_tx,
    output reg         tx_busy,
    output reg         tx_done,
    output reg         crc_en,
    output reg         crc_clear,
    output reg         ack_check,
    output wire        in_arb
);

    localparam IDLE         = 4'd0;
    localparam SOF          = 4'd1;
    localparam ARB          = 4'd2;
    localparam CONTROL      = 4'd3;
    localparam DATA         = 4'd4;
    localparam CRC          = 4'd5;
    localparam CRC_DELIM    = 4'd6;
    localparam ACK          = 4'd7;
    localparam ACK_DELIM    = 4'd8;
    localparam EOF          = 4'd9;
    localparam INTERMISSION = 4'd10;

    reg [3:0]  state;
    reg [10:0] id_reg;
    reg [3:0]  dlc_reg;
    reg [63:0] data_shift;
    reg [14:0] crc_shift;
    reg [4:0]  bit_cnt;
    reg [3:0]  byte_cnt;

    wire [3:0] dlc_eff = (tx_dlc > 4'd8) ? 4'd8 : tx_dlc;
    wire       tick    = bit_tick & ~tx_stall;

    assign in_arb = (state == ARB);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            can_tx     <= 1'b1;
            tx_busy    <= 1'b0;
            tx_done    <= 1'b0;
            crc_en     <= 1'b0;
            crc_clear  <= 1'b0;
            ack_check  <= 1'b0;
            id_reg     <= 11'd0;
            dlc_reg    <= 4'd0;
            data_shift <= 64'd0;
            crc_shift  <= 15'd0;
            bit_cnt    <= 5'd0;
            byte_cnt   <= 4'd0;
        end else begin
            tx_done   <= 1'b0;
            crc_clear <= 1'b0;
            ack_check <= 1'b0;

            if (tx_abort && (state != IDLE)) begin
                state     <= IDLE;
                can_tx    <= 1'b1;
                tx_busy   <= 1'b0;
                crc_en    <= 1'b0;
                bit_cnt   <= 5'd0;
                byte_cnt  <= 4'd0;
            end else if (tick) begin
                case (state)
                    IDLE: begin
                        can_tx   <= 1'b1;
                        tx_busy  <= 1'b0;
                        crc_en   <= 1'b0;
                        bit_cnt  <= 5'd0;
                        byte_cnt <= 4'd0;
                        if (tx_req) begin
                            tx_busy    <= 1'b1;
                            id_reg     <= tx_id;
                            dlc_reg    <= dlc_eff;
                            data_shift <= tx_data;
                            crc_clear  <= 1'b1;
                            state      <= SOF;
                        end
                    end

                    SOF: begin
                        can_tx <= 1'b0;
                        crc_en <= 1'b1;
                        bit_cnt <= 5'd0;
                        state  <= ARB;
                    end

                    ARB: begin
                        crc_en <= 1'b1;
                        if (bit_cnt < 5'd11) begin
                            can_tx  <= id_reg[10];
                            id_reg  <= {id_reg[9:0], 1'b0};
                            bit_cnt <= bit_cnt + 5'd1;
                        end else begin
                            can_tx  <= 1'b0; // RTR=0 (data frame)
                            bit_cnt <= 5'd0;
                            state   <= CONTROL;
                        end
                    end

                    CONTROL: begin
                        crc_en <= 1'b1;
                        case (bit_cnt)
                            5'd0: can_tx <= 1'b0;       // IDE
                            5'd1: can_tx <= 1'b0;       // r0
                            5'd2: can_tx <= dlc_reg[3];
                            5'd3: can_tx <= dlc_reg[2];
                            5'd4: can_tx <= dlc_reg[1];
                            default: can_tx <= dlc_reg[0];
                        endcase

                        if (bit_cnt == 5'd5) begin
                            bit_cnt  <= 5'd0;
                            byte_cnt <= 4'd0;
                            state    <= (dlc_reg == 4'd0) ? CRC : DATA;
                        end else begin
                            bit_cnt <= bit_cnt + 5'd1;
                        end
                    end

                    DATA: begin
                        crc_en     <= 1'b1;
                        can_tx     <= data_shift[63];
                        data_shift <= {data_shift[62:0], 1'b0};

                        if (bit_cnt == 5'd7) begin
                            bit_cnt  <= 5'd0;
                            byte_cnt <= byte_cnt + 4'd1;
                            if (byte_cnt + 4'd1 >= dlc_reg)
                                state <= CRC;
                        end else begin
                            bit_cnt <= bit_cnt + 5'd1;
                        end
                    end

                    CRC: begin
                        crc_en <= 1'b0;
                        if (bit_cnt == 5'd0) begin
                            can_tx    <= crc_computed[14];
                            crc_shift <= {crc_computed[13:0], 1'b0};
                        end else begin
                            can_tx    <= crc_shift[14];
                            crc_shift <= {crc_shift[13:0], 1'b0};
                        end

                        if (bit_cnt == 5'd14) begin
                            bit_cnt <= 5'd0;
                            state   <= CRC_DELIM;
                        end else begin
                            bit_cnt <= bit_cnt + 5'd1;
                        end
                    end

                    CRC_DELIM: begin
                        can_tx  <= 1'b1;
                        state   <= ACK;
                    end

                    ACK: begin
                        can_tx    <= 1'b1; // transmitter sends recessive in ACK slot
                        ack_check <= 1'b1;
                        state     <= ACK_DELIM;
                    end

                    ACK_DELIM: begin
                        can_tx <= 1'b1;
                        state  <= EOF;
                        bit_cnt <= 5'd0;
                    end

                    EOF: begin
                        can_tx <= 1'b1;
                        if (bit_cnt == 5'd6) begin
                            bit_cnt <= 5'd0;
                            state   <= INTERMISSION;
                        end else begin
                            bit_cnt <= bit_cnt + 5'd1;
                        end
                    end

                    INTERMISSION: begin
                        can_tx <= 1'b1;
                        if (bit_cnt == 5'd2) begin
                            state   <= IDLE;
                            tx_busy <= 1'b0;
                            tx_done <= 1'b1;
                            bit_cnt <= 5'd0;
                        end else begin
                            bit_cnt <= bit_cnt + 5'd1;
                        end
                    end

                    default: begin
                        state   <= IDLE;
                        can_tx  <= 1'b1;
                        tx_busy <= 1'b0;
                        crc_en  <= 1'b0;
                    end
                endcase
            end
        end
    end

endmodule
