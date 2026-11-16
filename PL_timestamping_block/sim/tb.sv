`timescale 1ns / 1ps

module axis_mon (
    input  logic        clk,
    input  logic        rstn,
    input  logic [31:0] tdata,
    input  logic        tvalid,
    input  logic        tready,
    input  logic        tlast
);
    logic [63:0] q[$];
    logic [31:0] lo;
    logic        have_lo = 0;
    logic        stall = 0;
    logic [31:0] stall_data;
    logic        stall_last;
    int          errors = 0;

    always @(posedge clk) begin
        if (rstn) begin
            // AXI-Stream rule: once valid, hold data until accepted.
            if (stall && !(tvalid && tdata == stall_data && tlast == stall_last)) begin
                $error("%m: beat changed while stalled");
                errors++;
            end
            stall      <= tvalid && !tready;
            stall_data <= tdata;
            stall_last <= tlast;

            if (tvalid && tready) begin
                if (!have_lo) begin
                    if (tlast) begin
                        $error("%m: tlast on word 0");
                        errors++;
                    end
                    lo      <= tdata;
                    have_lo <= 1;
                end else begin
                    if (!tlast) begin
                        $error("%m: missing tlast on word 1");
                        errors++;
                    end
                    q.push_back({tdata, lo});
                    have_lo <= 0;
                end
            end
        end
    end
endmodule

module tb_capture_ts;

    localparam [43:0] WRAP_INIT = 44'hFFF_FFFF_FF00;

    logic        clk = 0;
    logic        rstn = 0;
    logic [3:0]  apu = 0, r5 = 0;
    logic [3:0]  apu_w = 0;
    logic        tready = 1;
    logic [31:0] cnt_lo, cnt_lo_w;
    logic [31:0] tdata, tdata_w;
    logic        tvalid, tlast, tvalid_w, tlast_w;
    int          errors = 0;

    always #5 clk = ~clk;

    ts_capture dut (
        .clk(clk), .rstn(rstn), .gpio_apu(apu), .gpio_r5(r5), .cnt_lo(cnt_lo),
        .m_axis_tdata(tdata), .m_axis_tvalid(tvalid),
        .m_axis_tready(tready), .m_axis_tlast(tlast)
    );

    ts_capture #(.CNT_INIT(WRAP_INIT)) dut_w (
        .clk(clk), .rstn(rstn), .gpio_apu(apu_w), .gpio_r5(4'd0), .cnt_lo(cnt_lo_w),
        .m_axis_tdata(tdata_w), .m_axis_tvalid(tvalid_w),
        .m_axis_tready(1'b1), .m_axis_tlast(tlast_w)
    );

    axis_mon mon   (.clk(clk), .rstn(rstn), .tdata(tdata),   .tvalid(tvalid),   .tready(tready), .tlast(tlast));
    axis_mon mon_w (.clk(clk), .rstn(rstn), .tdata(tdata_w), .tvalid(tvalid_w), .tready(1'b1),   .tlast(tlast_w));

    function automatic logic        ev_ovf      (logic [63:0] e); return e[63];    endfunction
    function automatic logic [7:0]  ev_ch_change(logic [63:0] e); return e[59:52]; endfunction
    function automatic logic [7:0]  ev_ch_level (logic [63:0] e); return e[51:44]; endfunction
    function automatic logic [43:0] ev_ts       (logic [63:0] e); return e[43:0];  endfunction

    // An input changed at a negedge with cnt == c is timestamped c + 1.
    task automatic check_ev(string name, logic [63:0] e, logic ovf,
                            logic [7:0] ch_change, logic [7:0] ch_level, logic [43:0] ts);
        if (ev_ovf(e) !== ovf || ev_ch_change(e) !== ch_change || ev_ch_level(e) !== ch_level || ev_ts(e) !== ts) begin
            $error("%s: got ovf=%0b ch_change=%02h ch_level=%02h ts=%011h, want ovf=%0b ch_change=%02h ch_level=%02h ts=%011h",
                   name, ev_ovf(e), ev_ch_change(e), ev_ch_level(e), ev_ts(e), ovf, ch_change, ch_level, ts);
            errors++;
        end
    endtask

    task automatic expect_count(string name, int n);
        if (mon.q.size() != n) begin
            $error("%s: got %0d events, want %0d", name, mon.q.size(), n);
            errors++;
        end
    endtask

    task automatic drain();
        repeat (100) @(posedge clk);
    endtask

    logic [43:0] c;
    int          k;
    logic [43:0] cw;
    logic        wrap_done = 0;

    initial begin
        repeat (20) @(posedge clk);
        rstn = 1;
        repeat (20) @(posedge clk);

        // single edge
        @(negedge clk); c = cnt_lo; apu[0] = 1;
        drain();
        expect_count("single", 1);
        check_ev("single", mon.q.pop_front(), 0, 8'h01, 8'h01, c + 1);

        // same-cycle edges on several bits
        @(negedge clk); c = cnt_lo; apu[2:1] = 2'b11; r5[3] = 1;
        drain();
        expect_count("same-cycle", 1);
        check_ev("same-cycle", mon.q.pop_front(), 0, 8'h86, 8'h87, c + 1);

        // back-to-back edges
        @(negedge clk); c = cnt_lo;
        for (int i = 0; i < 5; i++) begin
            r5[0] = ~r5[0];
            if (i < 4) @(negedge clk);
        end
        drain();
        expect_count("back-to-back", 5);
        for (int i = 0; i < 5; i++)
            check_ev($sformatf("back-to-back[%0d]", i), mon.q.pop_front(), 0, 8'h10,
                     (i % 2 == 0) ? 8'h97 : 8'h87, c + 1 + i);

        // overflow: stall the stream, overrun the event FIFO, then check the flag
        tready = 0;
        @(negedge clk); c = cnt_lo;
        for (int i = 0; i < 40; i++) begin
            apu[3] = ~apu[3];
            if (i < 39) @(negedge clk);
        end
        repeat (10) @(posedge clk);
        tready = 1;
        drain();
        k = mon.q.size();
        $display("overflow: %0d events buffered before the first drop", k);
        if (k == 0 || k >= 40) begin
            $error("overflow: buffered %0d events, expected a drop", k);
            errors++;
        end
        for (int i = 0; i < k; i++)
            check_ev($sformatf("overflow[%0d]", i), mon.q.pop_front(), 0, 8'h08,
                     (i % 2 == 0) ? 8'h9F : 8'h97, c + 1 + i);

        @(negedge clk); c = cnt_lo; apu[3] = ~apu[3];
        drain();
        expect_count("overflow flag", 1);
        check_ev("overflow flag", mon.q.pop_front(), 1, 8'h08, {r5, apu}, c + 1);

        @(negedge clk); c = cnt_lo; apu[3] = ~apu[3];
        drain();
        expect_count("overflow cleared", 1);
        check_ev("overflow cleared", mon.q.pop_front(), 0, 8'h08, {r5, apu}, c + 1);

        wait (wrap_done);
        errors += mon.errors + mon_w.errors;
        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("FAILED: %0d errors", errors);
        $finish;
    end

    // counter wrap on the second instance, concurrent with the tests above
    initial begin
        wait (rstn);
        while (cnt_lo_w != 32'hFFFF_FFFC) @(negedge clk);
        cw = {12'hFFF, cnt_lo_w};
        for (int i = 0; i < 8; i++) begin
            apu_w[0] = ~apu_w[0];
            if (i < 7) @(negedge clk);
        end
        repeat (100) @(posedge clk);
        if (mon_w.q.size() != 8) begin
            $error("wrap: got %0d events, want 8", mon_w.q.size());
            errors++;
        end
        for (int i = 0; i < 8; i++)
            check_ev($sformatf("wrap[%0d]", i), mon_w.q.pop_front(), 0, 8'h01,
                     (i % 2 == 0) ? 8'h01 : 8'h00, cw + 1 + i);

        wrap_done = 1;
    end

    initial begin
        #1ms;
        $display("FAILED: timeout");
        $finish;
    end

endmodule
