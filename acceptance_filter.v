`timescale 1ns / 1ps

module acceptance_filter (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] acr_reg,
    input  wire [15:0] amr_reg,
    input  wire [10:0] rx_id,
    input  wire        rx_ready_in,
    output reg         rx_accepted,
    output reg         rx_filtered
);

    wire [10:0] acr = acr_reg[10:0];
    wire [10:0] amr = amr_reg[10:0];

    // bit matches if masked or equal
    wire id_match = (((rx_id ^ acr) & ~amr) == 11'd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_accepted <= 1'b0;
            rx_filtered <= 1'b0;
        end else begin
            rx_accepted <= 1'b0; // pulse
            rx_filtered <= 1'b0; // pulse

            if (rx_ready_in) begin
                if (id_match) rx_accepted <= 1'b1;
                else          rx_filtered <= 1'b1;
            end
        end
    end

endmodule