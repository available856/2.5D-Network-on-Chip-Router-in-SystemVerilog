`timescale 1ns/1ps

import noc_params::*;

module tb_sif_allocator;
    
parameter CLK_PERIOD = 10;

logic rst;
logic clk;
logic [PORT_NUM-1:0][VC_NUM-1:0] request_i;
port_t [VC_NUM-1:0] out_port_i [PORT_NUM-1:0];
logic [PORT_NUM-1:0][VC_NUM-1:0] grant_o;

// DUT instance
separable_input_first_allocator dut (.*);

//Clock generation
always #(CLK_PERIOD/2) clk = ~clk;

// Check one allocation decision before accepting it on the rising edge.
task tick;
begin
    @(posedge clk); #1;
    @(negedge clk);
end
endtask

task reset_dut;
begin
    rst = 1;
    request_i = '0;
    foreach (out_port_i[i]) foreach (out_port_i[i][j]) out_port_i[i][j] = LOCAL;
    repeat (2) @(negedge clk);
    rst = 0;
end
endtask

// Shared safety checks for each of the basic cases below.
task check_grants;
    int output_count[PORT_NUM];
begin
    #1;
    foreach (output_count[p]) output_count[p] = 0;
    foreach (grant_o[i]) begin
        if (!$onehot0(grant_o[i]) || (grant_o[i] & ~request_i[i]) != '0)
            $fatal(1, "Invalid grant at input port %0d", i);
        foreach (grant_o[i][j]) if (grant_o[i][j]) output_count[out_port_i[i][j]]++;
    end
    foreach (output_count[p]) if (output_count[p] > 1) $fatal(1, "Output port %0d granted twice", p);
end
endtask

initial begin
    clk = 0;
    reset_dut;

    // Test 1: Two VCs at the same input request the same output.
    $display("[%0t]-Test 1: Same input, same output", $time);
    request_i[LOCAL] = '1;
    out_port_i[LOCAL][0] = EAST;
    out_port_i[LOCAL][1] = EAST;
    for (int i = 0; i < 4; i++) begin
        check_grants;
        if (grant_o[LOCAL] != VC_NUM'(1 << (i % VC_NUM))) $fatal(1, "Sibling VC did not receive its turn");
        tick;
    end

    // Test 2: Same input, different outputs still permits one flit per input.
    reset_dut;
    $display("[%0t]-Test 2: Same input, different outputs", $time);
    request_i[LOCAL] = '1;
    out_port_i[LOCAL][0] = EAST;
    out_port_i[LOCAL][1] = WEST;
    for (int i = 0; i < 4; i++) begin
        check_grants;
        if (grant_o[LOCAL] != VC_NUM'(1 << (i % VC_NUM))) $fatal(1, "Sibling VC rotation failed");
        tick;
    end

    // Test 3: Different inputs/outputs can all be granted together.
    reset_dut;
    $display("[%0t]-Test 3: Independent requests", $time);
    request_i[0][0] = 1; out_port_i[0][0] = SOUTH;
    request_i[1][0] = 1; out_port_i[1][0] = WEST;
    request_i[2][1] = 1; out_port_i[2][1] = EAST;
    repeat (4) begin
        check_grants;
        if (grant_o !== request_i) $fatal(1, "Independent requests were not granted together");
        tick;
    end

    // Test 4: RR1 holds while losing RR2, then advances after its own grant.
    reset_dut;
    $display("[%0t]-Test 4: Persistent contention and fairness", $time);
    request_i = '1;
    foreach (out_port_i[i]) foreach (out_port_i[i][j]) out_port_i[i][j] = NORTH;
    for (int round = 0; round < 2; round++) begin
        for (int v = 0; v < VC_NUM; v++) for (int p = 0; p < PORT_NUM; p++) begin
            check_grants;
            if (!$onehot(grant_o) || !grant_o[p][v]) $fatal(1, "Persistent requester missed its RR turn");
            tick;
        end
    end

    // Test 5: Changing output requests must preserve input/output exclusivity.
    reset_dut;
    $display("[%0t]-Test 5: Changing requests", $time);
    repeat (10) begin
        request_i = $urandom;
        foreach (out_port_i[i]) foreach (out_port_i[i][j]) out_port_i[i][j] = port_t'($urandom_range(0, PORT_NUM-1));
        check_grants;
        tick;
    end

    // Test 6: Removing a request removes its grant; idle has no grants.
    reset_dut;
    $display("[%0t]-Test 6: Disappearing request and idle", $time);
    request_i[1][0] = 1;
    check_grants;
    if (!grant_o[1][0]) $fatal(1, "Single request was not granted");
    tick;
    request_i = '0;
    repeat (2) begin
        check_grants;
        if (grant_o != '0) $fatal(1, "Grant remained after request disappeared");
        tick;
    end

    $display("SIF Allocator basic tests PASSED");
    $finish;
end

endmodule
