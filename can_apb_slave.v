`timescale 1ns / 1ps

module can_apb_slave (
    input  wire        PCLK,
    input  wire        PRESETn,
    input  wire        PSEL,
    input  wire        PENABLE,
    input  wire        PWRITE,
    input  wire [7:0]  PADDR,
    input  wire [15:0] PWDATA,

    output reg  [15:0] PRDATA,
    output reg         PREADY,
    output reg         PSLVERR,

    output reg         reg_write_en,
    output reg         reg_read_en,
    output reg [7:0]   reg_addr,
    output reg [15:0]  reg_wdata,

    input  wire [15:0] reg_rdata,

    output reg         tx_req,
    output reg         tx_abort,
    output reg         rx_release
);

    wire apb_setup  = PSEL && !PENABLE;
    wire apb_access = PSEL &&  PENABLE;

    
    wire addr_valid = (PADDR <= 8'h2A) && (PADDR[0] == 1'b0);

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            PRDATA       <= 16'd0;
            PREADY       <= 1'b0;
            PSLVERR      <= 1'b0;

            reg_write_en <= 1'b0;
            reg_read_en  <= 1'b0;
            reg_addr     <= 8'd0;
            reg_wdata    <= 16'd0;

            tx_req       <= 1'b0;
            tx_abort     <= 1'b0;
            rx_release   <= 1'b0;
        end else begin
            // defaults each cycle
            PREADY       <= 1'b0;
            PSLVERR      <= 1'b0;

            reg_write_en <= 1'b0;
            reg_read_en  <= 1'b0;

            tx_req       <= 1'b0;
            tx_abort     <= 1'b0;
            rx_release   <= 1'b0;

            
            if (apb_access) begin
                PREADY   <= 1'b1;
                reg_addr <= PADDR;

                if (!addr_valid) begin
                    PSLVERR <= 1'b1;
                end else if (PWRITE) begin
                    reg_wdata    <= PWDATA;
                    reg_write_en <= 1'b1;

                   
                    if (PADDR == 8'h01) begin
                        tx_req     <= PWDATA[0];
                        tx_abort   <= PWDATA[1];
                        rx_release <= PWDATA[2];
                    end
                end else begin
                    reg_read_en <= 1'b1;
                    PRDATA      <= reg_rdata;
                end
            end
        end
    end

endmodule