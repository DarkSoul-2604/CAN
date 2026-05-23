`timescale 1ns / 1ps

module error_detector (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       bit_err,
    input  wire       stuff_err,
    input  wire       crc_err,
    input  wire       form_err,
    input  wire       ack_err,
    input  wire       arb_lost,

    input  wire       tx_done,
    input  wire       rx_ready,

    output reg  [7:0] tec,
    output reg  [7:0] rec,
    output reg  [4:0] err_code,
    output reg        bus_off,
    output wire       err_passive,
    output wire       err_active
);

    localparam ERR_NONE  = 5'd0;
    localparam ERR_BIT   = 5'd1;
    localparam ERR_STUFF = 5'd2;
    localparam ERR_CRC   = 5'd3;
    localparam ERR_FORM  = 5'd4;
    localparam ERR_ACK   = 5'd5;
    localparam ERR_ARB   = 5'd6;

    reg [8:0] tec_full;
    reg [8:0] tec_next;
    reg [7:0] rec_next;
    reg [4:0] err_next;

    assign err_passive = (tec >= 8'd128) || (rec >= 8'd128);
    assign err_active  = ~err_passive & ~bus_off;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tec_full <= 9'd0;
            tec      <= 8'd0;
            rec      <= 8'd0;
            err_code <= ERR_NONE;
            bus_off  <= 1'b0;
        end else begin
            tec_next = tec_full;
            rec_next = rec;
            err_next = err_code;

            if (!bus_off) begin
                if (bit_err && !arb_lost) begin
                    tec_next = tec_full + 9'd8;
                    err_next = ERR_BIT;
                end else if (ack_err) begin
                    tec_next = tec_full + 9'd8;
                    err_next = ERR_ACK;
                end else if (tx_done && (tec_full > 9'd0)) begin
                    tec_next = tec_full - 9'd1;
                end

                if (stuff_err) begin
                    rec_next = (rec == 8'hFF) ? rec : (rec + 8'd1);
                    err_next = ERR_STUFF;
                end else if (crc_err) begin
                    rec_next = (rec == 8'hFF) ? rec : (rec + 8'd1);
                    err_next = ERR_CRC;
                end else if (form_err) begin
                    rec_next = (rec == 8'hFF) ? rec : (rec + 8'd1);
                    err_next = ERR_FORM;
                end else if (rx_ready && (rec > 8'd0)) begin
                    rec_next = rec - 8'd1;
                end

                if (arb_lost)
                    err_next = ERR_ARB;

                if (tec_next >= 9'd256) begin
                    bus_off  <= 1'b1;
                    tec_full <= 9'd255;
                    tec      <= 8'hFF;
                end else begin
                    tec_full <= tec_next;
                    tec      <= tec_next[7:0];
                end

                rec      <= rec_next;
                err_code <= err_next;
            end
        end
    end

endmodule
