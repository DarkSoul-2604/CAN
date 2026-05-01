`timescale 1ns/1ps

module tb_interrupt;

  reg         clk;
  reg         rst_n;
  reg  [15:0] int_en_reg;

  reg         tx_done;
  reg         rx_ready;
  reg         crc_err;
  reg         form_err;
  reg         stuff_err;
  reg         arb_lost;
  reg         bus_off;

  reg         ir_clr;

  wire [15:0] ir_reg;
  wire        irq;

  interrupt dut (
    .clk(clk),
    .rst_n(rst_n),
    .int_en_reg(int_en_reg),
    .tx_done(tx_done),
    .rx_ready(rx_ready),
    .crc_err(crc_err),
    .form_err(form_err),
    .stuff_err(stuff_err),
    .arb_lost(arb_lost),
    .bus_off(bus_off),
    .ir_clr(ir_clr),
    .ir_reg(ir_reg),
    .irq(irq)
  );

  // clock
  initial clk = 0;
  always #5 clk = ~clk;

  // pulse helpers (drive real signals)
  task pulse_tx_done;
    begin tx_done = 1; @(posedge clk); tx_done = 0; end
  endtask
  task pulse_rx_ready;
    begin rx_ready = 1; @(posedge clk); rx_ready = 0; end
  endtask
  task pulse_crc_err;
    begin crc_err = 1; @(posedge clk); crc_err = 0; end
  endtask
  task pulse_form_err;
    begin form_err = 1; @(posedge clk); form_err = 0; end
  endtask
  task pulse_stuff_err;
    begin stuff_err = 1; @(posedge clk); stuff_err = 0; end
  endtask
  task pulse_arb_lost;
    begin arb_lost = 1; @(posedge clk); arb_lost = 0; end
  endtask
  task pulse_bus_off;
    begin bus_off = 1; @(posedge clk); bus_off = 0; end
  endtask

  initial begin
    // init
    rst_n      = 0;
    int_en_reg = 16'd0;
    tx_done    = 0;
    rx_ready   = 0;
    crc_err    = 0;
    form_err   = 0;
    stuff_err  = 0;
    arb_lost   = 0;
    bus_off    = 0;
    ir_clr     = 0;

    // reset
    repeat (2) @(posedge clk);
    rst_n = 1;

    int_en_reg[4:0] = 5'b11111;

    // TX done
    pulse_tx_done();
    @(posedge clk); // allow ir_reg update
    if (!ir_reg[0]) $display("ERROR: ir_reg[0] not set");
    @(posedge clk); // allow irq update
    if (!irq)       $display("ERROR: irq not asserted on tx_done");

    // RX ready
    pulse_rx_ready();
    @(posedge clk);
    if (!ir_reg[1]) $display("ERROR: ir_reg[1] not set");

    // any_err (crc_err)
    pulse_crc_err();
    @(posedge clk);
    if (!ir_reg[2]) $display("ERROR: ir_reg[2] not set by crc_err");

    // any_err (form_err)
    pulse_form_err();
    @(posedge clk);
    if (!ir_reg[2]) $display("ERROR: ir_reg[2] not set by form_err");

    // any_err (stuff_err)
    pulse_stuff_err();
    @(posedge clk);
    if (!ir_reg[2]) $display("ERROR: ir_reg[2] not set by stuff_err");

    // arbitration lost
    pulse_arb_lost();
    @(posedge clk);
    if (!ir_reg[3]) $display("ERROR: ir_reg[3] not set");

    // bus off
    pulse_bus_off();
    @(posedge clk);
    if (!ir_reg[4]) $display("ERROR: ir_reg[4] not set");

    // clear
    ir_clr = 1;
    @(posedge clk);
    ir_clr = 0;
    @(posedge clk);
    if (ir_reg != 16'd0) $display("ERROR: ir_reg not cleared");
    if (irq)             $display("ERROR: irq not cleared");

    // mask test
    int_en_reg[4:0] = 5'b00000;
    pulse_tx_done();
    @(posedge clk);
    if (irq) $display("ERROR: irq asserted with mask disabled");

    $display("TB finished");
    #20;
    $finish;
  end

endmodule