`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07.03.2026 18:18:14
// Design Name: 
// Module Name: crc
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1ns / 1ps

// Polynomial: x^15+x^14+x^10+x^8+x^7+x^4+x^3+1 = 0x4599
module crc(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,    
    input  wire        clear,     
    input  wire        data_in,   
    output wire [14:0] crc_out
);

reg [14:0] crc_reg;

assign crc_out = crc_reg;

wire crc_next = data_in ^ crc_reg[14];

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        crc_reg <= 15'd0;
    else if (clear)
        crc_reg <= 15'd0;
    else if (enable)
        crc_reg <= {crc_reg[13:0], 1'b0} ^ (crc_next ? 15'h4599 : 15'h0000);
end

endmodule