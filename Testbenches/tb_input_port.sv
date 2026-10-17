`timescale 1ns/1ps

import noc_params::*;

module tb_input_port;

parameter CLK_PERIOD = 10; // 100MHz clock

flit_t data_i;
logic valid_flit_i;
port_t [VC_NUM-1:0] port_new_i;
logic [VC_SIZE-1:0] sa_sel_vc_i;
logic [VC_SIZE-1:0] va_new_vc_i [VC_NUM-1:0];
logic [VC_NUM-1:0] va_valid_i;
logic sa_valid_i;
logic clk;
logic rst;
flit_t xb_flit_o;
logic [VC_NUM-1:0] is_allocatable_vc_o;
logic [VC_NUM-1:0] va_request_o;
logic sa_request_o [VC_NUM-1:0];
logic [VC_SIZE-1:0] sa_downstream_vc_o [VC_NUM-1:0];
port_t [VC_NUM-1:0] out_port_o;
logic [VC_NUM-1:0][PORT_NUM-1:0] adaptive_port_set_o;
logic [VC_NUM-1:0][PORT_NUM-1:0] escape_port_set_o;
credits_t credit_return_o;
logic [VC_NUM-1:0] is_full_o;
logic [VC_NUM-1:0] is_empty_o;
logic [VC_NUM-1:0] error_o;
//vc_class_t [VC_NUM-1:0] vc_class_o;

logic reset_done;
flit_t expected_flit[VC_NUM][16];
int written[VC_NUM], consumed[VC_NUM];

input_port #(
    .BUFFER_SIZE(VC_DEPTH),
    .X_CURRENT(MESH_SIZE_X/2),
    .Y_CURRENT(MESH_SIZE_Y/2)
) dut (
    .data_i(data_i),
    .valid_flit_i(valid_flit_i),
    .port_new_i(port_new_i),
    .rst(rst),
    .clk(clk),
    .sa_sel_vc_i(sa_sel_vc_i),
    .va_new_vc_i(va_new_vc_i),
    .va_valid_i(va_valid_i),
    .sa_valid_i(sa_valid_i),
    .xb_flit_o(xb_flit_o),
    .is_allocatable_vc_o(is_allocatable_vc_o),
    .va_request_o(va_request_o),
    .sa_request_o(sa_request_o),
    .sa_downstream_vc_o(sa_downstream_vc_o),
    .out_port_o(out_port_o),
    .escape_port_set_o(escape_port_set_o),
    .adaptive_port_set_o(adaptive_port_set_o),
    .credit_return_o(credit_return_o),
    .is_full_o(is_full_o),
    .is_empty_o(is_empty_o),
    .error_o(error_o)//,
    //.vc_class_o(vc_class_o)
);

initial begin
    clk = 0;
    rst = 0;
    reset_done = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

task reset_dut;
begin
    @(negedge clk);
    data_i = '0;
    valid_flit_i = '0;
    port_new_i = '0;
    sa_sel_vc_i = '0;
    va_new_vc_i = '{default:'0};
    va_valid_i = '0;
    sa_valid_i = 0;
    @(negedge clk) rst = 1;
    repeat(2) @(negedge clk);
    rst = 0;
    @(posedge clk);
    #1; // Small delay to ensure reset is deasserted before starting the test
    reset_done = 1;
    @(negedge clk);
end
endtask

task receive_flit_simple (input logic [VC_SIZE-1:0] vc_idx, input flit_label_t label, input logic [DEST_ADDR_SIZE_X-1:0] x_dest, input logic [DEST_ADDR_SIZE_Y-1:0] y_dest,
input logic [HEAD_PAYLOAD_SIZE-1:0] head_data, input logic [BODY_PAYLOAD_SIZE-1:0] body_data);
flit_t data;
begin
    data = '0;
    if (label == HEAD || label == HEADTAIL) begin 
        data = {label, vc_idx, x_dest, y_dest, head_data};
    end 
    else begin
        data = {label, vc_idx, body_data};
    end

    @(negedge clk);
    data_i = data;
    valid_flit_i = 1'b1;

    @(posedge clk); #1; // Small delay to allow outputs to stabilize after clock edge
    if (label == HEAD || label == HEADTAIL) begin
        $display("[%0t]-Flit received with label=%s, x_dest=%d, y_dest=%d, data=0x%h", $time, label.name(), x_dest, y_dest, head_data);
    end
    else begin
        $display("[%0t]-Flit received with label=%s, data=0x%h", $time, label.name(), data_i);
    end
    $display("Total flit: 0x%h", data);   

    @(negedge clk);
    valid_flit_i = 1'b0;
end
endtask

task virtual_channel_allocation (input logic [VC_SIZE-1:0] vc_idx); 
begin
    // Safely block and wait for the router to assert the VA request
    while (!va_request_o[vc_idx]) @(posedge clk);
    
    @(negedge clk);
    
    $display("[%0t]-Responding to VA request for VC %d", $time, vc_idx);
    select_va_port(vc_idx);
    select_va_down_vc(vc_idx);
    va_valid_i[vc_idx] = 1'b1;

    #1; // Small delay to allow outputs to stabilize after clock edge
    $display("[%0t]-Port_new=%s, va_new_vc=%d", $time, port_new_i[vc_idx].name(), va_new_vc_i[vc_idx]);

    @(negedge clk);
    va_valid_i[vc_idx] = 1'b0;

end
endtask

task switch_allocation (input logic [VC_SIZE-1:0] vc_idx); 
begin
    // Safely block and wait for the router to assert the SA request
    while (!sa_request_o[vc_idx]) @(posedge clk);

    @(negedge clk);
    
    $display("[%0t]-Responding to SA request for VC %d", $time, vc_idx);
    sa_sel_vc_i = vc_idx; // Select the requesting VC for switch allocation

    //sa_downstream_vc_o[vc_idx] = va_new_vc_i[vc_idx]; // Use the same downstream VC assigned during VA for testing
    sa_valid_i = 1'b1;

    #1; // Small delay to allow outputs to stabilize after clock edge
    $display("[%0t]-Selected upstream VC %d for SA and xb_flit_o=0x%h", $time, sa_sel_vc_i, xb_flit_o);

    @(negedge clk);
    sa_valid_i = 1'b0;
end
endtask



task select_va_port (input logic [VC_SIZE-1:0] vc_idx);
port_t last_port; 
begin
    last_port = LOCAL;
    // The grant's VC class selects the matching route mask.
    for (int i = 0; i < PORT_NUM; i++) begin
        if ((vc_idx == ESCAPE && escape_port_set_o[vc_idx][i]) ||
            (vc_idx == ADAPTIVE && adaptive_port_set_o[vc_idx][i])) begin
            last_port = port_t'(i);
        end
    end
    port_new_i[vc_idx] = last_port;
end
endtask

task select_va_down_vc (input logic [VC_SIZE-1:0] vc_idx);
begin
    if (vc_idx == ESCAPE) begin
        va_new_vc_i[vc_idx] = 0; // Assign escape VC
    end
    else begin
        va_new_vc_i[vc_idx] = ADAPTIVE; // Basic grant keeps this packet adaptive
    end 
end
endtask



// Check injected data against the selected FWFT flit before it is dequeued.
always @(posedge clk) begin
    if (rst) begin
        for (int v = 0; v < VC_NUM; v++) begin written[v] = 0; consumed[v] = 0; end
    end
    else if (reset_done) begin
        if (error_o != '0) $fatal(1, "Unexpected input port error");
        if (valid_flit_i) begin
            int v; v = int'(data_i.vc_id);
            if (is_full_o[v] || written[v] == 16) $fatal(1, "Input buffer/scoreboard full");
            expected_flit[v][written[v]] = data_i;
            written[v]++;
        end
        if (sa_valid_i) begin
            flit_t expected;
            int v; v = int'(sa_sel_vc_i);
            if (!sa_request_o[v] || consumed[v] == written[v]) $fatal(1, "Unexpected switch grant");
            expected = expected_flit[v][consumed[v]];
            expected.vc_id = sa_downstream_vc_o[v];
            if (xb_flit_o !== expected) $fatal(1, "Input port payload/order mismatch");
            if (out_port_o[v] !== port_new_i[v]) $fatal(1, "Allocated route was not saved");
            consumed[v]++;
            #1;
            if (!credit_return_o[v]) $fatal(1, "Dequeue did not return credit");
            if ((expected.flit_label == TAIL || expected.flit_label == HEADTAIL) && !is_allocatable_vc_o[v])
                $fatal(1, "Tail did not release the input VC");
        end
    end
end

initial begin
    #(CLK_PERIOD*150);
    $fatal(1, "Input Port test timed out");
end


initial begin
    reset_dut();

    //Receive a simple flit, 1st packet
    receive_flit_simple(1, HEADTAIL, 0, 1, HEAD_PAYLOAD_SIZE'({$urandom(), $urandom()}), 0);
    virtual_channel_allocation(1);
    $display("[%0t]-SA request for VC 1 observed", $time);    
    switch_allocation(1); 

    //2nd packet
    receive_flit_simple(1, HEAD, 0, 0, HEAD_PAYLOAD_SIZE'({$urandom(), $urandom()}), 0);
    virtual_channel_allocation(1);
    receive_flit_simple(1, BODY, 0, 0, 0, BODY_PAYLOAD_SIZE'({$urandom(), $urandom()}));
    receive_flit_simple(1, BODY, 0, 0, 0, BODY_PAYLOAD_SIZE'({$urandom(), $urandom()}));
    receive_flit_simple(1, TAIL, 0, 0, 0, BODY_PAYLOAD_SIZE'({$urandom(), $urandom()}));
    repeat (4) switch_allocation(1);

// Exercise the escape input VC as well as the adaptive one above.
    receive_flit_simple(0, HEADTAIL, 0, 0, HEAD_PAYLOAD_SIZE'($urandom), 0);
    virtual_channel_allocation(0);
    switch_allocation(0);
    repeat (2) @(negedge clk);
    for (int v = 0; v < VC_NUM; v++) begin
        if (written[v] == 0 || consumed[v] != written[v] || !is_empty_o[v])
            $fatal(1, "Input VC did not drain");
    end
    $display("Input Port basic tests PASSED");
    $finish;
end
  
endmodule
