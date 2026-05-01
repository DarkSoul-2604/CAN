`timescale 1ns / 1ps

module tb_can_apb_slave;

   
    reg         PCLK;
    reg         PRESETn;
    reg         PSEL;
    reg         PENABLE;
    reg         PWRITE;
    reg  [7:0]  PADDR;
    reg  [15:0] PWDATA;
    reg  [15:0] reg_rdata;

 
    wire [15:0] PRDATA;
    wire        PREADY;
    wire        PSLVERR;

    wire        reg_write_en;
    wire        reg_read_en;
    wire [7:0]  reg_addr;
    wire [15:0] reg_wdata;

    wire        tx_req;
    wire        tx_abort;
    wire        rx_release;

    // Instantiate DUT
    can_apb_slave dut (
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

        .tx_req(tx_req),
        .tx_abort(tx_abort),
        .rx_release(rx_release)
    );

//100mhz
    initial begin
        PCLK = 1'b0;
        forever #5 PCLK = ~PCLK;
    end

    // APB write task 
    task apb_write;
        input [7:0]  addr;
        input [15:0] data;
        begin
            @(posedge PCLK);
            PSEL    <= 1'b1;
            PENABLE <= 1'b0; // setup
            PWRITE  <= 1'b1;
            PADDR   <= addr;
            PWDATA  <= data;

            @(posedge PCLK);
            PENABLE <= 1'b1; // access

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
        begin
            @(posedge PCLK);
            PSEL    <= 1'b1;
            PENABLE <= 1'b0; // setup
            PWRITE  <= 1'b0;
            PADDR   <= addr;

            @(posedge PCLK);
            PENABLE <= 1'b1; // access

            @(posedge PCLK);
            PSEL    <= 1'b0;
            PENABLE <= 1'b0;
            PADDR   <= 8'd0;
        end
    endtask

    initial begin
        // Init
        PRESETn   = 1'b0;
        PSEL      = 1'b0;
        PENABLE   = 1'b0;
        PWRITE    = 1'b0;
        PADDR     = 8'd0;
        PWDATA    = 16'd0;
        reg_rdata = 16'hA5A5;

        // Reset
        #25;
        PRESETn = 1'b1;
        #20;

        $display("1.Normal Write:");
        apb_write(8'h02, 16'h1234);
        #1;
        $display("PREADY=%0d PSLVERR=%0d reg_write_en=%0d reg_addr=0x%0h reg_wdata=0x%0h",
                 PREADY, PSLVERR, reg_write_en, reg_addr, reg_wdata);

        $display("2.Normal read:");
        reg_rdata = 16'hBEEF;
        apb_read(8'h04);
        #1;
        $display("PREADY=%0d PSLVERR=%0d reg_read_en=%0d reg_addr=0x%0h PRDATA=0x%0h",
                 PREADY, PSLVERR, reg_read_en, reg_addr, PRDATA);

       
        $display("3.invalid addr: ");
        apb_write(8'h2B, 16'h9999); // > 0x2A (invalid)
        #1;
        $display("PREADY=%0d PSLVERR=%0d reg_write_en=%0d",
                 PREADY, PSLVERR, reg_write_en);

        #30;
        $display("\nDone.");
        $finish;
    end

endmodule