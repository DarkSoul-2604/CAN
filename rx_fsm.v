`timescale 1ns / 1ps

module rx_fsm (
    input  wire        clk,
    input  wire        rst_n,


    input  wire        data_valid,    // HIGH when data_in is a real bit
    input  wire        data_in,       // Destuffed serial bit

    // CRC check
    input  wire [14:0] crc_rx,       

    // CPU control
    input  wire        rx_release,    

    // To CAN bus (ACK)
    output reg         ack_bit,     

    // To RX CRC module
    output reg         crc_en,        
    output reg         crc_clear,     

    // To reg file
    output reg  [10:0] rx_id,
    output reg  [3:0]  rx_dlc,
    output reg  [15:0] rx_data0,
    output reg  [15:0] rx_data1,
    output reg  [15:0] rx_data2,
    output reg  [15:0] rx_data3,
    output reg         rx_ready,      

    // To error detector
    output reg         crc_err,
    output reg         form_err,
    output reg         rx_active      
);

    // States
    localparam IDLE      = 4'd0;
    localparam ARB       = 4'd1;
    localparam CONTROL   = 4'd2;
    localparam DATA      = 4'd3;
    localparam CRC_RCV   = 4'd4;
    localparam CRC_DELIM = 4'd5;
    localparam ACK_SLOT  = 4'd6;
    localparam ACK_DELIM = 4'd7;
    localparam EOF       = 4'd8;
    localparam INTERMISSION   = 4'd9;

    reg [3:0]  state;
    reg [5:0]  bit_cnt;
    reg [3:0]  byte_cnt;
    reg [10:0] id_shift;
    reg [3:0]  dlc_shift;
    reg [14:0] crc_rcvd;   // CRC field received in the frame
    reg [63:0] data_shift; 
    reg        buf_full;   // RX buffer occupied

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            bit_cnt    <= 6'd0;
            byte_cnt   <= 4'd0;
            id_shift   <= 11'd0;
            dlc_shift  <= 4'd0;
            crc_rcvd   <= 15'd0;
            data_shift <= 64'd0;
            buf_full   <= 1'b0;
            ack_bit    <= 1'b1;
            crc_en     <= 1'b0;
            crc_clear  <= 1'b0;
            rx_id      <= 11'd0;
            rx_dlc     <= 4'd0;
            rx_data0   <= 16'd0;
            rx_data1   <= 16'd0;
            rx_data2   <= 16'd0;
            rx_data3   <= 16'd0;
            rx_ready   <= 1'b0;
            crc_err    <= 1'b0;
            form_err   <= 1'b0;
            rx_active  <= 1'b0;
        end else begin
            // Default pulse signals
            rx_ready  <= 1'b0;
            crc_err   <= 1'b0;
            form_err  <= 1'b0;
            crc_clear <= 1'b0;
            ack_bit   <= 1'b1;   // Default recessive

            if (rx_release)
                buf_full <= 1'b0;

            if (data_valid) begin
                case (state)

                
                IDLE: begin
                    crc_en    <= 1'b0;
                    rx_active <= 1'b0;
                    if (data_in == 1'b0) begin
                        // SOF detected - dominant bit starts frame
                        state     <= ARB;
                        bit_cnt   <= 6'd0;
                        id_shift  <= 11'd0;
                        dlc_shift <= 4'd0;
                        data_shift<= 64'd0;
                        crc_rcvd  <= 15'd0;
                        byte_cnt  <= 4'd0;
                        rx_active <= 1'b1;
                        crc_clear <= 1'b1;   // Reset CRC module
                        crc_en    <= 1'b1;   // SOF bit feeds CRC
                    end
                end

               
                ARB: begin
                    crc_en <= 1'b1;
                    if (bit_cnt < 6'd11) begin
                        id_shift <= {id_shift[9:0], data_in};
                    end
                    // bit 11 = RTR (0 = data frame, ignored here)
                    bit_cnt <= bit_cnt + 6'd1;
                    if (bit_cnt == 6'd11) begin
                        rx_id   <= id_shift;
                        bit_cnt <= 6'd0;
                        state   <= CONTROL;
                    end
                end

               
                CONTROL: begin
                    crc_en <= 1'b1;
                    if (bit_cnt == 6'd0 && data_in != 1'b0)
                        form_err <= 1'b1;   // IDE must be dominant
                    if (bit_cnt >= 6'd2)
                        dlc_shift <= {dlc_shift[2:0], data_in};
                    bit_cnt <= bit_cnt + 6'd1;
                    if (bit_cnt == 6'd5) begin
                        rx_dlc  <= {dlc_shift[2:0], data_in};
                        bit_cnt <= 6'd0;
                        state   <= ({dlc_shift[2:0], data_in} == 4'd0) ? CRC_RCV : DATA;
                    end
                end


                DATA: begin
                    crc_en     <= 1'b1;
                    data_shift <= {data_shift[62:0], data_in};
                    bit_cnt    <= bit_cnt + 6'd1;
                    if (bit_cnt == 6'd7) begin
                        bit_cnt  <= 6'd0;
                        byte_cnt <= byte_cnt + 4'd1;
                        if (byte_cnt + 4'd1 >= rx_dlc) begin
                            state <= CRC_RCV;
                        end
                    end
                end


                CRC_RCV: begin
                    crc_en   <= 1'b0;   // now reading frame CRC
                    crc_rcvd <= {crc_rcvd[13:0], data_in};
                    bit_cnt  <= bit_cnt + 6'd1;
                    if (bit_cnt == 6'd14) begin
                        bit_cnt <= 6'd0;
                        state   <= CRC_DELIM;
                    end
                end

                
                CRC_DELIM: begin
                    crc_en <= 1'b0;
                    if (data_in != 1'b1)
                        form_err <= 1'b1;
                    // Compare received CRC vs computed CRC
                    if (crc_rcvd != crc_rx)
                        crc_err <= 1'b1;
                    state <= ACK_SLOT;
                end

                
                ACK_SLOT: begin
                    ack_bit <= 1'b0;    // Dominant ACK
                    state   <= ACK_DELIM;
                end

               
                ACK_DELIM: begin
                    if (data_in != 1'b1)
                        form_err <= 1'b1;
                    bit_cnt <= 6'd0;
                    state   <= EOF;
                end

               
                EOF: begin
                    if (data_in != 1'b1)
                        form_err <= 1'b1;
                    bit_cnt <= bit_cnt + 6'd1;
                    if (bit_cnt == 6'd6) begin
                        bit_cnt <= 6'd0;
                        state   <= INTERMISSION;
                        // Store frame if buffer free and no errors
                        if (!crc_err && !form_err && !buf_full) begin
                            rx_ready <= 1'b1;
                            buf_full <= 1'b1;
                            // Unpack 64-bit shift register into four 16-bit words
                            rx_data0 <= data_shift[63:48];
                            rx_data1 <= data_shift[47:32];
                            rx_data2 <= data_shift[31:16];
                            rx_data3 <= data_shift[15:0];
                        end
                    end
                end

               
                INTERMISSION: begin
                    bit_cnt <= bit_cnt + 6'd1;
                    if (bit_cnt == 6'd2) begin
                        state     <= IDLE;
                        rx_active <= 1'b0;
                    end
                end

                default: state <= IDLE;
                endcase
            end
        end
    end

endmodule