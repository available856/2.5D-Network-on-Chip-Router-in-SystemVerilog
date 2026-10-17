`timescale 1ns/1ps

import noc_params::*;

module tb_rc_unit_corner ();


typedef enum logic [4:0] {
    TB_LOCAL = 5'b00001,
    TB_NORTH = 5'b00010,
    TB_SOUTH  = 5'b00100,
    TB_WEST = 5'b01000,
    TB_EAST  = 5'b10000
} port_e;

logic [DEST_ADDR_SIZE_X-1:0] dest_x;
logic [DEST_ADDR_SIZE_Y-1:0] dest_y;
logic [PORT_NUM-1:0] escape_port_set;
logic [PORT_NUM-1:0] adaptive_port_set;
logic rc_valid;


// Corner router (0,0) in the 2x2 mesh.
rc_unit #(
    .X_CURRENT(0),
    .Y_CURRENT(0)
) dut (
    .x_dest_i(dest_x),
    .y_dest_i(dest_y),
    .rc_valid_i(rc_valid),
    .adaptive_port_set(adaptive_port_set),
    .escape_port_set(escape_port_set)
);


//Helper tasks for checking results
task check_onehot(input string test_name);
if (!$onehot(escape_port_set)) begin
    $error("%s FAILED: not one-hot = %b", test_name, escape_port_set);
end else begin
    $display("[%0t]-%s PASSED", $time, test_name);
end
endtask

task check_count(input string test_name, input int expected);
if ($countones(adaptive_port_set) != expected) begin
    $error("%s FAILED: expected %0d, got %0d (%b)",
        test_name, expected, $countones(adaptive_port_set), adaptive_port_set);
end else begin
    $display("[%0t]-%s PASSED", $time, test_name);
end
endtask

task check_exact_port_adaptive(input string name, input logic [PORT_NUM-1:0] expected);
    if (adaptive_port_set !== expected) begin
        $error("%s ADAPTIVE FAILED: expected %b got %b",
            name, expected, adaptive_port_set);
    end 
    else begin
        $display("[%0t]-%s PASSED", $time, name);
    end
endtask

task check_exact_port_escape(input string name, input logic [PORT_NUM-1:0] expected);
    if (escape_port_set !== expected) begin
        $error("%s ESCAPE FAILED: expected %b got %b",
            name, expected, escape_port_set);
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
    port_e output_ports_escape, output_ports_adaptive;
    logic [PORT_NUM-1:0] expected_ports;

    dest_x = DEST_ADDR_SIZE_X'(MESH_SIZE_X-1); dest_y = DEST_ADDR_SIZE_Y'(0); // Should go EAST
    expected_ports = TB_EAST;
    #1; 
    output_ports_escape = port_e'(escape_port_set);
    output_ports_adaptive = port_e'(adaptive_port_set);
    $display("[%0t]-Eligible port: %s", $time, output_ports_escape.name());
    check_onehot("Test X movement one-hot (ESCAPE)");
    check_count("Test X movement count (ADAPTIVE)", 1);
    check_exact_port_escape("Test X movement EAST (ESCAPE)", expected_ports);
    check_exact_port_adaptive("Test X movement EAST (ADAPTIVE)", expected_ports);
    #1;
endtask

task test_y_movement_escape();
    port_e output_ports_escape, output_ports_adaptive;
    logic [PORT_NUM-1:0] expected_ports;

    dest_x = DEST_ADDR_SIZE_X'(0); dest_y = DEST_ADDR_SIZE_Y'(MESH_SIZE_Y-1); // Should go NORTH
    expected_ports = TB_NORTH;
    #1; 
    output_ports_escape = port_e'(escape_port_set);
    output_ports_adaptive = port_e'(adaptive_port_set);
    $display("[%0t]-Eligible port: %s", $time, output_ports_escape.name());
    check_onehot("Test Y movement one-hot (ESCAPE)");
    check_count("Test Y movement count (ADAPTIVE)", 1);
    check_exact_port_escape("Test Y movement NORTH (ESCAPE)", expected_ports);
    check_exact_port_adaptive("Test Y movement NORTH (ADAPTIVE)", expected_ports);
    #1;
endtask

task test_no_movement_escape();
    port_e output_ports_escape, output_ports_adaptive;
    logic [PORT_NUM-1:0] expected_ports;

    dest_x = DEST_ADDR_SIZE_X'(0); dest_y = DEST_ADDR_SIZE_Y'(0); // Should stay LOCAL
    expected_ports = TB_LOCAL;
    #1; 
    output_ports_escape = port_e'(escape_port_set);
    output_ports_adaptive = port_e'(adaptive_port_set);
    $display("[%0t]-Eligible port: %s", $time, output_ports_escape.name());
    check_onehot("Test No Movement one-hot (ESCAPE)");
    check_count("Test No Movement count (ADAPTIVE)", 1);
    check_exact_port_escape("Test No Movement - LOCAL (ESCAPE)", expected_ports);
    check_exact_port_adaptive("Test No Movement - LOCAL (ADAPTIVE)", expected_ports);
    #1;
endtask

//Adaptive VC Tests
task test_xy_movement_adaptive();
    port_e output_ports;
    logic [PORT_NUM-1:0] expected_ports_adaptive, expected_ports_escape;

    dest_x = DEST_ADDR_SIZE_X'(1); dest_y = DEST_ADDR_SIZE_Y'(MESH_SIZE_Y-1); // Should go EAST or NORTH
    expected_ports_adaptive = TB_EAST | TB_NORTH;
    expected_ports_escape = TB_EAST;
    #1;
    for (int i = 0; i < PORT_NUM; i++) begin
        if (adaptive_port_set[i]) begin
            output_ports = port_e'(1 << i);
            $display("[%0t]-Eligible port: %s", $time, output_ports.name());
        end
    end
    check_count("Test X and Y movement count (ADAPTIVE)", 2);
    check_onehot("Test X movement one-hot (ESCAPE)");
    check_exact_port_escape("Test X movement EAST (ESCAPE)", expected_ports_escape);
    check_exact_port_adaptive("Test X and Y movement EAST+NORTH (ADAPTIVE)", expected_ports_adaptive);
    #1;
endtask

task test_single_dimension_adaptive();
    port_e output_ports;
    logic [PORT_NUM-1:0] expected_ports;

    dest_x = DEST_ADDR_SIZE_X'(0); dest_y = DEST_ADDR_SIZE_Y'(MESH_SIZE_Y-1); // Should go NORTH only
    expected_ports = TB_NORTH;

    #1;
    for (int i = 0; i < PORT_NUM; i++) begin
        if (adaptive_port_set[i]) begin
            output_ports = port_e'(1 << i);
            $display("[%0t]-Eligible port: %s", $time, output_ports.name());
        end
    end
    check_count("Test Y movement count (ADAPTIVE)", 1);
    check_onehot("Test Y movement only one-hot (ESCAPE)");
    check_exact_port_escape("Test Y movement only NORTH (ESCAPE)", expected_ports);
    check_exact_port_adaptive("Test Y movement only NORTH (ADAPTIVE)", expected_ports);
    #1;
endtask

task 
test_no_movement_adaptive();
    port_e output_ports;
    logic [PORT_NUM-1:0] expected_ports;

    dest_x = DEST_ADDR_SIZE_X'(0); dest_y = DEST_ADDR_SIZE_Y'(0); // Should stay LOCAL
    expected_ports = TB_LOCAL;
    #1;
    for (int i = 0; i < PORT_NUM; i++) begin
        if (adaptive_port_set[i]) begin
            output_ports = port_e'(1 << i);
            $display("[%0t]-Eligible port: %s", $time, output_ports.name());
        end
    end
    check_count("Test No Movement count (ADAPTIVE)", 1);
    check_onehot("Test No Movement one-hot (ESCAPE)");
    check_exact_port_escape("Test No Movement - LOCAL (ESCAPE)", expected_ports);
    check_exact_port_adaptive("Test No Movement - LOCAL (ADAPTIVE)", expected_ports);
    #1;
endtask

task 
test_no_eligible_ports();
    port_e output_ports;
    logic [PORT_NUM-1:0] expected_ports;

    dest_x = DEST_ADDR_SIZE_X'($urandom_range(0, MESH_SIZE_X-1)); dest_y = DEST_ADDR_SIZE_Y'($urandom_range(0, MESH_SIZE_Y-1)); // Random destination
    expected_ports = '0; // Eligible ports based on destination
    #1;
    for (int i = 0; i < PORT_NUM; i++) begin
        if (adaptive_port_set[i]) begin
            output_ports = port_e'(1 << i);
            $display("[%0t]-Eligible port: %s", $time, output_ports.name());
        end
    end
    check_count("Test No Eligible Ports count (ADAPTIVE)", 0);
    check_exact_port_adaptive("Test No Eligible Ports (ADAPTIVE)", expected_ports);
    check_exact_port_escape("Test No Eligible Ports (ESCAPE)", expected_ports);
    #1;
endtask

initial begin
    #1;

    rc_valid = 1'b1; // Keep valid high for follwing tests
    test_x_movement_escape();
    test_y_movement_escape();
    test_no_movement_escape();
    test_xy_movement_adaptive();
    test_single_dimension_adaptive();
    test_no_movement_adaptive();
    rc_valid = 1'b0; // No valid input, should yield no eligible ports
    test_no_eligible_ports();

    $display("RC Corner basic tests PASSED");
    $finish;
end

endmodule
