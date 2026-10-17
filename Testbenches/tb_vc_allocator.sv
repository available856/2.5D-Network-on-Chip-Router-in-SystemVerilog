`timescale 1ns/1ps

import noc_params::*;

module tb_vc_allocator;

parameter CLK_PERIOD = 10;
parameter ADAPTIVE_TIMEOUT = 5;

// -----------------------------
// DUT signals
// -----------------------------
logic rst;
logic clk;
logic [PORT_NUM-1:0][VC_NUM-1:0] idle_downstream_vc_i;
input_block2vc_allocator ib_if();

// -----------------------------
// DUT instance
// -----------------------------
vc_allocator #(
    .ADAPTIVE_TIMEOUT(ADAPTIVE_TIMEOUT)
) dut (
    .rst(rst),
    .clk(clk),
    .idle_downstream_vc_i(idle_downstream_vc_i),
    .ib_if(ib_if)
);

// -----------------------------
// Clock generation
// -----------------------------
initial clk = 0;
always #(CLK_PERIOD/2) clk = ~clk;

// Only drive the input side of the updated allocator interface.
task clear_interface_signals();
begin
    ib_if.vc_request = '{default:'0};
    ib_if.adaptive_port_set = '0;
    ib_if.escape_port_set = '0;
    ib_if.credits_exist = '1;
    idle_downstream_vc_i = '0;
end
endtask

task reset();
begin
    @(negedge clk);
    rst = 1;
    clear_interface_signals();
    repeat (2) @(negedge clk);
    rst = 0;
end
endtask

// Every final grant must name a requested, credited, unique resource.
always @(posedge clk) begin
    if (!rst) begin
        int used[PORT_NUM][VC_NUM];
        foreach (used[p,v]) used[p][v] = 0;
        for (int p = 0; p < PORT_NUM; p++) for (int v = 0; v < VC_NUM; v++) begin
            if (ib_if.vc_valid[p][v]) begin
                int dp, dv;
                dp = int'(ib_if.port_new[p][v]); dv = int'(ib_if.vc_new[p][v]);
                if (!ib_if.vc_request[p][v] || !ib_if.credits_exist[dp][dv] || used[dp][dv])
                    $fatal(1, "Invalid or duplicate VC allocation");
                used[dp][dv]++;
                if ((v == ESCAPE || dut.escape_pending[p][v]) &&
                    (dv != ESCAPE || !ib_if.escape_port_set[p][v][dp]))
                    $fatal(1, "Escape grant did not follow the XY mask");
            end
        end
    end
end

task test_single_request();
begin
    $display("[%0t]-Test 1: Single escape and adaptive requests", $time);
    for (int v = 0; v < VC_NUM; v++) begin
        reset();
        ib_if.escape_port_set[LOCAL][v][WEST] = 1;
        ib_if.adaptive_port_set[LOCAL][v][WEST] = 1;
        ib_if.vc_request[LOCAL][v] = 1;
        #1;
        if (!ib_if.vc_valid[LOCAL][v] || ib_if.port_new[LOCAL][v] != WEST ||
            ib_if.vc_new[LOCAL][v] != ((ADAPTIVE_TIMEOUT == 0) ? ESCAPE : v))
            $fatal(1, "Single-request allocation failed");
        @(posedge clk); @(negedge clk);
        ib_if.vc_request[LOCAL][v] = 0;
    end
end
endtask

task test_escape_fallback();
begin
    $display("[%0t]-Test 2: Exact timeout and sticky XY escape", $time);
    reset();
    ib_if.credits_exist = '0;
    ib_if.adaptive_port_set[LOCAL][ADAPTIVE][WEST] = 1;
    ib_if.adaptive_port_set[LOCAL][ADAPTIVE][SOUTH] = 1;
    ib_if.escape_port_set[LOCAL][ADAPTIVE][WEST] = 1;
    ib_if.vc_request[LOCAL][ADAPTIVE] = 1;

    // A failed RR1 proposal is not a final allocation; age the complete request.
    for (int i = 1; i <= ADAPTIVE_TIMEOUT; i++) begin
        #1;
        if (ib_if.vc_valid[LOCAL][ADAPTIVE]) $fatal(1, "Grant without credit");
        @(posedge clk); #1;
        if (dut.wait_counter[LOCAL][ADAPTIVE] != i || dut.escape_pending[LOCAL][ADAPTIVE] != (i == ADAPTIVE_TIMEOUT))
            $fatal(1, "Timeout has an early or delayed pending flag");
        @(negedge clk);
    end

    // Adaptive credit returning after timeout must not cancel pending escape.
    ib_if.credits_exist[WEST][ADAPTIVE] = 1;
    repeat (2) begin
        #1;
        if (ib_if.vc_valid[LOCAL][ADAPTIVE] || !dut.escape_pending[LOCAL][ADAPTIVE])
            $fatal(1, "Pending escaped back to adaptive");
        @(posedge clk); @(negedge clk);
    end
    ib_if.credits_exist[WEST][ESCAPE] = 1;
    #1;
    if (!ib_if.vc_valid[LOCAL][ADAPTIVE] || ib_if.vc_new[LOCAL][ADAPTIVE] != ESCAPE || ib_if.port_new[LOCAL][ADAPTIVE] != WEST)
        $fatal(1, "Timed-out request did not take XY escape");
    
    @(posedge clk); #1;
    if (dut.wait_counter[LOCAL][ADAPTIVE] != 0) $fatal(1, "Grant did not clear timeout");
    
    @(negedge clk);
    ib_if.vc_request[LOCAL][ADAPTIVE] = 0;
end
endtask

task test_collision();
begin
    $display("[%0t]-Test 3: Collision and resource ownership", $time);
    reset();
    for (int p = 0; p < 3; p++) begin
        ib_if.escape_port_set[p][ESCAPE][WEST] = 1;
        ib_if.vc_request[p][ESCAPE] = 1;
    end
    #1;
    if (!$onehot({ib_if.vc_valid[0][ESCAPE],ib_if.vc_valid[1][ESCAPE],ib_if.vc_valid[2][ESCAPE]}))
        $fatal(1, "Expected exactly one winner for a shared VC");

    @(posedge clk); @(negedge clk); #1;
    for (int p = 0; p < 3; p++) if (ib_if.vc_valid[p][ESCAPE]) $fatal(1, "Allocated a busy VC again");
end
endtask

task test_fairness();
begin
    $display("[%0t]-Test 4: Round Robin across released resources", $time);
    reset();
    for (int p = 0; p < 3; p++) begin
        ib_if.escape_port_set[p][ESCAPE][WEST] = 1;
        ib_if.vc_request[p][ESCAPE] = 1;
    end
    for (int i = 0; i < 6; i++) begin
        int winner; winner = i % 3;
        #1;
        if (!ib_if.vc_valid[winner][ESCAPE]) $fatal(1, "VC resource RR skipped the next requester");
        
        @(posedge clk); @(negedge clk);
        ib_if.vc_request[winner][ESCAPE] = 0;
        idle_downstream_vc_i[WEST][ESCAPE] = 1;
        
        @(posedge clk); @(negedge clk);
        idle_downstream_vc_i = '0;
        ib_if.vc_request[winner][ESCAPE] = 1;
    end
end
endtask

task test_backpressure_combined();
begin
    $display("[%0t]-Test 5: Credits and VC release", $time);
    reset();

    ib_if.escape_port_set[LOCAL][ESCAPE][WEST] = 1;
    ib_if.vc_request[LOCAL][ESCAPE] = 1;
    #1;
    if (!ib_if.vc_valid[LOCAL][ESCAPE]) $fatal(1, "Initial allocation failed");
    
    @(posedge clk); @(negedge clk);
    
    ib_if.vc_request[LOCAL][ESCAPE] = 0;
    ib_if.escape_port_set[NORTH][ESCAPE][WEST] = 1;
    ib_if.vc_request[NORTH][ESCAPE] = 1;
    ib_if.credits_exist[WEST][ESCAPE] = 0;
    #1;
    if (ib_if.vc_valid[NORTH][ESCAPE]) $fatal(1, "Allocated without credits");
    
    @(posedge clk); @(negedge clk);
    ib_if.credits_exist[WEST][ESCAPE] = 1;
    #1;
    if (ib_if.vc_valid[NORTH][ESCAPE]) $fatal(1, "Credit alone freed an owned VC");

    idle_downstream_vc_i[WEST][ESCAPE] = 1;
    
    @(posedge clk); @(negedge clk);
    idle_downstream_vc_i = '0;
    #1;
    if (!ib_if.vc_valid[NORTH][ESCAPE]) $fatal(1, "Release plus credit did not permit allocation");
end
endtask

task test_parallel_allocation();
begin
    $display("[%0t]-Test 6: Independent allocations in parallel", $time);
    reset();
    for (int p = 0; p < 3; p++) begin
        ib_if.escape_port_set[p][ESCAPE][p] = 1;
        ib_if.vc_request[p][ESCAPE] = 1;
    end
    #1;
    for (int p = 0; p < 3; p++) begin
        if (!ib_if.vc_valid[p][ESCAPE] || ib_if.port_new[p][ESCAPE] != port_t'(p))
            $fatal(1, "Independent allocation was missing or misrouted");
    end
end
endtask

initial begin
    rst = 1;
    clear_interface_signals();
    test_single_request();
    test_escape_fallback();
    test_collision();
    test_fairness();
    test_backpressure_combined();
    test_parallel_allocation();
    $display("VC Allocator basic tests PASSED");
    $finish;
end

initial begin
    #(CLK_PERIOD*200);
    $fatal(1, "VC Allocator test timed out");
end

endmodule
