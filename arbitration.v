`timescale 1ns / 1ps

module arbitration (
    input  wire clk,
    input  wire rst_n,
    input  wire bit_tick,

    input  wire tx_active, // HIGH only while TX is in arbitration field
    input  wire can_tx,    //tx
    input  wire can_rx,    //rx

    output reg  arb_lost
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        arb_lost <= 1'b0;
    end else begin
    
        arb_lost <= 1'b0;

       //when tx is recessive and rx is dominant
        if (bit_tick && tx_active && (can_tx == 1'b1) && (can_rx == 1'b0))
            arb_lost <= 1'b1;
    end
end

endmodule