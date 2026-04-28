`timescale 1ns / 1ps

module can_bit_timing(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] btr_reg,   // [5:0]=BRP, [9:6]=TSEG1, [12:10]=TSEG2, [14:13]=SJW
    input  wire        can_rx,
    output reg         tq_tick,
    output reg         sample_tick,
    output reg         bit_tick
);

wire [5:0] brp   = btr_reg[5:0];
wire [3:0] tseg1 = btr_reg[9:6];
wire [2:0] tseg2 = btr_reg[12:10];
wire [1:0] sjw   = btr_reg[14:13];

reg [5:0] prescaler_cnt;
reg       can_rx_d;
reg [5:0] tq_cnt;

wire edge_detected = can_rx ^ can_rx_d;
wire [5:0] bit_time = 6'd1 + {2'd0,tseg1} + {3'd0,tseg2}; // Sync + TSEG1 + TSEG2

// Prescaler: generate tq_tick
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        prescaler_cnt <= 6'd0;
        tq_tick       <= 1'b0;
    end else begin
        if (brp == 6'd0 || prescaler_cnt == (brp - 6'd1)) begin         ///////////
            prescaler_cnt <= 6'd0;
            tq_tick       <= 1'b1;
        end else begin
            prescaler_cnt <= prescaler_cnt + 6'd1;
            tq_tick       <= 1'b0;
        end
    end
end

// Edge detect
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) can_rx_d <= 1'b1;
    else        can_rx_d <= can_rx;
end


always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tq_cnt      <= 6'd0;
        sample_tick <= 1'b0;
        bit_tick    <= 1'b0;
    end else begin
        sample_tick <= 1'b0;
        bit_tick    <= 1'b0;

        if (tq_tick) begin
            // sample point at end of TSEG1
            if (tq_cnt == {2'd0,tseg1})
                sample_tick <= 1'b1;

            // hard sync only at start of bit (tq_cnt==0)
            if (edge_detected && tq_cnt == 6'd0) begin
                tq_cnt <= 6'd0;
            end
            // resync during bit
            else if (edge_detected) begin
                if (tq_cnt < {2'd0,tseg1}) begin
                    // (late edge) - lengthen by up to SJW
                    if ((({2'd0,tseg1} - tq_cnt) > {4'd0,sjw}))
                        tq_cnt <= tq_cnt + {4'd0,sjw};
                    else
                        tq_cnt <= {2'd0,tseg1};
                end else begin
                    // (early edge) - shorten by up to SJW
                    if (((tq_cnt - {2'd0,tseg1}) > {4'd0,sjw}))
                        tq_cnt <= tq_cnt - {4'd0,sjw};
                    else
                        tq_cnt <= {2'd0,tseg1};
                end
            end
          
            else begin
                if (tq_cnt == (bit_time - 6'd1)) begin
                    tq_cnt   <= 6'd0;
                    bit_tick <= 1'b1;
                end else begin
                    tq_cnt <= tq_cnt + 6'd1;
                end
            end
        end
    end
end

endmodule