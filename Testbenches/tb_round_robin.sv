`timescale 1ns/1ps

module tb_round_robin;

    localparam int AGENTS_NUM = 4;

    logic clk;
    logic rst;
    logic [AGENTS_NUM-1:0] requests;
    logic [AGENTS_NUM-1:0] grants;

    // DUT
    round_robin_arbiter #(
        .AGENTS_NUM(AGENTS_NUM)
    ) dut (
        .clk(clk),
        .rst(rst),
        .requests_i(requests),
        .grants_o(grants)
    );

    // Clock generation
    always #5 clk = ~clk;

    // Simple task to advance one cycle
    task tick;
        begin
            @(posedge clk);
            #1; // small delay for signal settle
        end
    endtask

    initial begin
        clk = 0;
        rst = 1;
        requests = '0;

        // Reset phase
        repeat (2) tick;
        rst = 0;

        // ----------------------------
        // Test 1: Single request
        // ----------------------------
        $display("Test 1: Single request");
        requests = 4'b0100;
        tick;
        if (grants != 4'b0100)
            $error("Single request failed");

        // ----------------------------
        // Test 2: Full contention
        // ----------------------------
        $display("Test 2: Full contention");
        requests = 4'b1111;
        repeat (8) begin
            tick;
            $display("Grant = %b", grants);
        end

        // ----------------------------
        // Test 3: Partial contention
        // ----------------------------
        $display("Test 3: Partial contention");
        requests = 4'b1011;
        repeat (8) begin
            tick;
            $display("Grant = %b", grants);
        end

        // ----------------------------
        // Test 4: No requests
        // ----------------------------
        $display("Test 4: No requests");
        requests = 4'b0000;
        repeat (2) tick;
        if (grants != 4'b0000)
            $error("No request case failed");

        $display("Simulation finished.");
        $finish;
    end

endmodule