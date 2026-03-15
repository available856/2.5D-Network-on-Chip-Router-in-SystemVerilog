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
    // Test 1: Different VCs same input, different output ports
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
    rst = 1;
    repeat(2) @(posedge clk); //Reset
    rst = 0;

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
    // Test 3: Contention between different input ports for the same output port
    // ----------------------------

     rst = 1;
    repeat(2) @(posedge clk); //Reset
    rst = 0;

    $display("[%0t]-Test 3: Contention between different input ports for the same output port", $time);
    request_i[0] = 2'b01; // VC0 at input port 0 requests
    request_i[1] = 2'b10; // VC1 at input port 1 requests
    request_i[2] = 2'b10; // VC1 at input port 2 requests
    out_port_i[0][0] = NORTH; 
    out_port_i[1][1] = NORTH; //Desired destination
    out_port_i[2][1] = NORTH; 
    repeat (8) begin
        #1; //Wait for combinational logic to settle
        $display("[%0t]-Grants: Port0_VC0=%b, Port1_VC1=%b, Port2_VC1=%b", $time, grant_o[0][0], grant_o[1][1], grant_o[2][1]);
        if (grant_o[0][0] && grant_o[1][1] || grant_o[0][0] && grant_o[2][1] || grant_o[1][1] && grant_o[2][1]) begin
            $error("Contention detected between input ports for the same output port");
        end
        tick;
    end

    // ----------------------------
    // Test 4: No contention, multiple requests from different input ports wanting different output ports
    // ----------------------------

    rst = 1;
    repeat(2) @(posedge clk); //Reset
    rst = 0;

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

$display("-------------Simulation Finished------------");
$finish;
end

endmodule