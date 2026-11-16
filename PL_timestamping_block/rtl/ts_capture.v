`timescale 1ns / 1ps

module ts_capture #(
    parameter [43:0] CNT_INIT = 44'd0
) (
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF m_axis, ASSOCIATED_RESET rstn" *)
    input  wire        clk,
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire        rstn,
    input  wire [3:0]  gpio_apu,
    input  wire [3:0]  gpio_r5,
    output wire [31:0] cnt_lo,
    output wire [31:0] m_axis_tdata,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire        m_axis_tlast
);

    reg [43:0] cnt;
    reg [7:0]  in_q;
    reg [7:0]  in_prev;
    reg        ovf;
    reg        beat;

    wire [7:0]  ch_level = in_q;
    wire [7:0]  ch_change = in_q ^ in_prev;
    wire        event_hit = |ch_change;
    wire        fifo_full;
    wire        fifo_empty;
    wire        wr_rst_busy;
    wire        rd_rst_busy;
    wire        blocked = fifo_full | wr_rst_busy;
    wire        wr_en = event_hit & ~blocked;
    wire [63:0] din = {ovf, 3'b000, ch_change, ch_level, cnt};
    wire [63:0] dout;
    wire        rd_en = beat & m_axis_tready;

    assign cnt_lo = cnt[31:0];

    always @(posedge clk) begin
        if (!rstn) begin
            cnt     <= CNT_INIT;
            in_q    <= 8'd0;
            in_prev <= 8'd0;
            ovf     <= 1'b0;
        end else begin
            cnt     <= cnt + 44'd1;
            in_q    <= {gpio_r5, gpio_apu};
            in_prev <= in_q;
            // Sticky until an event carrying the flag is written.
            if (event_hit && blocked)
                ovf <= 1'b1;
            else if (wr_en)
                ovf <= 1'b0;
        end
    end

    xpm_fifo_sync #(
        .FIFO_MEMORY_TYPE    ("distributed"),
        .FIFO_WRITE_DEPTH    (16),
        .WRITE_DATA_WIDTH    (64),
        .READ_DATA_WIDTH     (64),
        .READ_MODE           ("fwft"),
        .FIFO_READ_LATENCY   (0),
        .USE_ADV_FEATURES    ("0000"),
        .DOUT_RESET_VALUE    ("0"),
        .ECC_MODE            ("no_ecc"),
        .FULL_RESET_VALUE    (1),
        .WAKEUP_TIME         (0)
    ) u_evfifo (
        .wr_clk        (clk),
        .rst           (~rstn),
        .din           (din),
        .wr_en         (wr_en),
        .full          (fifo_full),
        .wr_rst_busy   (wr_rst_busy),
        .dout          (dout),
        .rd_en         (rd_en),
        .empty         (fifo_empty),
        .rd_rst_busy   (rd_rst_busy),
        .sleep         (1'b0),
        .injectsbiterr (1'b0),
        .injectdbiterr (1'b0),
        .prog_full     (),
        .wr_data_count (),
        .overflow      (),
        .wr_ack        (),
        .almost_full   (),
        .prog_empty    (),
        .rd_data_count (),
        .underflow     (),
        .data_valid    (),
        .almost_empty  (),
        .sbiterr       (),
        .dbiterr       ()
    );

    // beat 0 sends ts[31:0], beat 1 sends the upper word with tlast.
    always @(posedge clk) begin
        if (!rstn)
            beat <= 1'b0;
        else if (m_axis_tvalid && m_axis_tready)
            beat <= ~beat;
    end

    assign m_axis_tvalid = ~fifo_empty & ~rd_rst_busy;
    assign m_axis_tdata  = beat ? dout[63:32] : dout[31:0];
    assign m_axis_tlast  = beat;

endmodule
