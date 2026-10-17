`timescale 1ns/1ps

module tb_round_robin;

    parameter CLK_PERIOD = 10;
    localparam AGENTS_NUM = 4;

    logic clk;
    logic rst; 
    logic advance;
    logic [AGENTS_NUM-1:0] requests;
    logic [AGENTS_NUM-1:0] grants;

    // DUT
    round_robin_arbiter #(
        .AGENTS_NUM(AGENTS_NUM)
    ) dut (
        .clk(clk),
        .rst(rst),
        .advance_i(advance), // Advance only when the selected grant is accepted
        .requests_i(requests),
        .grants_o(grants)
    );

    // Clock generation
    always #(CLK_PERIOD/2) clk = ~clk;

    // Simple task to advance one cycle
    task tick;
        begin
            @(posedge clk);
            #1; // small delay for signal settle
        end
    endtask

    // Check the combinational grant before the edge accepting it.
    task check_grant(input logic [AGENTS_NUM-1:0] request_set,
        input logic [AGENTS_NUM-1:0] expected, input logic accepted);
        begin
            @(negedge clk);
            requests = request_set;
            advance = accepted;
            #1;
            if (grants !== expected)
                $fatal(1, "Expected grant %b, got %b", expected, grants);
            tick;
        end
    endtask

    initial begin
        clk = 0;
        rst = 1;
        requests = '0;
        advance = 0;

        // Reset phase
        repeat (2) tick;
        rst = 0;

        // ----------------------------
        // Test 1: Single request
        // ----------------------------
        $display("Test 1: Single request");
        check_grant(4'b0100, 4'b0100, 1);

        // ----------------------------
        // Test 2: Full contention
        // ----------------------------
        $display("Test 2: Full contention");
        // Accepting agent 2 above makes agent 3 the next priority.
        for (int i = 0; i < 8; i++) begin
            check_grant(4'b1111, AGENTS_NUM'(1 << ((i + 3) % AGENTS_NUM)), 1);
        end

        // ----------------------------
        // Test 3: Partial contention
        // ----------------------------
        $display("Test 3: Partial contention");
        repeat (2) begin
            check_grant(4'b1011, 4'b1000, 1);
            check_grant(4'b1011, 4'b0001, 1);
            check_grant(4'b1011, 4'b0010, 1);
        end

        // ----------------------------
        // Test 4: Hold priority while the selected request loses RR2
        // ----------------------------
        $display("Test 4: Hold until accepted");
        repeat (3) check_grant(4'b1111, 4'b0100, 0);
        check_grant(4'b1111, 4'b0100, 1);
        check_grant(4'b1111, 4'b1000, 1); // Wrap back to agent 0

        // ----------------------------
        // Test 5: Idle cycles preserve priority even with advance high
        // ----------------------------
        $display("Test 5: No requests");
        repeat (2) check_grant(4'b0000, 4'b0000, 1);
        check_grant(4'b1111, 4'b0001, 0);

        $display("Round Robin basic tests PASSED");
        $finish;
    end

endmodule
