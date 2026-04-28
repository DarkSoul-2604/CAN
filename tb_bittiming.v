`timescale 1ns / 1ps

module tb_bit_stuffing;

    reg  clk;
    reg  rst_n;
    reg  tx_en;
    reg  rx_en;
    reg  bit_tick;
    reg  sample_tick;
    reg  clear;
    reg  data_in;

    wire data_out;
    wire data_valid;
    wire stuff_err;
    wire tx_stall;

    integer pass_count;
    integer fail_count;

    // DUT
    bit_stuffing dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .tx_en      (tx_en),
        .rx_en      (rx_en),
        .bit_tick   (bit_tick),
        .sample_tick(sample_tick),
        .clear      (clear),
        .data_in    (data_in),
        .data_out   (data_out),
        .data_valid (data_valid),
        .stuff_err  (stuff_err),
        .tx_stall   (tx_stall)
    );

    // clock
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ---------------- helpers ----------------
    task check;
        input cond;
        input [255:0] msg;
        begin
            if (cond) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0t : %0s", $time, msg);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0t : %0s", $time, msg);
            end
        end
    endtask

    task reset_dut;
        begin
            rst_n       = 1'b0;
            tx_en       = 1'b0;
            rx_en       = 1'b0;
            bit_tick    = 1'b0;
            sample_tick = 1'b0;
            clear       = 1'b0;
            data_in     = 1'b1;
            repeat (3) @(posedge clk);
            rst_n = 1'b1;
            @(posedge clk);
        end
    endtask

    task pulse_clear;
        begin
            clear = 1'b1;
            @(posedge clk);
            clear = 1'b0;
            @(posedge clk);
        end
    endtask

    task tx_send_bit;
        input b;
        begin
            data_in   = b;
            bit_tick  = 1'b1;
            @(posedge clk);
            bit_tick  = 1'b0;
            @(posedge clk);
        end
    endtask

    task rx_sample_bit;
        input b;
        begin
            data_in      = b;
            sample_tick  = 1'b1;
            @(posedge clk);
            sample_tick  = 1'b0;
            @(posedge clk);
        end
    endtask

    // ---------------- test sequence ----------------
    initial begin
        pass_count = 0;
        fail_count = 0;

        $dumpfile("tb_bit_stuffing.vcd");
        $dumpvars(0, tb_bit_stuffing);

        // ========== TEST 0: Reset ==========
        reset_dut();
        check(data_out == 1'b1, "Reset: data_out default recessive");
        check(data_valid == 1'b0, "Reset: data_valid low");
        check(stuff_err == 1'b0, "Reset: stuff_err low");
        check(tx_stall == 1'b0, "Reset: tx_stall low");

        // ========== TEST 1: TX no stuffing for alternating bits ==========
        tx_en = 1'b1; rx_en = 1'b0;
        tx_send_bit(1'b1); check(data_out==1'b1, "TX alt bit1");
        tx_send_bit(1'b0); check(data_out==1'b0, "TX alt bit0");
        tx_send_bit(1'b1); check(data_out==1'b1, "TX alt bit1 again");
        check(tx_stall==1'b0, "TX alt: no stall");

        // ========== TEST 2: TX stuffing after five equal bits ==========
        pulse_clear();
        tx_en = 1'b1; rx_en = 1'b0;

        tx_send_bit(1'b1); //1
        tx_send_bit(1'b1); //2
        tx_send_bit(1'b1); //3
        tx_send_bit(1'b1); //4
        tx_send_bit(1'b1); //5

        // On next bit-time, module should insert complement (0), stall asserted at condition
        data_in  = 1'b1;   // upstream would keep same; DUT should stuff instead
        bit_tick = 1'b1;
        @(posedge clk);
        check(data_out==1'b0, "TX stuff inserted complement after five 1s");
        check(tx_stall==1'b1, "TX stall asserted on stuff cycle");
        bit_tick = 1'b0;
        @(posedge clk);

        // Next cycle normal resumes
        tx_send_bit(1'b1);
        check(stuff_err==1'b0, "TX path no stuff_err");

        // ========== TEST 3: RX normal forwarding ==========
        pulse_clear();
        tx_en = 1'b0; rx_en = 1'b1;

        rx_sample_bit(1'b1); check(data_valid==1'b1 && data_out==1'b1, "RX normal bit1 valid");
        rx_sample_bit(1'b0); check(data_valid==1'b1 && data_out==1'b0, "RX normal bit0 valid");
        check(stuff_err==1'b0, "RX normal no stuff error");

        // ========== TEST 4: RX valid stuffed bit is dropped ==========
        pulse_clear();
        tx_en = 1'b0; rx_en = 1'b1;

        // five consecutive 1s (valid data bits)
        rx_sample_bit(1'b1);
        check(data_valid==1'b1 && data_out==1'b1, "RX run1");
        rx_sample_bit(1'b1);
        check(data_valid==1'b1, "RX run2");
        rx_sample_bit(1'b1);
        check(data_valid==1'b1, "RX run3");
        rx_sample_bit(1'b1);
        check(data_valid==1'b1, "RX run4");
        rx_sample_bit(1'b1);
        check(data_valid==1'b1, "RX run5");

        // stuffed complement bit (0) should be dropped
        rx_sample_bit(1'b0);
        check(data_valid==1'b0, "RX stuffed complement bit dropped");
        check(stuff_err==1'b0, "RX valid stuff bit no error");

        // next normal bit
        rx_sample_bit(1'b0);
        check(data_valid==1'b1 && data_out==1'b0, "RX resumes after dropped stuff bit");

        // ========== TEST 5: RX stuff error ==========
        pulse_clear();
        tx_en = 1'b0; rx_en = 1'b1;

        // five consecutive 0s
        rx_sample_bit(1'b0);
        rx_sample_bit(1'b0);
        rx_sample_bit(1'b0);
        rx_sample_bit(1'b0);
        rx_sample_bit(1'b0);

        // invalid: sixth is also 0 (should have been 1 stuffed bit)
        rx_sample_bit(1'b0);
        check(stuff_err==1'b1, "RX stuff error on non-complement after five same bits");

        // summary
        $display("--------------------------------------------------");
        $display("TB SUMMARY: PASS=%0d FAIL=%0d", pass_count, fail_count);
        $display("--------------------------------------------------");

        if (fail_count == 0)
            $display("TB_RESULT: SUCCESS");
        else
            $display("TB_RESULT: FAILED");

        #20;
        $finish;
    end

endmodule