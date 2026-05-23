`timescale 1ns / 1ps

module rx_fsm (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        data_valid,
    input  wire        data_in,

    input  wire [14:0] crc_rx,

    input  wire        rx_release,

    output reg         ack_bit,

    output reg         crc_en,
    output reg         crc_clear,

    output reg  [10:0] rx_id,
    output reg  [3:0]  rx_dlc,
    output reg  [15:0] rx_data0,
    output reg  [15:0] rx_data1,
    output reg  [15:0] rx_data2,
    output reg  [15:0] rx_data3,
    output reg         rx_ready,

    output reg         crc_err,
    output reg         form_err,
    output reg         rx_active
);

    localparam IDLE         = 4'd0;
    localparam ARB          = 4'd1;
    localparam CONTROL      = 4'd2;
    localparam DATA         = 4'd3;
    localparam CRC_RCV      = 4'd4;
    localparam CRC_DELIM    = 4'd5;
    localparam ACK_SLOT     = 4'd6;
    localparam ACK_DELIM    = 4'd7;
    localparam EOF          = 4'd8;
    localparam INTERMISSION = 4'd9;

    reg [3:0]  state;
    reg [5:0]  bit_cnt;
    reg [3:0]  byte_cnt;
    reg [10:0] id_shift;
    reg [3:0]  dlc_shift;
    reg [3:0]  dlc_latched;
    reg [14:0] crc_rcvd;
    reg [63:0] data_shift;
    reg        buf_full;
    reg        frame_crc_bad;
    reg        frame_form_bad;

    wire [3:0] dlc_eff = (dlc_latched > 4'd8) ? 4'd8 : dlc_latched;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            bit_cnt       <= 6'd0;
            byte_cnt      <= 4'd0;
            id_shift      <= 11'd0;
            dlc_shift     <= 4'd0;
            dlc_latched   <= 4'd0;
            crc_rcvd      <= 15'd0;
            data_shift    <= 64'd0;
            buf_full      <= 1'b0;
            frame_crc_bad <= 1'b0;
            frame_form_bad<= 1'b0;

            ack_bit       <= 1'b1;
            crc_en        <= 1'b0;
            crc_clear     <= 1'b0;

            rx_id         <= 11'd0;
            rx_dlc        <= 4'd0;
            rx_data0      <= 16'd0;
            rx_data1      <= 16'd0;
            rx_data2      <= 16'd0;
            rx_data3      <= 16'd0;
            rx_ready      <= 1'b0;

            crc_err       <= 1'b0;
            form_err      <= 1'b0;
            rx_active     <= 1'b0;
        end else begin
            rx_ready  <= 1'b0;
            crc_err   <= 1'b0;
            form_err  <= 1'b0;
            crc_clear <= 1'b0;
            ack_bit   <= 1'b1;

            if (rx_release)
                buf_full <= 1'b0;

            if (data_valid) begin
                case (state)
                    IDLE: begin
                        crc_en    <= 1'b0;
                        rx_active <= 1'b0;
                        if (data_in == 1'b0) begin
                            state          <= ARB;
                            bit_cnt        <= 6'd0;
                            byte_cnt       <= 4'd0;
                            id_shift       <= 11'd0;
                            dlc_shift      <= 4'd0;
                            dlc_latched    <= 4'd0;
                            crc_rcvd       <= 15'd0;
                            data_shift     <= 64'd0;
                            frame_crc_bad  <= 1'b0;
                            frame_form_bad <= 1'b0;
                            rx_active      <= 1'b1;
                            crc_clear      <= 1'b1;
                            crc_en         <= 1'b1;
                        end
                    end

                    ARB: begin
                        crc_en <= 1'b1;

                        if (bit_cnt < 6'd11) begin
                            id_shift <= {id_shift[9:0], data_in};
                            if (bit_cnt == 6'd10)
                                rx_id <= {id_shift[9:0], data_in};
                        end

                        if (bit_cnt == 6'd11) begin
                            bit_cnt <= 6'd0;
                            state   <= CONTROL;
                        end else begin
                            bit_cnt <= bit_cnt + 6'd1;
                        end
                    end

                    CONTROL: begin
                        crc_en <= 1'b1;

                        if ((bit_cnt == 6'd0) && (data_in != 1'b0)) begin
                            form_err       <= 1'b1;
                            frame_form_bad <= 1'b1;
                        end

                        if ((bit_cnt == 6'd1) && (data_in != 1'b0)) begin
                            form_err       <= 1'b1;
                            frame_form_bad <= 1'b1;
                        end

                        if (bit_cnt >= 6'd2)
                            dlc_shift <= {dlc_shift[2:0], data_in};

                        if (bit_cnt == 6'd5) begin
                            dlc_latched <= {dlc_shift[2:0], data_in};
                            rx_dlc      <= ({dlc_shift[2:0], data_in} > 4'd8) ? 4'd8 : {dlc_shift[2:0], data_in};
                            bit_cnt     <= 6'd0;
                            byte_cnt    <= 4'd0;
                            state       <= ({dlc_shift[2:0], data_in} == 4'd0) ? CRC_RCV : DATA;
                        end else begin
                            bit_cnt <= bit_cnt + 6'd1;
                        end
                    end

                    DATA: begin
                        crc_en     <= 1'b1;
                        data_shift <= {data_shift[62:0], data_in};

                        if (bit_cnt == 6'd7) begin
                            bit_cnt  <= 6'd0;
                            byte_cnt <= byte_cnt + 4'd1;
                            if (byte_cnt + 4'd1 >= dlc_eff)
                                state <= CRC_RCV;
                        end else begin
                            bit_cnt <= bit_cnt + 6'd1;
                        end
                    end

                    CRC_RCV: begin
                        crc_en   <= 1'b0;
                        crc_rcvd <= {crc_rcvd[13:0], data_in};

                        if (bit_cnt == 6'd14) begin
                            bit_cnt <= 6'd0;
                            state   <= CRC_DELIM;
                        end else begin
                            bit_cnt <= bit_cnt + 6'd1;
                        end
                    end

                    CRC_DELIM: begin
                        crc_en <= 1'b0;
                        if (data_in != 1'b1) begin
                            form_err       <= 1'b1;
                            frame_form_bad <= 1'b1;
                        end
                        if (crc_rcvd != crc_rx) begin
                            crc_err       <= 1'b1;
                            frame_crc_bad <= 1'b1;
                        end
                        state <= ACK_SLOT;
                    end

                    ACK_SLOT: begin
                        ack_bit <= (frame_crc_bad || frame_form_bad) ? 1'b1 : 1'b0;
                        state   <= ACK_DELIM;
                    end

                    ACK_DELIM: begin
                        if (data_in != 1'b1) begin
                            form_err       <= 1'b1;
                            frame_form_bad <= 1'b1;
                        end
                        bit_cnt <= 6'd0;
                        state   <= EOF;
                    end

                    EOF: begin
                        if (data_in != 1'b1) begin
                            form_err       <= 1'b1;
                            frame_form_bad <= 1'b1;
                        end

                        if (bit_cnt == 6'd6) begin
                            bit_cnt <= 6'd0;
                            state   <= INTERMISSION;
                            if (!frame_crc_bad && !frame_form_bad && !buf_full) begin
                                rx_ready  <= 1'b1;
                                buf_full  <= 1'b1;
                                rx_data0  <= data_shift[63:48];
                                rx_data1  <= data_shift[47:32];
                                rx_data2  <= data_shift[31:16];
                                rx_data3  <= data_shift[15:0];
                            end
                        end else begin
                            bit_cnt <= bit_cnt + 6'd1;
                        end
                    end

                    INTERMISSION: begin
                        if (bit_cnt == 6'd2) begin
                            state     <= IDLE;
                            rx_active <= 1'b0;
                            bit_cnt   <= 6'd0;
                        end else begin
                            bit_cnt <= bit_cnt + 6'd1;
                        end
                    end

                    default: state <= IDLE;
                endcase
            end
        end
    end

endmodule
