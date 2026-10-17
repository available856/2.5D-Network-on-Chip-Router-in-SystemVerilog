`timescale 1ns/1ps

import noc_params::*;

module tb_circular_buffer ();

  parameter CLK_PERIOD = 10;

    // --------------------------------------------------
    // Clock / Reset
    // --------------------------------------------------
    logic rst;
    logic clk;

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    // --------------------------------------------------
    // DUT signals
    // --------------------------------------------------
    flit_t data_i;
    //flit_t data_o;
    flit_t peek_o;

    logic read_i;
    logic write_i;
    logic is_full;
    logic is_empty;

    // --------------------------------------------------
    // Instantiate DUT
    // --------------------------------------------------
    circular_buffer #(
        .BUFFER_SIZE(VC_DEPTH)
    ) dut (.*);

    flit_t expected_q[$];

    // Drive on the falling edge; peek is checked before the read edge.
    task write_flit(input int value);
        begin
            @(negedge clk);
            if (is_full) $fatal(1, "Write attempted on a full buffer");
            data_i = '0;
            data_i.flit_label = BODY;
            data_i.data.bt_pl = BODY_PAYLOAD_SIZE'(value);
            write_i = 1;
            expected_q.push_back(data_i);
            @(negedge clk);
            write_i = 0;
        end
    endtask

    task read_flit;
        flit_t expected;
        begin
            @(negedge clk);
            if (is_empty || expected_q.size() == 0) $fatal(1, "Unexpected empty buffer");
            expected = expected_q.pop_front();
            if (peek_o !== expected) $fatal(1, "FIFO order or payload mismatch");
            read_i = 1;
            @(negedge clk);
            read_i = 0;
        end
    endtask

    // --------------------------------------------------
    // Test sequence
    // --------------------------------------------------
    initial begin
        rst = 1;
        read_i = 0;
        write_i = 0;
        data_i = '0;
        repeat (2) @(negedge clk);
        rst = 0;
        #1;
        if (!is_empty || is_full) $fatal(1, "Reset flags failed");

        // Write to full, then check that peek does not remove data.
        for (int i = 0; i < VC_DEPTH; i++) write_flit(i);
        if (!is_full) $fatal(1, "Buffer should be full");
        repeat (2) begin
            @(negedge clk);
            if (peek_o !== expected_q[0] || !is_full) $fatal(1, "Peek changed the buffer");
        end

        // Read two, then write two to exercise pointer wraparound.
        repeat (2) read_flit();
        write_flit(VC_DEPTH);
        write_flit(VC_DEPTH+1);
        if (!is_full) $fatal(1, "Buffer should be full after wraparound");

        // Simultaneous read/write with room available preserves occupancy.
        read_flit();
        @(negedge clk);
        begin
            flit_t expected;
            expected = expected_q.pop_front();
            if (peek_o !== expected) $fatal(1, "Simultaneous read mismatch");
        end
        data_i.data.bt_pl = BODY_PAYLOAD_SIZE'(VC_DEPTH+2);
        expected_q.push_back(data_i);
        read_i = 1;
        write_i = 1;
        @(negedge clk);
        read_i = 0;
        write_i = 0;
        if (is_empty || is_full) $fatal(1, "Simultaneous transfer changed occupancy");

        while (expected_q.size() != 0) read_flit();
        if (!is_empty) $fatal(1, "Buffer did not drain");
        $display("Circular Buffer basic tests PASSED");
        $finish;
    end

endmodule
