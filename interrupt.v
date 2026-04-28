`timescale 1ns / 1ps

module interrupt (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] int_en_reg,
    
    input  wire        tx_done,
    input  wire        rx_ready,
    input  wire        crc_err,
    input  wire        form_err,
    input  wire        stuff_err,
    input  wire        arb_lost,
    input  wire        bus_off,
    
    input  wire        ir_clr,
    // Outputs
    output reg  [15:0] ir_reg,      
    output reg         irq         
);

    
    wire any_err = crc_err | form_err | stuff_err;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ir_reg <= 16'd0;
            irq    <= 1'b0;
        end else begin
           
            if (tx_done)              ir_reg[0] <= 1'b1;
            if (rx_ready)             ir_reg[1] <= 1'b1;
            if (any_err)              ir_reg[2] <= 1'b1;
            if (arb_lost)             ir_reg[3] <= 1'b1;
            if (bus_off)              ir_reg[4] <= 1'b1;

          
            if (ir_clr)
                ir_reg <= 16'd0;

            
            irq <= |(ir_reg[4:0] & int_en_reg[4:0]);
        end
    end

endmodule