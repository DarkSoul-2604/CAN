`timescale 1ns / 1ps

module tb_can_top;

    reg         PCLK;
    reg         PRESETn;
    reg         PSEL;
    reg         PENABLE;
    reg         PWRITE;
    reg  [7:0]  PADDR;
    reg  [15:0] PWDATA;
    reg         can_rx;

    wire [15:0] PRDATA;
    wire        PREADY;
    wire        PSLVERR;
    wire        can_tx;
    wire        irq;

    reg force_rx;
    reg forced_bit;
    reg [3:0] last_tx_state;
    reg [3:0] last_rx_state;

    can_top dut (
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
        .can_rx(can_rx),
        .can_tx(can_tx),
        .irq(irq)
    );

    initial begin
        PCLK = 1'b0;
        forever #5 PCLK = ~PCLK;
    end

    // Keep the bus coherent during TX (echo), drive dominant ACK in ACK slot.
    // During RX injection phase, force_rx overrides this behavior.
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)
            can_rx <= 1'b1;
        else if (force_rx)
            can_rx <= forced_bit;
        else if (dut.u_tx_fsm.ack_check)
            can_rx <= 1'b0;
        else
            can_rx <= can_tx;
    end

    always @(posedge PCLK) begin
        if (PRESETn) begin
            if ((dut.u_tx_fsm.state != last_tx_state) ||
                (dut.u_rx_fsm.state != last_rx_state) ||
                dut.u_tx_fsm.tx_done || dut.u_rx_fsm.rx_ready) begin
                $display("t=%0t TX_FSM=%0d RX_FSM=%0d tx_busy=%0b tx_done=%0b rx_active=%0b rx_ready=%0b can_tx=%0b can_rx=%0b",
                         $time,
                         dut.u_tx_fsm.state,
                         dut.u_rx_fsm.state,
                         dut.u_tx_fsm.tx_busy,
                         dut.u_tx_fsm.tx_done,
                         dut.u_rx_fsm.rx_active,
                         dut.u_rx_fsm.rx_ready,
                         can_tx,
                         can_rx);
            end
            last_tx_state <= dut.u_tx_fsm.state;
            last_rx_state <= dut.u_rx_fsm.state;
        end
    end

    task apb_write;
        input [7:0]  addr;
        input [15:0] data;
        begin
            @(posedge PCLK);
            PSEL    <= 1'b1;
            PENABLE <= 1'b0;
            PWRITE  <= 1'b1;
            PADDR   <= addr;
            PWDATA  <= data;

            @(posedge PCLK);
            PENABLE <= 1'b1;

            @(posedge PCLK);
            PSEL    <= 1'b0;
            PENABLE <= 1'b0;
            PWRITE  <= 1'b0;
            PADDR   <= 8'd0;
            PWDATA  <= 16'd0;
        end
    endtask

    task rx_send_bit;
        input b;
        begin
            force_rx   = 1'b1;
            forced_bit = b;
            @(posedge PCLK);
            while (dut.sample_tick !== 1'b1)
                @(posedge PCLK);
        end
    endtask

    initial begin
        PRESETn    = 1'b0;
        PSEL       = 1'b0;
        PENABLE    = 1'b0;
        PWRITE     = 1'b0;
        PADDR      = 8'd0;
        PWDATA     = 16'd0;
        force_rx   = 1'b0;
        forced_bit = 1'b1;
        last_tx_state = 4'hF;
        last_rx_state = 4'hF;

        repeat (4) @(posedge PCLK);
        PRESETn = 1'b1;
        repeat (2) @(posedge PCLK);

        // Fast bit timing setup for simulation: BRP=0, TSEG1=2, TSEG2=1, SJW=1
        apb_write(8'h04, 16'h2480);

        // TX frame setup: ID=0x123, DLC=1, DATA[0]=0xA5
        apb_write(8'h0A, 16'h0123);
        apb_write(8'h0C, 16'h0001);
        apb_write(8'h0E, 16'hA500);
        apb_write(8'h10, 16'h0000);
        apb_write(8'h12, 16'h0000);
        apb_write(8'h14, 16'h0000);

        $display("\n--- Start TX from top module ---");
        apb_write(8'h01, 16'h0001); // tx_req

        wait (dut.u_tx_fsm.tx_done == 1'b1);
        @(posedge PCLK);
        $display("--- TX complete ---\n");

        $display("--- Start RX stimulus for RX FSM display ---");
        // SOF
        rx_send_bit(1'b0);
        // ID[10:0] = 10101010101
        rx_send_bit(1'b1); rx_send_bit(1'b0); rx_send_bit(1'b1); rx_send_bit(1'b0); rx_send_bit(1'b1);
        rx_send_bit(1'b0); rx_send_bit(1'b1); rx_send_bit(1'b0); rx_send_bit(1'b1); rx_send_bit(1'b0);
        rx_send_bit(1'b1);
        // RTR
        rx_send_bit(1'b0);
        // IDE, r0, DLC=0001
        rx_send_bit(1'b0); rx_send_bit(1'b0); rx_send_bit(1'b0); rx_send_bit(1'b0); rx_send_bit(1'b0); rx_send_bit(1'b1);
        // DATA byte = 0xA5
        rx_send_bit(1'b1); rx_send_bit(1'b0); rx_send_bit(1'b1); rx_send_bit(1'b0);
        rx_send_bit(1'b0); rx_send_bit(1'b1); rx_send_bit(1'b0); rx_send_bit(1'b1);
        // CRC (arbitrary demo bits for FSM progression display)
        rx_send_bit(1'b0); rx_send_bit(1'b0); rx_send_bit(1'b0); rx_send_bit(1'b0); rx_send_bit(1'b0);
        rx_send_bit(1'b0); rx_send_bit(1'b0); rx_send_bit(1'b0); rx_send_bit(1'b0); rx_send_bit(1'b0);
        rx_send_bit(1'b0); rx_send_bit(1'b0); rx_send_bit(1'b0); rx_send_bit(1'b0); rx_send_bit(1'b0);
        // CRC delimiter, ACK slot, ACK delimiter
        rx_send_bit(1'b1); rx_send_bit(1'b1); rx_send_bit(1'b1);
        // EOF (7) + Intermission (3)
        rx_send_bit(1'b1); rx_send_bit(1'b1); rx_send_bit(1'b1); rx_send_bit(1'b1); rx_send_bit(1'b1); rx_send_bit(1'b1); rx_send_bit(1'b1);
        rx_send_bit(1'b1); rx_send_bit(1'b1); rx_send_bit(1'b1);

        force_rx = 1'b0;
        repeat (20) @(posedge PCLK);

        $display("--- RX stimulus done ---");
        $display("Final: tx_done=%0b rx_ready=%0b crc_err=%0b form_err=%0b irq=%0b",
                 dut.u_tx_fsm.tx_done,
                 dut.u_rx_fsm.rx_ready,
                 dut.u_rx_fsm.crc_err,
                 dut.u_rx_fsm.form_err,
                 irq);

        #20;
        $finish;
    end

endmodule
