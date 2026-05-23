`timescale 1ns / 1ps

module tb_bittiming;

    reg clk;
    reg rst_n;
    reg [15:0] btr_reg;
    reg can_rx;

    wire tq_tick;
    wire sample_tick;
    wire bit_tick;

    integer clk_count;
    integer tq_count;
    integer bit_count;
    integer fail_count;
    integer prev_tq_clk;
    integer tq_period_fail;

    can_bit_timing dut (
        .clk(clk),
        .rst_n(rst_n),
        .btr_reg(btr_reg),
        .can_rx(can_rx),
        .tq_tick(tq_tick),
        .sample_tick(sample_tick),
        .bit_tick(bit_tick)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (rst_n) begin
            clk_count <= clk_count + 1;
            if (tq_tick) begin
                tq_count  <= tq_count + 1;
                if (prev_tq_clk >= 0 && (clk_count - prev_tq_clk) != 3)
                    tq_period_fail <= tq_period_fail + 1;
                prev_tq_clk <= clk_count;
            end
            if (bit_tick) bit_count <= bit_count + 1;
        end
    end

    initial begin
        rst_n = 1'b0;
        // BRP=2, TSEG1=2, TSEG2=1, SJW=1
        btr_reg = 16'd0;
        btr_reg[5:0]   = 6'd2;
        btr_reg[9:6]   = 4'd2;
        btr_reg[12:10] = 3'd1;
        btr_reg[14:13] = 2'd1;
        can_rx = 1'b1;

        clk_count  = 0;
        tq_count   = 0;
        bit_count  = 0;
        fail_count = 0;
        prev_tq_clk = -1;
        tq_period_fail = 0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        repeat (24) @(posedge clk);

        if (tq_count < 6) begin
            $display("[FAIL] Expected at least 6 tq ticks, got %0d", tq_count);
            fail_count = fail_count + 1;
        end
        
        if (tq_period_fail != 0) begin
            $display("[FAIL] TQ period not constant BRP+1 cycles; failures=%0d", tq_period_fail);
            fail_count = fail_count + 1;
        end

        if (bit_count < 1) begin
            $display("[FAIL] Expected at least 1 bit tick, got %0d", bit_count);
            fail_count = fail_count + 1;
        end

        if (fail_count == 0)
            $display("TB_RESULT: SUCCESS");
        else
            $display("TB_RESULT: FAILED (%0d)", fail_count);

        #20;
        $finish;
    end

endmodule
