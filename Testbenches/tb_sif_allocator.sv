`timescale 1ns/1ps

import noc_params::*;

module tb_sif_allocator;
    
parameter CLK_PERIOD = 10;

logic rst;
logic clk;
logic [PORT_NUM-1:0][VC_NUM-1:0] request_i;
port_t out_port_i [PORT_NUM-1:0][VC_NUM-1:0];
logic [PORT_NUM-1:0][VC_NUM-1:0] grant_o;

// DUT instance
separable_input_first_allocator #(
    .VC_NUM(VC_NUM)
) dut (.*);

//Clock generation
always #(CLK_PERIOD/2) clk = ~clk;

// Simple task to advance one cycle
task tick;
    begin
        @(posedge clk);
        #1; // small delay for signal settle
    end
endtask

task reset_dut;
    begin
        rst = 1;
        request_i = '0; // Instantly kill all active requests
        
        // Safely park all output destinations
        foreach (out_port_i[i]) begin
            foreach (out_port_i[i][j]) begin
                out_port_i[i][j] = LOCAL; 
            end
        end

        repeat(2) @(posedge clk);
        rst = 0;
    end
endtask

initial begin
    clk = 0;
    rst = 1;
    request_i = '0;
    foreach (out_port_i[i]) begin
        foreach (out_port_i[i][j]) begin
            out_port_i[i][j] = LOCAL; // Default to LOCAL, can be changed in tests
        end
    end

    repeat (2) @(posedge clk); //Reset phase
    rst = 0;

    // ----------------------------
    // Test 1: Different VCs same input, same output ports
    // ----------------------------
    $display("[%0t]-Test 1: Different VCs same input, same output ports",$time);
    request_i[0] = 2'b11; // Both VCs at input port 0 request
    out_port_i[0][0] = EAST; // VC0 requests output port 0, VC1 requests output port 1
    out_port_i[0][1] = EAST; // Both VCs request the same output port
    repeat (4) begin
        #1; // Wait for combinational logic to settle
        $display("[%0t]-Grant VC0 = %b, VC1 = %b", $time, grant_o[0][0], grant_o[0][1]);
        if (grant_o[0] == 2'b11) begin
            $error("Both VCs granted simultaneously at input port 0");
        end
           tick;
    end

    // ----------------------------
    // Test 2: Different VCs same input, different output ports
    // ----------------------------
    reset_dut;

    $display("[%0t]-Test 2: Different VCs same input, different output ports", $time);
    request_i[0] = 2'b11; // Both VCs at input port 0 request
    out_port_i[0][0] = EAST; // VC0 requests output port 0, VC1 requests output port 1
    out_port_i[0][1] = WEST; // Both VCs request the same output port
    repeat (4) begin
        #1; // Wait for combinational logic to settle
        $display("[%0t]-Grant VC0 = %b, VC1 = %b", $time, grant_o[0][0], grant_o[0][1]);
          unique case (1)
            grant_o[0][0]: $display("[%0t]-Port = EAST granted at input port 0", $time);
            grant_o[0][1]: $display("[%0t]-Port = WEST granted at input port 0", $time);
            default: $error("No grants at input port 0");
        endcase
        if (grant_o[0] == 2'b11) begin
            $error("Both VCs granted simultaneously at input port 0");
        end
           tick;
    end

    // ----------------------------
    // Test 3: Full stress contention test between different input ports for the same output port - Varying OP
    // ----------------------------
    reset_dut;

    $display("[%0t]-Test 3: Full stress contention test between different input ports for the same output port - Varying OP", $time);
    
    foreach (request_i[i]) begin
        request_i[i] = '1; // All VCs at all input ports request
    end

    repeat (20) begin
        int output_count[PORT_NUM];

        foreach (out_port_i[i]) begin
            foreach (out_port_i[i][j]) begin
                out_port_i[i][j] = port_t'($time/CLK_PERIOD % PORT_NUM); // All VCs want the same output port at the same time
            end
        end

    #1; // Wait for combinational logic to settle

    // property 1: no two VCs granted in same input
    $display("[%0t]-Property 1: No two VCs granted in same input", $time);
    foreach (grant_o[i]) begin
        if (grant_o[i] == 2'b11)
            $error("Two VCs granted at same input port %0d", i);
    end
    $display("[%0t]-Property 1 : PASSED", $time);

    // property 2: only one input per output
    $display("[%0t]-Property 2: Only one input per output", $time);

    foreach (output_count[p]) output_count[p] = 0;

    foreach (grant_o[i]) begin
        foreach (grant_o[i][j]) begin
            if (grant_o[i][j])
                output_count[out_port_i[i][j]]++;
        end
    end

    foreach (output_count[p]) begin
        if (output_count[p] > 1)
            $error("Multiple inputs granted same output port %0d", p);
        end

    foreach (grant_o[i]) begin
        foreach (grant_o[i][j]) begin
            if (grant_o[i][j])
                $display("[%0t]-IP%0d -> VC%0d -> OP%0d", $time, i, j, out_port_i[i][j]);
        end
    end

    tick;
end
        

    // ----------------------------
    // Test 4: No contention, multiple requests from different input ports wanting different output ports
    // ----------------------------
    reset_dut;

    $display("[%0t]-Test 4: No contention, multiple requests from different input ports wanting different output ports", $time);
    request_i[0] = 2'b01; // VC0 at input port 0 requests
    request_i[1] = 2'b01; // VC0 at input port 1 requests
    request_i[2] = 2'b10; // VC1 at input port 2 requests
    out_port_i[0][0] = SOUTH; 
    out_port_i[1][0] = WEST; 
    out_port_i[2][1] = EAST; 
    repeat (8) begin
        #1; // Wait for combinational logic to settle
        if (grant_o[0][0] && grant_o[1][0] && grant_o[2][1])
             $display("[%0t]-Grants: Port0_VC0=%b, Port1_VC0=%b, Port2_VC1=%b", $time, grant_o[0][0], grant_o[1][0], grant_o[2][1]);
        else
            $error("Test Failed ! Expected all grants to be high but got Port0_VC0=%b, Port1_VC0=%b, Port2_VC1=%b", grant_o[0][0], grant_o[1][0], grant_o[2][1]);
        tick;
    end

// ----------------------------
// Test 5: Full stress test
// ----------------------------
reset_dut;
    
$display("[%0t]-Test 5: Stress test (all requests active)", $time);

// enable every VC request
foreach (request_i[i]) begin
    request_i[i] = '1;
end

repeat (20) begin
    int output_count[PORT_NUM];

    // rotate destination ports every cycle
    foreach (out_port_i[i]) begin
        foreach (out_port_i[i][j]) begin
            out_port_i[i][j] = port_t'((i + j + $time/CLK_PERIOD) % PORT_NUM);
        end
    end

    #1;

    // property 1: no two VCs granted in same input
    $display("[%0t]-Property 1: No two VCs granted in same input", $time);
    foreach (grant_o[i]) begin
        if (grant_o[i] == 2'b11)
            $error("Two VCs granted at same input port %0d", i);
    end
    $display("[%0t]-Property 1 : PASSED", $time);

    // property 2: only one input per output
    $display("[%0t]-Property 2: Only one input per output", $time);

    foreach (output_count[p]) output_count[p] = 0;

    foreach (grant_o[i]) begin
        foreach (grant_o[i][j]) begin
            if (grant_o[i][j])
                output_count[out_port_i[i][j]]++;
        end
    end

    foreach (output_count[p]) begin
        if (output_count[p] > 1)
            $error("Multiple inputs granted same output port %0d", p);
    end

    $display("[%0t]-Property 2 : PASSED", $time);

    foreach (grant_o[i]) begin
        foreach (grant_o[i][j]) begin
            if (grant_o[i][j])
                $display("[%0t]-IP%0d -> VC%0d -> OP%0d", $time, i, j, out_port_i[i][j]);
        end
    end

    tick;
end

// ----------------------------
// Test 6: IDLE case (no requests)
// ----------------------------
reset_dut;

$display("[%0t]-Test 6: Idle case (no active requests)", $time);

repeat (4) begin
    #1;

    foreach (grant_o[i]) begin
        if (grant_o[i] != '0)
            $error("Unexpected grant during IDLE at input port %0d: %b", i, grant_o[i]);
    end

    $display("[%0t]-All grants correctly idle", $time);

    tick;
end

// ----------------------------
// Test 7: Disappearing request
// ----------------------------
reset_dut;

$display("[%0t]-Test 7: Disappearing request", $time);

// initial request
request_i[1][0] = 1;
out_port_i[1][0] = EAST;

#1;

if (!grant_o[1][0])
    $error("Request should have been granted but was not");
else
    $display("[%0t]-Grant correctly issued before request disappears", $time);

tick;

// remove the request
request_i[1][0] = 0;

#1;

foreach (grant_o[i]) begin
    foreach (grant_o[i][j]) begin
        if (grant_o[i][j])
            $error("Grant persisted after request disappeared at input %0d VC %0d", i, j);
    end
end

$display("[%0t]-Grant correctly removed after request disappeared", $time);

tick;

// ----------------------------
// Test 8: Full stress contention test between different input ports for the same output port - Constant OP
// ----------------------------
reset_dut;

$display("[%0t]-Test 8: Full stress contention test between different input ports for the same output port - Constant OP", $time);

foreach (request_i[i]) begin
    request_i[i] = '1; // All VCs at all input ports request
end

repeat (20) begin
    int output_count[PORT_NUM];

    foreach (out_port_i[i]) begin
        foreach (out_port_i[i][j]) begin
            out_port_i[i][j] = NORTH; // All VCs want the same output port at the same time
        end
    end

#1; // Wait for combinational logic to settle

// property 1: no two VCs granted in same input
$display("[%0t]-Property 1: No two VCs granted in same input", $time);
foreach (grant_o[i]) begin
    if (grant_o[i] == 2'b11)
        $error("Two VCs granted at same input port %0d", i);
end
$display("[%0t]-Property 1 : PASSED", $time);

// property 2: only one input per output
$display("[%0t]-Property 2: Only one input per output", $time);

foreach (output_count[p]) output_count[p] = 0;

foreach (grant_o[i]) begin
    foreach (grant_o[i][j]) begin
        if (grant_o[i][j])
            output_count[out_port_i[i][j]]++;
    end
end

foreach (output_count[p]) begin
    if (output_count[p] > 1)
        $error("Multiple inputs granted same output port %0d", p);
    end

foreach (grant_o[i]) begin
    foreach (grant_o[i][j]) begin
        if (grant_o[i][j])
            $display("[%0t]-IP%0d -> VC%0d -> OP%0d", $time, i, j, out_port_i[i][j]);
    end
end

tick;
end



$display("-------------Simulation Finished------------");
$finish;
end

endmodule