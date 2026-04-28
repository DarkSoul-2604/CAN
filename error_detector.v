`timescale 1ns / 1ps

module error_detector (
    input  wire       clk,
    input  wire       rst_n,

    // Error inputs (1-cycle pulses)
    input  wire       bit_err,
    input  wire       stuff_err,
    input  wire       crc_err,
    input  wire       form_err,
    input  wire       ack_err,
    input  wire       arb_lost,

    // Success inputs (from FSMs)
    input  wire       tx_done,    // Frame transmitted successfully
    input  wire       rx_ready,   // Frame received successfully

    // Outputs to register file
    output reg  [7:0] tec,        // Transmit Error Counter
    output reg  [7:0] rec,        // Receive Error Counter
    output reg  [4:0] err_code,   // Encoded last error type
    output reg        bus_off,    // Node is bus-off (TEC >= 256)
    output wire       err_passive,// Node is error passive
    output wire       err_active  // Node is error active
);

    // Error code encoding
    localparam ERR_NONE  = 5'd0;
    localparam ERR_BIT   = 5'd1;
    localparam ERR_STUFF = 5'd2;
    localparam ERR_CRC   = 5'd3;
    localparam ERR_FORM  = 5'd4;
    localparam ERR_ACK   = 5'd5;
    localparam ERR_ARB   = 5'd6;

    // Error state thresholds (CAN spec)
    // Error Passive threshold: TEC >= 128 or REC >= 128
    // Bus-Off threshold:       TEC >= 256  (stored in 9 bits internally)
    reg [8:0] tec_full; // 9-bit to detect overflow past 255

    assign err_passive = (tec >= 8'd128) || (rec >= 8'd128);
    assign err_active  = ~err_passive & ~bus_off;

    // TX error increment (per CAN spec: +8 per TX error)
    // RX error increment: +1 per RX error
    // TX success: -1 (down to 0)
    // RX success: -1 (down to 127 minimum from passive side)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tec_full <= 9'd0;
            tec      <= 8'd0;
            rec      <= 8'd0;
            err_code <= ERR_NONE;
            bus_off  <= 1'b0;
        end else begin
            err_code <= ERR_NONE;

            if (!bus_off) begin
                //------ TX error events (increment TEC by 8) ------
                if (bit_err && ~arb_lost) begin
                    tec_full <= tec_full + 9'd8;
                    err_code <= ERR_BIT;
                end else if (ack_err) begin
                    tec_full <= tec_full + 9'd8;
                    err_code <= ERR_ACK;
                end else if (tx_done && tec_full > 9'd0) begin
                    // Successful TX: decrement TEC by 1
                    tec_full <= tec_full - 9'd1;
                end

                //------ RX error 
                if (stuff_err) begin
                    rec      <= (rec < 8'd255) ? rec + 8'd1 : rec;
                    err_code <= ERR_STUFF;
                end else if (crc_err) begin
                    rec      <= (rec < 8'd255) ? rec + 8'd1 : rec;
                    err_code <= ERR_CRC;
                end else if (form_err) begin
                    rec      <= (rec < 8'd255) ? rec + 8'd1 : rec;
                    err_code <= ERR_FORM;
                end else if (rx_ready && rec > 8'd0) begin
                    // Successful RX: decrement REC by 1 (min 0)
                    rec <= rec - 8'd1;
                end

                //------ Bus-off detection ------
                if (tec_full >= 9'd256) begin
                    bus_off  <= 1'b1;
                    tec_full <= 9'd255; // Cap display at 255
                end

                tec <= tec_full[7:0];
            end
            // Note: Bus-off recovery (128 recessive sequences) is
            // handled externally by reset_mode from the CPU.
        end
    end

endmodule