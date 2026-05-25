module can_reg_file (

    input  wire        clk,
    input  wire        rst_n,

    //---------------- APB
    input  wire        reg_write_en,
    input  wire        reg_read_en,
    input  wire [7:0]  reg_addr,
    input  wire [15:0] reg_wdata,
    output reg  [15:0] reg_rdata,

    //---------------- STATUS
    input wire tx_busy,
    input wire tx_done,
    input wire rx_ready,
    input wire arb_lost,
    input wire bus_off,

    //---------------- ERROR
    input wire [7:0] tec,
    input wire [7:0] rec,
    input wire [4:0] err_code,

    //-----------------INTERRUPT
    input wire [15:0]  ir_reg_in,

    //---------------- RX
    input wire [10:0] rx_id,
    input wire [3:0]  rx_dlc,
    input wire [15:0] rx_data0,
    input wire [15:0] rx_data1,
    input wire [15:0] rx_data2,
    input wire [15:0] rx_data3,

    //---------------- MODE
    output wire reset_mode,
    output wire loopback_mode,
    output wire listen_only_mode,

    //---------------- Tx
    output wire [10:0] tx_id,
    output wire [3:0]  tx_dlc,
    output wire [15:0] tx_data0,
    output wire [15:0] tx_data1,
    output wire [15:0] tx_data2,
    output wire [15:0] tx_data3,

    //-----------configurations
    output wire [15:0] btr_reg_out,
    output wire [15:0] acr_reg_out,
    output wire [15:0] amr_reg_out,
    output wire [15:0] int_en_reg_out

);

//---------------- REG
reg [15:0] mode_reg;        // 0x00
reg [15:0] int_en_reg;      // 0x02
reg [15:0] btr_reg;         // 0x04
reg [15:0] acr_reg;         // 0x06
reg [15:0] amr_reg;         // 0x08

reg [15:0] tx_id_reg;       // 0x0A
reg [15:0] tx_dlc_reg;      // 0x0C
reg [15:0] tx_data0_reg;    // 0x0E
reg [15:0] tx_data1_reg;    // 0x10
reg [15:0] tx_data2_reg;    // 0x12
reg [15:0] tx_data3_reg;    // 0x14

reg [15:0] status_reg;      // 0x16
reg [15:0] tec_reg;         // 0x1A
reg [15:0] rec_reg;         // 0x1C
reg [15:0] err_reg;         // 0x1E

// Latched RX snapshot for atomic multi-register reads
reg [10:0] rx_id_reg;       // 0x20
reg [3:0]  rx_dlc_reg;      // 0x22
reg [15:0] rx_data0_reg;    // 0x24
reg [15:0] rx_data1_reg;    // 0x26
reg [15:0] rx_data2_reg;    // 0x28
reg [15:0] rx_data3_reg;    // 0x2A

//------------ Write (from CPU)
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mode_reg    <= 16'h0001;
        int_en_reg  <= 16'h0000;
        btr_reg     <= 16'h0000;
        acr_reg     <= 16'h0000;
        amr_reg     <= 16'h0000;

        tx_id_reg   <= 16'h0000;
        tx_dlc_reg  <= 16'h0000;
        tx_data0_reg<= 16'h0000;
        tx_data1_reg<= 16'h0000;
        tx_data2_reg<= 16'h0000;
        tx_data3_reg<= 16'h0000;
    end else if (reg_write_en) begin
        case (reg_addr)
            8'h00: mode_reg     <= reg_wdata;
            8'h02: int_en_reg   <= reg_wdata;
            8'h04: btr_reg      <= reg_wdata;
            8'h06: acr_reg      <= reg_wdata;
            8'h08: amr_reg      <= reg_wdata;
            8'h0A: tx_id_reg    <= reg_wdata;
            8'h0C: tx_dlc_reg   <= reg_wdata;
            8'h0E: tx_data0_reg <= reg_wdata;
            8'h10: tx_data1_reg <= reg_wdata;
            8'h12: tx_data2_reg <= reg_wdata;
            8'h14: tx_data3_reg <= reg_wdata;
            default: ;
        endcase
    end
end

//-------------- Status/RX capture (from CAN core)
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        status_reg  <= 16'h0000;
        tec_reg     <= 16'h0000;
        rec_reg     <= 16'h0000;
        err_reg     <= 16'h0000;

        rx_id_reg   <= 11'd0;
        rx_dlc_reg  <= 4'd0;
        rx_data0_reg<= 16'd0;
        rx_data1_reg<= 16'd0;
        rx_data2_reg<= 16'd0;
        rx_data3_reg<= 16'd0;
    end else begin
        status_reg[0] <= tx_busy;
        status_reg[1] <= tx_done;
        status_reg[2] <= rx_ready;
        status_reg[3] <= arb_lost;
        status_reg[4] <= bus_off;

        tec_reg       <= {8'd0, tec};
        rec_reg       <= {8'd0, rec};
        err_reg[4:0]  <= err_code;

        if (rx_ready) begin
            rx_id_reg    <= rx_id;
            rx_dlc_reg   <= rx_dlc;
            rx_data0_reg <= rx_data0;
            rx_data1_reg <= rx_data1;
            rx_data2_reg <= rx_data2;
            rx_data3_reg <= rx_data3;
        end
    end
end

//----------- Read mux (combinational for APB read atomicity)
always @(*) begin
    reg_rdata = 16'h0000;
    if (reg_read_en) begin
        case (reg_addr)
            8'h00: reg_rdata = mode_reg;
            8'h02: reg_rdata = int_en_reg;
            8'h04: reg_rdata = btr_reg;
            8'h06: reg_rdata = acr_reg;
            8'h08: reg_rdata = amr_reg;
            8'h0A: reg_rdata = tx_id_reg;
            8'h0C: reg_rdata = tx_dlc_reg;
            8'h0E: reg_rdata = tx_data0_reg;
            8'h10: reg_rdata = tx_data1_reg;
            8'h12: reg_rdata = tx_data2_reg;
            8'h14: reg_rdata = tx_data3_reg;
            8'h16: reg_rdata = status_reg;
            8'h18: reg_rdata = ir_reg_in;
            8'h1A: reg_rdata = tec_reg;
            8'h1C: reg_rdata = rec_reg;
            8'h1E: reg_rdata = err_reg;
            8'h20: reg_rdata = {5'd0, rx_id_reg};
            8'h22: reg_rdata = {12'd0, rx_dlc_reg};
            8'h24: reg_rdata = rx_data0_reg;
            8'h26: reg_rdata = rx_data1_reg;
            8'h28: reg_rdata = rx_data2_reg;
            8'h2A: reg_rdata = rx_data3_reg;
            default: reg_rdata = 16'h0000;
        endcase
    end
end

//--------------- output
assign reset_mode       = mode_reg[0];
assign loopback_mode    = mode_reg[1];
assign listen_only_mode = mode_reg[2];

assign tx_id    = tx_id_reg[10:0];
assign tx_dlc   = tx_dlc_reg[3:0];
assign tx_data0 = tx_data0_reg;
assign tx_data1 = tx_data1_reg;
assign tx_data2 = tx_data2_reg;
assign tx_data3 = tx_data3_reg;

assign btr_reg_out    = btr_reg;
assign acr_reg_out    = acr_reg;
assign amr_reg_out    = amr_reg;
assign int_en_reg_out = int_en_reg;

endmodule
