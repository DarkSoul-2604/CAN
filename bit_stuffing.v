`timescale 1ns / 1ps

module bit_stuffing (
    input  wire clk,
    input  wire rst_n,

    input  wire tx_en,
    input  wire rx_en,
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
            cnt        <= 3'd0;
            last_bit   <= 1'b1;
            data_out   <= 1'b1;
            data_valid <= 1'b0;
            stuff_err  <= 1'b0;
        end else begin
            data_valid <= 1'b0;
            stuff_err  <= 1'b0;

            if (tx_en && bit_tick) begin
                if (cnt == 3'd0) begin
                    data_out  <= data_in;
                    last_bit  <= data_in;
                    cnt       <= 3'd1;
                end else if (cnt == 3'd5) begin
                    // Stuff inserted bit (complement), upstream is stalled this cycle
                    data_out  <= ~last_bit;
                    last_bit  <= ~last_bit;
                    cnt       <= 3'd1;
                end else begin
                    data_out <= data_in;
                    if (data_in == last_bit)
                        cnt <= cnt + 3'd1;
                    else begin
                        last_bit <= data_in;
                        cnt      <= 3'd1;
                    end
                end
            end else if (rx_en && sample_tick) begin
                if (cnt == 3'd0) begin
                    data_out   <= data_in;
                    data_valid <= 1'b1;
                    last_bit   <= data_in;
                    cnt        <= 3'd1;
                end else if (cnt == 3'd5) begin
                    if (data_in == last_bit) begin
                        // 6 identical bits: stuffing violation
                        stuff_err  <= 1'b1;
                        data_valid <= 1'b0;
                        last_bit   <= data_in;
                        cnt        <= 3'd1;
                    end else begin
                        // valid stuffed bit: drop it
                        data_valid <= 1'b0;
                        last_bit   <= data_in;
                        cnt        <= 3'd1;
                    end
                end else begin
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
