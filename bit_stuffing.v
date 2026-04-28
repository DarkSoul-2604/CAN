`timescale 1ns / 1ps

module bit_stuffing (
    input  wire clk,
    input  wire rst_n,

    input  wire tx_en,       // stuffing 
    input  wire rx_en,       // destuffing 
    input  wire bit_tick,    
    input  wire sample_tick, 
    input  wire clear,       
    input  wire data_in,     

    output reg  data_out,    
    output reg  data_valid,  
    output reg  stuff_err,   
    output wire tx_stall
);

    reg [2:0] cnt;       
    reg       last_bit;  

    
    assign tx_stall = tx_en && bit_tick && (cnt == 3'd5);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || clear) begin
            cnt        <= 3'd1;   
            last_bit   <= 1'b1;   
            data_out   <= 1'b1;
            data_valid <= 1'b0;
            stuff_err  <= 1'b0;
        end else begin
            // default
            data_valid <= 1'b0;
            stuff_err  <= 1'b0;

            // TX STUFFING
            if (tx_en && bit_tick) begin
                if (cnt == 3'd5) begin
                    //insert stuffed bit 
                    data_out <= ~last_bit;
                    last_bit <= ~last_bit;
                    cnt      <= 3'd1;
                end else begin
                    data_out <= data_in;
                    if (data_in == last_bit)
                        cnt <= cnt + 3'd1;
                    else begin
                        last_bit <= data_in;
                        cnt      <= 3'd1;
                    end
                end
            end

            // RX DESTUFFING
            if (rx_en && sample_tick) begin
                if (cnt == 3'd5) begin
                    if (data_in == last_bit) begin 
                        //error (6 bits same) 
                        stuff_err  <= 1'b1;
                        data_out   <= data_in;
                        data_valid <= 1'b1; 
                        cnt        <= 3'd1;
                        
                    end else begin
                        data_valid <= 1'b0;
                        last_bit   <= data_in;
                        cnt        <= 3'd1;
                    end
                end else begin
                    // normal payload
                    data_out   <= data_in;
                    data_valid <= 1'b1;
                    if (data_in == last_bit)
                        cnt <= cnt + 3'd1;
                    else begin
                        last_bit <= data_in;
                        cnt      <= 3'd1;
                    end
                end
            end
        end
    end

endmodule