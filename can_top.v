`timescale 1ns / 1ps

module can_top (
    input  wire        PCLK,
    input  wire        PRESETn,
    input  wire        PSEL,
    input  wire        PENABLE,
    input  wire        PWRITE,
    input  wire [7:0]  PADDR,
    input  wire [15:0] PWDATA,
    output wire [15:0] PRDATA,
    output wire        PREADY,
    output wire        PSLVERR,

    input  wire        can_rx,
    output wire        can_tx,
    output wire        irq
);

    wire        reg_write_en;
    wire        reg_read_en;
    wire [7:0]  reg_addr;
    wire [15:0] reg_wdata;
    wire [15:0] reg_rdata;

    wire        tx_req_cmd;
    wire        tx_abort_cmd;
    wire        rx_release_cmd;

    wire        tx_busy;
    wire        tx_done;
    wire        rx_ready_raw;
    wire        rx_ready_acc;
    wire        arb_lost;
    wire        bus_off;

    wire [7:0]  tec;
    wire [7:0]  rec;
    wire [4:0]  err_code;

    wire [15:0] ir_reg;

    wire [10:0] tx_id;
    wire [3:0]  tx_dlc;
    wire [15:0] tx_data0;
    wire [15:0] tx_data1;
    wire [15:0] tx_data2;
    wire [15:0] tx_data3;

    wire [15:0] btr_reg;
    wire [15:0] acr_reg;
    wire [15:0] amr_reg;
    wire [15:0] int_en_reg;
    wire        reset_mode;
    wire        loopback_mode;
    wire        listen_only_mode;

    wire [10:0] rx_id;
    wire [3:0]  rx_dlc;
    wire [15:0] rx_data0;
    wire [15:0] rx_data1;
    wire [15:0] rx_data2;
    wire [15:0] rx_data3;

    wire tq_tick;
    wire sample_tick;
    wire bit_tick;

    wire tx_stall;
    wire stuff_data_out;
    wire stuff_data_valid;
    wire stuff_err;

    wire tx_raw_bit;
    wire tx_crc_en;
    wire tx_crc_clear;
    wire tx_in_arb;
    wire tx_ack_check;

    wire [14:0] tx_crc;
    wire [14:0] rx_crc;

    wire rx_ack_bit;
    wire rx_crc_en;
    wire rx_crc_clear;
    wire rx_crc_err;
    wire rx_form_err;
    wire rx_active;

    wire rx_accepted;
    wire rx_filtered;

    wire can_rx_i = loopback_mode ? can_tx : can_rx;

    wire tx_path_en = tx_busy && !listen_only_mode && !bus_off;
    wire rx_path_en = !tx_path_en;

    wire tx_bus_bit = tx_path_en ? stuff_data_out : 1'b1;
    assign can_tx   = ((tx_bus_bit == 1'b0) || (rx_ack_bit == 1'b0)) ? 1'b0 : 1'b1;

    wire tx_abort_i = tx_abort_cmd | arb_lost | bus_off;
    wire ack_err    = tx_ack_check && can_rx_i;
    wire bit_err    = tx_busy && bit_tick && !tx_in_arb && (tx_bus_bit == 1'b1) && (can_rx_i == 1'b0);

    wire ir_clr = reg_write_en && (reg_addr == 8'h18) && reg_wdata[0];

    wire [63:0] tx_data = {tx_data0, tx_data1, tx_data2, tx_data3};

    can_apb_slave u_apb (
        .PCLK(PCLK),
        .PRESETn(PRESETn),
        .PSEL(PSEL),
        .PENABLE(PENABLE),
        .PWRITE(PWRITE),
        .PADDR(PADDR),
        .PWDATA(PWDATA),
        .PRDATA(PRDATA),
        .PREADY(PREADY),
        .PSLVERR(PSLVERR),
        .reg_write_en(reg_write_en),
        .reg_read_en(reg_read_en),
        .reg_addr(reg_addr),
        .reg_wdata(reg_wdata),
        .reg_rdata(reg_rdata),
        .tx_req(tx_req_cmd),
        .tx_abort(tx_abort_cmd),
        .rx_release(rx_release_cmd)
    );

    can_reg_file u_reg_file (
        .clk(PCLK),
        .rst_n(PRESETn),
        .reg_write_en(reg_write_en),
        .reg_read_en(reg_read_en),
        .reg_addr(reg_addr),
        .reg_wdata(reg_wdata),
        .reg_rdata(reg_rdata),
        .tx_busy(tx_busy),
        .tx_done(tx_done),
        .rx_ready(rx_ready_acc),
        .arb_lost(arb_lost),
        .bus_off(bus_off),
        .tec(tec),
        .rec(rec),
        .err_code(err_code),
        .ir_reg_in(ir_reg),
        .rx_id(rx_id),
        .rx_dlc(rx_dlc),
        .rx_data0(rx_data0),
        .rx_data1(rx_data1),
        .rx_data2(rx_data2),
        .rx_data3(rx_data3),
        .reset_mode(reset_mode),
        .loopback_mode(loopback_mode),
        .listen_only_mode(listen_only_mode),
        .tx_id(tx_id),
        .tx_dlc(tx_dlc),
        .tx_data0(tx_data0),
        .tx_data1(tx_data1),
        .tx_data2(tx_data2),
        .tx_data3(tx_data3),
        .btr_reg_out(btr_reg),
        .acr_reg_out(acr_reg),
        .amr_reg_out(amr_reg),
        .int_en_reg_out(int_en_reg)
    );

    can_bit_timing u_bit_timing (
        .clk(PCLK),
        .rst_n(PRESETn),
        .btr_reg(btr_reg),
        .can_rx(can_rx_i),
        .tq_tick(tq_tick),
        .sample_tick(sample_tick),
        .bit_tick(bit_tick)
    );

    tx_fsm u_tx_fsm (
        .clk(PCLK),
        .rst_n(PRESETn),
        .bit_tick(bit_tick),
        .tx_stall(tx_stall),
        .tx_req(tx_req_cmd),
        .tx_abort(tx_abort_i),
        .tx_id(tx_id),
        .tx_dlc(tx_dlc),
        .tx_data(tx_data),
        .crc_computed(tx_crc),
        .can_tx(tx_raw_bit),
        .tx_busy(tx_busy),
        .tx_done(tx_done),
        .crc_en(tx_crc_en),
        .crc_clear(tx_crc_clear),
        .ack_check(tx_ack_check),
        .in_arb(tx_in_arb)
    );

    bit_stuffing u_bit_stuffing (
        .clk(PCLK),
        .rst_n(PRESETn),
        .tx_en(tx_path_en),
        .rx_en(rx_path_en),
        .bit_tick(bit_tick),
        .sample_tick(sample_tick),
        .clear(tx_crc_clear | rx_crc_clear),
        .data_in(tx_path_en ? tx_raw_bit : can_rx_i),
        .data_out(stuff_data_out),
        .data_valid(stuff_data_valid),
        .stuff_err(stuff_err),
        .tx_stall(tx_stall)
    );

    rx_fsm u_rx_fsm (
        .clk(PCLK),
        .rst_n(PRESETn),
        .data_valid(stuff_data_valid),
        .data_in(stuff_data_out),
        .crc_rx(rx_crc),
        .rx_release(rx_release_cmd | rx_filtered),
        .ack_bit(rx_ack_bit),
        .crc_en(rx_crc_en),
        .crc_clear(rx_crc_clear),
        .rx_id(rx_id),
        .rx_dlc(rx_dlc),
        .rx_data0(rx_data0),
        .rx_data1(rx_data1),
        .rx_data2(rx_data2),
        .rx_data3(rx_data3),
        .rx_ready(rx_ready_raw),
        .crc_err(rx_crc_err),
        .form_err(rx_form_err),
        .rx_active(rx_active)
    );

    crc u_tx_crc (
        .clk(PCLK),
        .rst_n(PRESETn),
        .enable(tx_crc_en),
        .clear(tx_crc_clear),
        .data_in(tx_raw_bit),
        .crc_out(tx_crc)
    );

    crc u_rx_crc (
        .clk(PCLK),
        .rst_n(PRESETn),
        .enable(rx_crc_en && stuff_data_valid),
        .clear(rx_crc_clear),
        .data_in(stuff_data_out),
        .crc_out(rx_crc)
    );

    arbitration u_arbitration (
        .clk(PCLK),
        .rst_n(PRESETn),
        .bit_tick(bit_tick),
        .tx_active(tx_in_arb),
        .can_tx(tx_bus_bit),
        .can_rx(can_rx_i),
        .arb_lost(arb_lost)
    );

    acceptance_filter u_acceptance_filter (
        .clk(PCLK),
        .rst_n(PRESETn),
        .acr_reg(acr_reg),
        .amr_reg(amr_reg),
        .rx_id(rx_id),
        .rx_ready_in(rx_ready_raw),
        .rx_accepted(rx_accepted),
        .rx_filtered(rx_filtered)
    );

    assign rx_ready_acc = rx_accepted;

    error_detector u_error_detector (
        .clk(PCLK),
        .rst_n(PRESETn),
        .bit_err(bit_err),
        .stuff_err(stuff_err),
        .crc_err(rx_crc_err),
        .form_err(rx_form_err),
        .ack_err(ack_err),
        .arb_lost(arb_lost),
        .tx_done(tx_done),
        .rx_ready(rx_ready_acc),
        .tec(tec),
        .rec(rec),
        .err_code(err_code),
        .bus_off(bus_off),
        .err_passive(),
        .err_active()
    );

    interrupt u_interrupt (
        .clk(PCLK),
        .rst_n(PRESETn),
        .int_en_reg(int_en_reg),
        .tx_done(tx_done),
        .rx_ready(rx_ready_acc),
        .crc_err(rx_crc_err),
        .form_err(rx_form_err),
        .stuff_err(stuff_err),
        .arb_lost(arb_lost),
        .bus_off(bus_off),
        .ir_clr(ir_clr),
        .ir_reg(ir_reg),
        .irq(irq)
    );

endmodule
