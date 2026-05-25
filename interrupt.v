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
    output reg  [15:0] ir_reg,
    output reg         irq
);

    wire any_err = crc_err | form_err | stuff_err;

    reg [15:0] ir_next;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ir_reg <= 16'd0;
            irq    <= 1'b0;
        end else begin
            ir_next = ir_reg;

            if (ir_clr) begin
                ir_next = 16'd0;
            end else begin
                if (tx_done)  ir_next[0] = 1'b1;
                if (rx_ready) ir_next[1] = 1'b1;
                if (any_err)  ir_next[2] = 1'b1;
                if (arb_lost) ir_next[3] = 1'b1;
                if (bus_off)  ir_next[4] = 1'b1;
            end

            ir_reg <= ir_next;
            irq    <= |(ir_next[4:0] & int_en_reg[4:0]);
        end
    end

endmodule
