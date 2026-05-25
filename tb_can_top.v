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

    reg [10:0] tx_state_seen;
    reg [255:0] tx_frame_bits;
    reg [15:0] rd_data;
    reg [14:0] tx_crc_snap;
    reg [14:0] tx_crc_bits_seen;
    reg tx_crc_snap_valid;
    integer tx_cap_len;
    integer tx_crc_bit_count;
    integer tx_stuff_cnt;
    integer eof_ones_cnt;
    integer errors;
    integer i;
    integer timeout;

    localparam TX_IDLE         = 4'd0;
    localparam TX_SOF          = 4'd1;
    localparam TX_ARB          = 4'd2;
    localparam TX_CONTROL      = 4'd3;
    localparam TX_DATA         = 4'd4;
    localparam TX_CRC          = 4'd5;
    localparam TX_CRC_DELIM    = 4'd6;
    localparam TX_ACK          = 4'd7;
    localparam TX_ACK_DELIM    = 4'd8;
    localparam TX_EOF          = 4'd9;
    localparam TX_INTERMISSION = 4'd10;

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

            if (dut.bit_tick && dut.u_tx_fsm.tx_busy && dut.tx_stall)
                tx_stuff_cnt <= tx_stuff_cnt + 1;

            if (dut.bit_tick && !dut.tx_stall) begin
                if (dut.u_tx_fsm.state <= TX_INTERMISSION)
                    tx_state_seen[dut.u_tx_fsm.state] <= 1'b1;

                if ((dut.u_tx_fsm.state != TX_IDLE) && (tx_cap_len < 256)) begin
                    tx_frame_bits[tx_cap_len] <= can_tx;
                    tx_cap_len <= tx_cap_len + 1;
                end

                if (dut.u_tx_fsm.state == TX_CRC) begin
                    if (!tx_crc_snap_valid) begin
                        tx_crc_snap       <= dut.u_tx_fsm.crc_computed;
                        tx_crc_snap_valid <= 1'b1;
                    end
                    if (tx_crc_bit_count < 15) begin
                        tx_crc_bits_seen[14 - tx_crc_bit_count] <= can_tx;
                        tx_crc_bit_count <= tx_crc_bit_count + 1;
                    end
                end

                if ((dut.u_tx_fsm.state == TX_EOF) && (can_tx == 1'b1))
                    eof_ones_cnt <= eof_ones_cnt + 1;
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

    task apb_read;
        input [7:0] addr;
        output [15:0] data;
        begin
            @(posedge PCLK);
            PSEL    <= 1'b1;
            PENABLE <= 1'b0;
            PWRITE  <= 1'b0;
            PADDR   <= addr;

            @(posedge PCLK);
            PENABLE <= 1'b1;

            @(posedge PCLK);
            data    = PRDATA;
            PSEL    <= 1'b0;
            PENABLE <= 1'b0;
            PADDR   <= 8'd0;
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
        tx_state_seen = 11'd0;
        tx_frame_bits = 256'd0;
        tx_cap_len = 0;
        tx_crc_snap = 15'd0;
        tx_crc_bits_seen = 15'd0;
        tx_crc_snap_valid = 1'b0;
        tx_crc_bit_count = 0;
        tx_stuff_cnt = 0;
        eof_ones_cnt = 0;
        errors = 0;
        rd_data = 16'd0;

        repeat (4) @(posedge PCLK);
        PRESETn = 1'b1;
        repeat (2) @(posedge PCLK);

        // Fast bit timing setup for simulation: BRP=0, TSEG1=2, TSEG2=1, SJW=1.
        apb_write(8'h04, 16'h2480);
        // Accept all IDs for replay receive check.
        apb_write(8'h06, 16'h0000);
        apb_write(8'h08, 16'h07FF);
        // Normal mode.
        apb_write(8'h00, 16'h0000);

        // TX frame setup: ID=0x7FF, DLC=2, DATA[1:0]=16'hF0F0.
        // ID=0x7FF creates a long run of dominant/recessive levels, so at least
        // one stuffing event is expected and checked in this test.
        apb_write(8'h0A, 16'h07FF);
        apb_write(8'h0C, 16'h0002);
        apb_write(8'h0E, 16'hF0F0);
        apb_write(8'h10, 16'h0000);
        apb_write(8'h12, 16'h0000);
        apb_write(8'h14, 16'h0000);

        $display("\n--- Start TX from top module (capture full frame) ---");
        apb_write(8'h01, 16'h0001); // tx_req

        timeout = 0;
        while ((dut.u_tx_fsm.tx_done !== 1'b1) && (timeout < 5000)) begin
            @(posedge PCLK);
            timeout = timeout + 1;
        end
        if (timeout >= 5000) begin
            $display("ERROR: TX did not complete");
            errors = errors + 1;
        end
        @(posedge PCLK);
        $display("--- TX complete ---\n");

        if (!tx_state_seen[TX_SOF]) begin
            $display("ERROR: SOF state not observed");
            errors = errors + 1;
        end
        if (!tx_state_seen[TX_ARB]) begin
            $display("ERROR: ARB state not observed");
            errors = errors + 1;
        end
        if (!tx_state_seen[TX_CONTROL]) begin
            $display("ERROR: CONTROL state not observed");
            errors = errors + 1;
        end
        if (!tx_state_seen[TX_DATA]) begin
            $display("ERROR: DATA state not observed");
            errors = errors + 1;
        end
        if (!tx_state_seen[TX_CRC]) begin
            $display("ERROR: CRC state not observed");
            errors = errors + 1;
        end
        if (!tx_state_seen[TX_CRC_DELIM]) begin
            $display("ERROR: CRC_DELIM state not observed");
            errors = errors + 1;
        end
        if (!tx_state_seen[TX_ACK]) begin
            $display("ERROR: ACK state not observed");
            errors = errors + 1;
        end
        if (!tx_state_seen[TX_ACK_DELIM]) begin
            $display("ERROR: ACK_DELIM state not observed");
            errors = errors + 1;
        end
        if (!tx_state_seen[TX_EOF]) begin
            $display("ERROR: EOF state not observed");
            errors = errors + 1;
        end
        if (!tx_state_seen[TX_INTERMISSION]) begin
            $display("ERROR: INTERMISSION state not observed");
            errors = errors + 1;
        end

        if (tx_stuff_cnt <= 0) begin
            $display("ERROR: bit stuffing activity was not observed");
            errors = errors + 1;
        end
        if (tx_crc_bit_count != 15) begin
            $display("ERROR: CRC length mismatch, saw %0d bits", tx_crc_bit_count);
            errors = errors + 1;
        end else if (tx_crc_bits_seen !== tx_crc_snap) begin
            $display("ERROR: CRC field mismatch. expected=%0h saw=%0h", tx_crc_snap, tx_crc_bits_seen);
            errors = errors + 1;
        end
        if (eof_ones_cnt != 7) begin
            $display("ERROR: EOF recessive bit count mismatch, saw %0d expected 7", eof_ones_cnt);
            errors = errors + 1;
        end
        if (tx_cap_len <= 0) begin
            $display("ERROR: No captured TX frame bits for replay");
            errors = errors + 1;
        end

        $display("--- Switch to listen-only and replay captured TX frame into RX ---");
        apb_write(8'h00, 16'h0004); // listen_only_mode=1
        apb_write(8'h01, 16'h0004); // rx_release

        for (i = 0; i < tx_cap_len; i = i + 1)
            rx_send_bit(tx_frame_bits[i]);

        force_rx = 1'b0;

        timeout = 0;
        while ((dut.u_rx_fsm.rx_ready !== 1'b1) && (timeout < 8000)) begin
            @(posedge PCLK);
            timeout = timeout + 1;
        end
        if (timeout >= 8000) begin
            $display("ERROR: RX did not assert rx_ready after replay");
            errors = errors + 1;
        end

        apb_read(8'h20, rd_data);
        if (rd_data[10:0] !== 11'h7FF) begin
            $display("ERROR: RX ID mismatch expected=0x7FF got=0x%0h", rd_data[10:0]);
            errors = errors + 1;
        end
        apb_read(8'h22, rd_data);
        if (rd_data[3:0] !== 4'd2) begin
            $display("ERROR: RX DLC mismatch expected=2 got=%0d", rd_data[3:0]);
            errors = errors + 1;
        end
        apb_read(8'h24, rd_data);
        if (rd_data !== 16'hF0F0) begin
            $display("ERROR: RX DATA0 mismatch expected=0xF0F0 got=0x%0h", rd_data);
            errors = errors + 1;
        end
        apb_read(8'h26, rd_data);
        if (rd_data !== 16'h0000) begin
            $display("ERROR: RX DATA1 mismatch expected=0x0000 got=0x%0h", rd_data);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("\nTB RESULT: PASS (full frame phase checks + listen-only RX replay match)\n");
        else
            $display("\nTB RESULT: FAIL with %0d error(s)\n", errors);

        #30;
        $finish;
    end

endmodule
