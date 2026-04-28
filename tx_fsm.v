`timescale 1ns / 1ps

module tx_fsm (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        bit_tick,
    input  wire        tx_stall,      //for adding bitstuffing bit
    input  wire        tx_req,
    input  wire [10:0] tx_id,
    input  wire [3:0]  tx_dlc,
    input  wire [63:0] tx_data,
    input  wire        can_rx,
    input  wire [14:0] crc_computed,   
    output reg         can_tx,
    output reg         tx_busy,
    output reg         tx_done,
    output reg         crc_en,
    output reg         crc_clear,      
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

    reg [3:0]  state, next_state;
    reg [10:0] id_reg;
    reg        rtr_reg;
    reg [63:0] data_shift;
    reg [5:0]  control_reg;
    reg [14:0] crc_shift;
    reg [4:0]  bit_cnt;
    reg [3:0]  byte_cnt;


    wire tick = bit_tick & ~tx_stall;   // tick- 1 stall -0

    assign in_arb = (state == ARB);

 //state 
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        state <= IDLE;
    else if (tick)
        state <= next_state;
    end
//nest state 
    always @(*) begin
        next_state = state;
        case (state)
            IDLE:
                if (tx_req)
                next_state = SOF;
            SOF:
                next_state = ARB;
            ARB:  //11 id+ IDE
                if (bit_cnt == 5'd11) 
                next_state = CONTROL;
            CONTROL:   // 
                if (bit_cnt == 5'd5)
                    next_state = (tx_dlc == 4'd0) ? CRC : DATA; // to check is data available or 
            DATA:
                if (byte_cnt == tx_dlc && bit_cnt == 5'd7)
                    next_state = CRC;
            CRC:
                if (bit_cnt == 5'd14)
                    next_state = CRC_DELIM;
            CRC_DELIM:
                next_state = ACK;
            ACK:
                next_state = ACK_DELIM;
            ACK_DELIM:
                next_state = EOF;
            EOF:
                if (bit_cnt == 5'd6)
                    next_state = INTERMISSION;
            INTERMISSION:
                if (bit_cnt == 5'd2)
                    next_state = IDLE;
            default:
                next_state = IDLE;
        endcase
    end

    // ---- Data path
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            can_tx    <= 1'b1;
            tx_busy   <= 1'b0;
            tx_done   <= 1'b0;
            crc_en    <= 1'b0;
            crc_clear <= 1'b0;
            bit_cnt   <= 5'd0;
            byte_cnt  <= 4'd0;
            id_reg    <= 11'd0;
            rtr_reg   <= 1'b0;
            data_shift<= 64'd0;
            control_reg <= 6'd0;
            crc_shift <= 15'd0;
        end else begin
            crc_clear <= 1'b0;
            tx_done   <= 1'b0;

            if (tick) begin
                
                crc_en <= (next_state == SOF   || next_state == ARB    ||
                           next_state == CONTROL|| next_state == DATA   ||
                           state == SOF || state == ARB ||
                           state == CONTROL || state == DATA);

                case (state)
                //---- IDLE
                IDLE: begin
                    can_tx  <= 1'b1;
                    tx_busy <= 1'b0;
                    crc_en  <= 1'b0;
                    if (tx_req)
                    begin
                        tx_busy     <= 1'b1;
                        id_reg      <= tx_id;
                        rtr_reg     <= 1'b0;
                        data_shift  <= tx_data;
                        control_reg <= {1'b0, 1'b0, tx_dlc}; // IDE=0, r0=0, DLC
                        crc_clear   <= 1'b1;
                        bit_cnt     <= 5'd0;
                        byte_cnt    <= 4'd0;
                    end
                end
                //SOF
                SOF: begin
                    can_tx  <= 1'b0;
                    crc_en  <= 1'b1;
                    bit_cnt <= 5'd0;
                end
                //ARBITRATION (ID + RTR)
                ARB: begin
                    crc_en <= 1'b1;
                    if (bit_cnt < 5'd11) begin
                        can_tx <= id_reg[10];
                        id_reg <= {id_reg[9:0], 1'b0};
                    end else begin
                        can_tx <= rtr_reg;
                    end
                    bit_cnt <= bit_cnt + 5'd1;//counter
                end
                //CONTROL: IDE + r0 + DLC[3:0]
                CONTROL: begin
                    crc_en     <= 1'b1;
                    can_tx     <= control_reg[5];
                    control_reg<= {control_reg[4:0], 1'b0};
                    bit_cnt    <= bit_cnt + 5'd1;
                end
                //DATA
                DATA: begin
                    crc_en     <= 1'b1;
                    can_tx     <= data_shift[63];
                    data_shift <= {data_shift[62:0], 1'b0};
                    bit_cnt    <= bit_cnt + 5'd1;
                    if (bit_cnt == 5'd7) begin
                        bit_cnt  <= 5'd0;
                        byte_cnt <= byte_cnt + 4'd1;
                    end
                end
                //---- CRC
                CRC: begin
                    crc_en <= 1'b0;
                    if (bit_cnt == 5'd0)
                        crc_shift <= crc_computed;  
                    can_tx    <= crc_shift[14];
                    crc_shift <= {crc_shift[13:0], 1'b0};
                    bit_cnt   <= bit_cnt + 5'd1;
                end
                //---- CRC DELIMITER
                CRC_DELIM: begin
                    can_tx  <= 1'b1;
                    crc_en  <= 1'b0;
                    bit_cnt <= 5'd0;
                end
                //---- ACK
                ACK: begin
                    can_tx  <= 1'b1;
                    bit_cnt <= 5'd0;
                end
                //---- ACK DELIMITER
                ACK_DELIM: begin
                    can_tx  <= 1'b1;
                    bit_cnt <= 5'd0;
                end
                //---- EOF
                EOF: begin
                    can_tx  <= 1'b1;
                    bit_cnt <= bit_cnt + 5'd1;
                    if (bit_cnt == 5'd6) begin
                        tx_done <= 1'b1;
                        tx_busy <= 1'b0;
                    end
                end
             
                INTERMISSION: begin
                    can_tx  <= 1'b1;
                    bit_cnt <= bit_cnt + 5'd1;
                end
                endcase
            end
        end
    end

endmodule