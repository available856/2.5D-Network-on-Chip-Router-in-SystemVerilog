`timescale 1ns/1ps

import noc_params::*;

module tb_rc_unit ();


localparam CLK_PERIOD = 10;

logic clk;

typedef enum logic [4:0] {
    TB_LOCAL = 5'b00001,
    TB_NORTH = 5'b00010,
    TB_SOUTH  = 5'b00100,
    TB_WEST = 5'b01000,
    TB_EAST  = 5'b10000
} port_e;

logic [DEST_ADDR_SIZE_X-1:0] dest_x;
logic [DEST_ADDR_SIZE_Y-1:0] dest_y;
vc_class_t vc_class;
logic [PORT_NUM-1:0] eligible_port_set;

rc_unit #(
    .X_CURRENT(2),
    .Y_CURRENT(2)
) dut (
    .x_dest_i(dest_x),
    .y_dest_i(dest_y),
    .vc_class_i(vc_class),
    .eligible_port_set(eligible_port_set)
);

initial clk = 0;
always #(CLK_PERIOD/2) clk = ~clk;

//Helper tasks for checking results
task check_onehot(input string test_name);
if (!$onehot(eligible_port_set)) begin
    $error("%s FAILED: not one-hot = %b", test_name, eligible_port_set);
end else begin
    $display("[%0t]-%s PASSED", $time, test_name);
end
endtask

task check_count(input string test_name, input int expected);
if ($countones(eligible_port_set) != expected) begin
    $error("%s FAILED: expected %0d, got %0d (%b)",
        test_name, expected, $countones(eligible_port_set), eligible_port_set);
end else begin
    $display("[%0t]-%s PASSED", $time, test_name);
end
endtask

task check_exact_port(input string name, input logic [PORT_NUM-1:0] expected);
    if (eligible_port_set !== expected) begin
        $error("%s FAILED: expected %b got %b",
            name, expected, eligible_port_set);
    end 
    else begin
        $display("[%0t]-%s PASSED", $time, name);
    end
endtask

//-------------------------
// Test cases
//-------------------------

// Escape VC tests
task test_x_movement_escape();
    port_e output_ports;
    logic [PORT_NUM-1:0] expected_ports;

    vc_class = ESCAPE;

    dest_x = 3; dest_y = 2; // Should go EAST
    expected_ports = TB_EAST;
    #1; 
    output_ports = port_e'(eligible_port_set);
    $display("[%0t]-Eligible port: %s", $time, output_ports.name());
    check_onehot("Test X movement one-hot (ESCAPE)");
    check_exact_port("Test X movement EAST (ESCAPE)", expected_ports);
    #1;
endtask

task test_y_movement_escape();
    port_e output_ports;
    logic [PORT_NUM-1:0] expected_ports;

    vc_class = ESCAPE;

    dest_x = 2; dest_y = 1; // Should go SOUTH
    expected_ports = TB_SOUTH;
    #1; 
    output_ports = port_e'(eligible_port_set);
    $display("[%0t]-Eligible port: %s", $time, output_ports.name());
    check_onehot("Test Y movement one-hot (ESCAPE)");
    check_exact_port("Test Y movement SOUTH (ESCAPE)", expected_ports);
    #1;
endtask

task test_no_movement_escape();
    port_e output_ports;
    logic [PORT_NUM-1:0] expected_ports;

    vc_class = ESCAPE;

    dest_x = 2; dest_y = 2; // Should stay LOCAL
    expected_ports = TB_LOCAL;
    #1; 
    output_ports = port_e'(eligible_port_set);
    $display("[%0t]-Eligible port: %s", $time, output_ports.name());
    check_onehot("Test No Movement one-hot (ESCAPE)");
    check_exact_port("Test No Movement - LOCAL (ESCAPE)", expected_ports);
    #1;
endtask

//Adaptive VC Tests
task test_xy_movement_adaptive();
    port_e output_ports;
    logic [PORT_NUM-1:0] expected_ports;

    vc_class = ADAPTIVE;

    dest_x = 3; dest_y = 1; // Should go EAST and SOUTH
    expected_ports = TB_EAST | TB_SOUTH;
    #1;
    for (int i = 0; i < PORT_NUM; i++) begin
        if (eligible_port_set[i]) begin
            output_ports = port_e'(1 << i);
            $display("[%0t]-Eligible port: %s", $time, output_ports.name());
        end
    end
    check_count("Test X and Y movement count (ADAPTIVE)", 2);
    check_exact_port("Test X and Y movement EAST+SOUTH (ADAPTIVE)", expected_ports);
    #1;
endtask

task test_single_dimension_adaptive();
    port_e output_ports;
    logic [PORT_NUM-1:0] expected_ports;

    vc_class = ADAPTIVE;

    dest_x = 3; dest_y = 2; // Should go EAST only
    expected_ports = TB_EAST;

    #1;
    for (int i = 0; i < PORT_NUM; i++) begin
        if (eligible_port_set[i]) begin
            output_ports = port_e'(1 << i);
            $display("[%0t]-Eligible port: %s", $time, output_ports.name());
        end
    end
    check_onehot("Test X movement only one-hot (ADAPTIVE)");
    check_exact_port("Test X movement only EAST (ADAPTIVE)", expected_ports);
    #1;
endtask

task 
test_no_movement_adaptive();
    port_e output_ports;
    logic [PORT_NUM-1:0] expected_ports;

    vc_class = ADAPTIVE;

    dest_x = 2; dest_y = 2; // Should stay LOCAL
    expected_ports = TB_LOCAL;
    #1;
    for (int i = 0; i < PORT_NUM; i++) begin
        if (eligible_port_set[i]) begin
            output_ports = port_e'(1 << i);
            $display("[%0t]-Eligible port: %s", $time, output_ports.name());
        end
    end
    check_onehot("Test No Movement one-hot (ADAPTIVE)");
    check_exact_port("Test No Movement - LOCAL (ADAPTIVE)", expected_ports);
    #1;
endtask

initial begin
    @(posedge clk);

    test_x_movement_escape();
    test_y_movement_escape();
    test_no_movement_escape();
    test_xy_movement_adaptive();
    test_single_dimension_adaptive();
    test_no_movement_adaptive();

    $finish;
end

endmodule