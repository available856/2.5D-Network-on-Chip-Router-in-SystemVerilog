`timescale 1ns/1ps

import noc_params::*;

module tb_vc_allocator;

parameter CLK_PERIOD = 10;

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
vc_allocator dut (
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

// -----------------------------
// Helper: clear requests
// -----------------------------
task clear_interface_signals();
    ib_if.vc_new = '{default: '{default: '0}};
    ib_if.port_new = '{default:0};
    ib_if.vc_valid = '{default:0};
    ib_if.vc_request = '{default:0};
    ib_if.out_port_mask = '0;
    ib_if.credits_exist = '1; // Assume all VCs have credits by default
    ib_if.vc_class = '0; // Assume all VCs are of class ESCAPE by default
endtask

// -----------------------------
// Reset task
// -----------------------------
task reset();
    rst = 1;
    idle_downstream_vc_i = '0; // All downstream VCs start as busy (not idle)
    clear_interface_signals();
    repeat (2) @(posedge clk); // Hold reset for 2 cycles
    rst = 0;
    @(posedge clk); // Wait for one cycle after deasserting reset
endtask

// -----------------------------
// Collision always block
// -----------------------------
always @(negedge clk) begin
    int count;

    for (int down_port = 0; down_port < PORT_NUM; down_port++) begin
        for (int down_vc = 0; down_vc < VC_NUM; down_vc++) begin
            count = 0;
            for (int up_port = 0; up_port < PORT_NUM; up_port++) begin
                for (int up_vc = 0; up_vc < VC_NUM; up_vc++) begin
                    if (ib_if.vc_valid[up_port][up_vc] && ib_if.port_new[up_port][up_vc] == port_t'(down_port) && ib_if.vc_new[up_port][up_vc] == down_vc) begin
                        count++;
                        if (count > 1) begin
                            $fatal(1, "[%0t]-Collision Detected: Downstream VC(%0d,%0d) allocated to multiple upstream agents", $time, down_port, down_vc);
                        end
                    end
                end
            end
        end
    end
end

// -----------------------------
// TEST 1: Single request
// -----------------------------
task test_single_request();
    $display("[%0t]-Test 1: Single Request", $time);

    reset();

    @(negedge clk);

    //Example Request: Input port 0, VC 0 requests downstream VC 0 on output port 1
    ib_if.out_port_mask[0][0][1] = 1'b1; // Requesting output port 1
    ib_if.vc_request[0][0] = 1'b1; // Request from input port 0, VC 0
    


    @(posedge clk); //Wait to allow propagation of allocation

    //Check
    if (!ib_if.vc_valid[0][0])  
        $error ("[%0t]-Test 1 Failed: Expected VC(0,0) to allocate downstream VC(1,0)", $time);
    else if (ib_if.vc_new[0][0] != 0 || ib_if.port_new[0][0] != port_t'(1))
        $error ("[%0t]-Test 1 Failed: Expected allocated downstream VC to be 0, got %0d", $time, ib_if.vc_new[0][0]);
    else 
        $display("[%0t]-Test 1 Passed", $time);
    endtask 

// -----------------------------
// TEST 2: Multiple Requests for the same downstream VC (Collision Detection)
// -----------------------------
task test_collision();
    $display("[%0t]-Test 2: Collision Detection", $time);

    reset();

    @(negedge clk);

    //Example Requests: Input port 0, VC 0 and Input port 1, VC 0 both request downstream VC 0 on output port 2
    ib_if.out_port_mask[0][0][2] = 1'b1; // Requesting output port 2
    ib_if.out_port_mask[1][0][2] = 1'b1; // Both input port 0, VC 0 and input port 1, VC 0 requesting output port 2

    ib_if.vc_request[0][0] = 1'b1; // Request from input port 0, VC 0
    ib_if.vc_request[1][0] = 1'b1; // Request from input port 1, VC 0

    ib_if.credits_exist[2][1] = 1'b0; // Assume credits DON'T exist for downstream VC(2,1) to force allocation of downstream VC(2,0) and create a collision scenario

    @(posedge clk); //Wait to allow propagation of allocation

    //Check
    unique if (ib_if.vc_valid[0][0] && ib_if.vc_new[0][0] == 0 && ib_if.port_new[0][0] == port_t'(2))  
        $display("[%0t]-Test 2 Passed: Input port 0, VC 0 allocated downstream VC(2,0)", $time);
    else if (ib_if.vc_valid[1][0] && ib_if.vc_new[1][0] == 0 && ib_if.port_new[1][0] == port_t'(2))
        $display("[%0t]-Test 2 Passed: Input port 1, VC 0 allocated downstream VC(2,0)", $time);
    else
        $error ("[%0t]-Test 2 Failed: Expected one of the input ports to allocate downstream VC(2,0)", $time);

endtask

// -----------------------------
// TEST 3: Fairness (RR)
// -----------------------------
task test_fairness();
    $display("[%0t]-Test 3: Fairness (Round Robin)", $time);
    reset();

    repeat (10) begin
        
        
        // 1. SETUP PHASE (Drive on Negedge)
        
        @(negedge clk);
        clear_interface_signals();

        // All 3 Agents request downstream VC 0 on output port 3
        ib_if.out_port_mask[0][1][3] = 1'b1;
        ib_if.out_port_mask[1][0][3] = 1'b1;
        ib_if.out_port_mask[2][1][3] = 1'b1;

        ib_if.vc_request[0][1] = 1'b1; 
        ib_if.vc_request[1][0] = 1'b1; 
        ib_if.vc_request[2][1] = 1'b1; 

        ib_if.credits_exist[3][1] = 1'b0; // Force (3,0)

        
        // 2. EVALUATION PHASE (Read on Posedge)
        
        @(posedge clk); 

        unique if (ib_if.vc_valid[0][1] && ib_if.vc_new[0][1] == 0 && ib_if.port_new[0][1] == port_t'(3))  
            $display("[%0t]-Test 3 Passed: Input port 0, VC 1 allocated downstream VC(3,0)", $time);
        else if (ib_if.vc_valid[1][0] && ib_if.vc_new[1][0] == 0 && ib_if.port_new[1][0] == port_t'(3))
            $display("[%0t]-Test 3 Passed: Input port 1, VC 0 allocated downstream VC(3,0)", $time);
        else if (ib_if.vc_valid[2][1] && ib_if.vc_new[2][1] == 0 && ib_if.port_new[2][1] == port_t'(3))
            $display("[%0t]-Test 3 Passed: Input port 2, VC 1 allocated downstream VC(3,0)", $time);
        else
            $error ("[%0t]-Test 3 Failed: Expected one of the input ports to allocate downstream VC(3,0)", $time);
        
        
        // 3. RELEASE PHASE (Drive on next Negedge)
        
        @(negedge clk);
        ib_if.vc_request = '{default:0}; // Safely drop requests
        idle_downstream_vc_i[3][0] = 1'b1; // Fire release pulse
        
        
        // 4. CLEANUP PHASE (Next Negedge)
        
        @(negedge clk); 
        idle_downstream_vc_i[3][0] = 1'b0; // Clear the pulse
    end

endtask

// -----------------------------
// Test 4: Backpressure (Availability + Credits)
// -----------------------------
task test_backpressure_combined();
    $display("[%0t]-Test 4: Backpressure (Availability + Credits)", $time);

    reset();

    // Step 1: Allocate VC(2,0) → make it unavailable
    @(negedge clk);

    ib_if.out_port_mask[0][0][2] = 1'b1; // Requesting output port 2
    ib_if.vc_request[0][0] = 1'b1; // Request from input port 0, VC 0
    ib_if.credits_exist[2][1] = 1'b0; // Force allocation of downstream VC(2,0) to create a backpressure scenario

    @(posedge clk);

    if (!ib_if.vc_valid[0][0])
        $error("Initial allocation failed");

    // Step 2: Remove all credits ALSO
    @(negedge clk);

    ib_if.credits_exist[2][0] = 1'b0;

    @(posedge clk);

    // MUST NOT allocate (blocked by BOTH)
    if (ib_if.vc_valid[0][0])
        $error("Backpressure FAILED: allocation happened under full block");

    // Step 3: Restore credits ONLY → still blocked (availability = 0)
    @(negedge clk);

    ib_if.credits_exist[2][0] = 1'b1;

    @(posedge clk);

    if (ib_if.vc_valid[0][0])
        $error("Allocation happened despite VC still locked");

    // Step 4: Release VC → now should work
    @(negedge clk);
    idle_downstream_vc_i[2][0] = 1'b1; // pulse
    ib_if.vc_request[0][0] = 1'b0; // Drop request to avoid immediate re-allocation

    @(negedge clk);
    idle_downstream_vc_i[2][0] = 1'b0;

    @(negedge clk);
    ib_if.vc_request[0][0] = 1'b1; // Re-assert request after release

    @(posedge clk);

    if (!ib_if.vc_valid[0][0])
        $error("Allocation failed after release + credits");

    $display("[%0t]-Test 4: Backpressure (Availability + Credits) PASSED", $time);
endtask 

// -----------------------------
// TEST 5: Multi-Resource Parallel Allocation
// -----------------------------
task test_parallel_allocation();
    $display("[%0t]-Test 5: Multi-Resource Parallel Allocation", $time);

    reset();

    // 1. Setup Phase (Drive on Negedge)
    @(negedge clk);

    // Agent (0,0) requests Port 1
    ib_if.out_port_mask[0][0][1] = 1'b1;
    ib_if.vc_request[0][0] = 1'b1;

    // Agent (1,0) requests Port 2
    ib_if.out_port_mask[1][0][2] = 1'b1;
    ib_if.vc_request[1][0] = 1'b1;

    // Agent (2,0) requests Port 3
    ib_if.out_port_mask[2][0][3] = 1'b1;
    ib_if.vc_request[2][0] = 1'b1;

    
    // 2. Evaluation Phase (Read on Posedge)
    @(posedge clk);

    // We expect ALL THREE to receive a grant in the exact same clock cycle.
    if (!ib_if.vc_valid[0][0] || !ib_if.vc_valid[1][0] || !ib_if.vc_valid[2][0]) begin
        $error("[%0t]-Test 5 Failed: Allocator serialized the requests instead of granting in parallel!", $time);
    end 
    else begin
       //Verify they got routed to the correct ports
        if (ib_if.port_new[0][0] != port_t'(1) || ib_if.port_new[1][0] != port_t'(2) || ib_if.port_new[2][0] != port_t'(3)) begin
            $error("[%0t]-Test 5 Failed: Parallel allocation routed to the wrong ports!", $time);
        end 
        else begin
            $display("[%0t]-Test 5 Passed: 3 Independent Allocations in 1 Cycle", $time);
        end
    end

    
    // 3. Cleanup Phase (Drop Requests, Fire Releases)
    @(negedge clk);
    ib_if.vc_request = '{default:0}; // Safely drop all requests

    // Release whatever downstream VCs they were assigned (likely VC 0 for all)
    idle_downstream_vc_i[1][ib_if.vc_new[0][0]] = 1'b1;
    idle_downstream_vc_i[2][ib_if.vc_new[1][0]] = 1'b1;
    idle_downstream_vc_i[3][ib_if.vc_new[2][0]] = 1'b1;

    @(negedge clk);
    idle_downstream_vc_i = '0; // Clear all pulses
endtask

// -----------------------------
// TEST 6: No-Eligible-Resource (Hard Stall)
// -----------------------------
task test_hard_stall();
    $display("[%0t]-Test 6: No-Eligible-Resource (Hard Stall)", $time);

    reset();

    
    // 1. SETUP PHASE: Create a locked VC scenario first
    @(negedge clk);
    
    // Allocate VC(3,0) to Agent (2,0) just to lock it.
    ib_if.out_port_mask[2][0][3] = 1'b1;
    ib_if.vc_request[2][0] = 1'b1;
    ib_if.credits_exist[3][1] = 1'b0; // Force it to pick VC 0
    
    @(posedge clk); // VC(3,0) is now officially LOCKED.

    // 2. STALL PHASE (Drive on Negedge)
    @(negedge clk);
    ib_if.vc_request = '{default:0}; // Drop the setup request
    
    // Scenario A: Valid request, but NO CREDITS anywhere on the port
    ib_if.out_port_mask[0][0][1] = 1'b1;
    ib_if.vc_request[0][0] = 1'b1;
    for (int v = 0; v < VC_NUM; v++) 
        ib_if.credits_exist[1][v] = 1'b0; 

    // Scenario B: Valid request, but ONLY available VC is LOCKED
    // (Port 3, VC 0 is locked from Step 1. We disable VC 1 via credits)
    ib_if.out_port_mask[1][0][3] = 1'b1;
    ib_if.vc_request[1][0] = 1'b1;
    ib_if.credits_exist[3][1] = 1'b0; 

    // Scenario C: Request asserted, but NO Routing Mask match
    ib_if.out_port_mask[2][1] = '0; // Empty mask
    ib_if.vc_request[2][1] = 1'b1;


    // 3. EVALUATION PHASE (Read on Posedge)
    @(posedge clk);

    // The allocator should remain dead silent. ALL vc_valid bits MUST be 0.
    for (int p = 0; p < PORT_NUM; p++) begin
        for (int v = 0; v < VC_NUM; v++) begin
            if (ib_if.vc_valid[p][v]) begin
                $error("[%0t]-Test 6 Failed: Allocator issued a grant to an ineligible resource! vc_valid[%0d][%0d] = 1", $time, p, v);
            end
        end
    end

    $display("[%0t]-Test 6 Passed: Allocator correctly stalled all invalid requests", $time);


    // 4. CLEANUP PHASE
    @(negedge clk);
    ib_if.vc_request = '{default:0};
    idle_downstream_vc_i[3][0] = 1'b1; // Release the lock from Step 1

    @(negedge clk);
    idle_downstream_vc_i = '0;
endtask


initial begin

    test_single_request();
    test_collision();
    test_fairness();
    test_backpressure_combined();
    test_parallel_allocation();
    test_hard_stall();

    $finish;
end

endmodule