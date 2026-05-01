`timescale 1ns/1ps

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

  bit_stuffing dut (
    .clk(clk),
    .rst_n(rst_n),
    .tx_en(tx_en),
    .rx_en(rx_en),
    .bit_tick(bit_tick),
    .sample_tick(sample_tick),
    .clear(clear),
    .data_in(data_in),
    .data_out(data_out),
    .data_valid(data_valid),
    .stuff_err(stuff_err),
    .tx_stall(tx_stall)
  );

  // clock
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // tick helpers
  task tick_bit;
    begin
      bit_tick = 1'b1;
      @(posedge clk);
      bit_tick = 1'b0;
      @(posedge clk);
    end
  endtask

  task tick_sample;
    begin
      sample_tick = 1'b1;
      @(posedge clk);
      sample_tick = 1'b0;
      @(posedge clk);
    end
  endtask

  task tx_send;
    input b;
    begin
      data_in = b;
      tick_bit();
    end
  endtask

  task rx_send;
    input b;
    begin
      data_in = b;
      tick_sample();
    end
  endtask

  initial begin
    // init
    rst_n = 0;
    tx_en = 0;
    rx_en = 0;
    bit_tick = 0;
    sample_tick = 0;
    clear = 0;
    data_in = 1'b1;

    // reset
    repeat (2) @(posedge clk);
    rst_n = 1;

    // -------------------------
    // TX stuffing test
    // -------------------------
    $display("TX stuffing test");
    clear = 1; @(posedge clk); clear = 0;
    tx_en = 1; rx_en = 0;

    tx_send(1);
    tx_send(1);
    tx_send(1);
    tx_send(1);
    tx_send(1);
    tx_send(1); // should stuff here

    tx_en = 0;

    // -------------------------
    // RX destuffing test
    // sequence: 11111 0 1 0
    // -------------------------
    $display("RX destuffing test");
    clear = 1; @(posedge clk); clear = 0;
    rx_en = 1; tx_en = 0;

    rx_send(1);
    rx_send(1);
    rx_send(1);
    rx_send(1);
    rx_send(1);
    rx_send(0); // stuffed bit (should be dropped)
    rx_send(1);
    rx_send(0);

    // -------------------------
    // RX error test
    // 6 identical bits
    // -------------------------
    $display("RX error test");
    clear = 1; @(posedge clk); clear = 0;

    rx_send(0);
    rx_send(0);
    rx_send(0);
    rx_send(0);
    rx_send(0);
    rx_send(0); // should raise stuff_err

    rx_en = 0;

    #20;
    $finish;
  end

endmodule