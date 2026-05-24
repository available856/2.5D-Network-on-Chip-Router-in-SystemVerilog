`timescale 1ns / 1ps

import noc_params::*;


module tb_input_block;

parameter CLK_PERIOD = 10; // 100MHz clock

flit_t data [PORT_NUM-1:0];
logic [VC_NUM-1:0] valid_flit [PORT_NUM-1:0];
credits_t credit_return_i [PORT_NUM-1:0];
logic rst;
logic clk;
input_block2crossbar crossbar_if();
input_block2switch_allocator sa_if();
input_block2vc_allocator va_if();
logic [VC_NUM-1:0] vc_allocatable_o [PORT_NUM-1:0];
logic [VC_NUM-1:0] error_o [PORT_NUM-1:0];
vc_class_t [PORT_NUM-1:0][VC_NUM-1:0] vc_class_o;
credits_t credit_return_o [PORT_NUM-1:0];   

logic reset_done;

// -----------------------------
// DUT instance
// -----------------------------
input_block #(
    .BUFFER_SIZE(VC_DEPTH),
    .X_CURRENT(MESH_SIZE_X/2),
    .Y_CURRENT(MESH_SIZE_Y/2)
) dut (
    .data_i(data),
    .valid_flit_i(valid_flit),
    .credit_return_i(credit_return_i),
    .rst(rst),
    .clk(clk),
    .crossbar_if(crossbar_if),
    .sa_if(sa_if),
    .va_if(va_if),
    .vc_allocatable_o(vc_allocatable_o),
    .error_o(error_o),
    .vc_class_o(vc_class_o),
    .credit_return_o(credit_return_o)
);

initial begin
    clk = 0;
    rst = 0;
    reset_done = 0;
end

always #(CLK_PERIOD/2) clk = ~clk;

task reset_dut;
    begin
        @(negedge clk);
        data = '{default: '0};
        valid_flit = '{default: '0};
        credit_return_i = '{default: '0};
        va_if.vc_new = '{default: '{default: '0}};
        va_if.vc_valid = '{default: '0};
        sa_if.vc_sel = '{default: '0};
        sa_if.valid_port_sel = '{default: '0};
        for (int ip = 0; ip < PORT_NUM; ip++) begin
            for (int v = 0; v < VC_NUM; v++) begin
                va_if.port_new[ip][v] = LOCAL;
            end
        end
        @(negedge clk);
        rst = 1;
        repeat(2) @(negedge clk);
        rst = 0;
        @(posedge clk);
        #1; // Small delay to ensure reset is deasserted before starting the test
        reset_done = 1;
        $display("[%0t]-DUT reset complete\n------------------------------\n", $time);
        @(negedge clk);
    end
endtask


always @(posedge clk) begin
    port_t port;
    begin
        #2; // Small delay to allow outputs to stabilize after clock edge
        if (reset_done) begin
            $display("-[%0t] Credits Overall Details -----", $time);
            for (int dp = 0; dp < PORT_NUM; dp++) begin
                port = port_t'(dp);
                $display("Port %s,  Credits-VC0: %d, VC1: %d", port.name(), dut.credits_counter[dp][0], dut.credits_counter[dp][1]);
            end
            $display("------------------------------\n");
        end
    end
end


task receive_flit (input port_t port, input logic [VC_SIZE-1:0] vc_idx, input flit_label_t label, input logic [DEST_ADDR_SIZE_X-1:0] x_dest, input logic [DEST_ADDR_SIZE_Y-1:0] y_dest,
input logic [HEAD_PAYLOAD_SIZE-1:0] head_data, input logic [BODY_PAYLOAD_SIZE-1:0] body_data);
flit_t data_t;
logic [VC_NUM-1:0] vc_flit_valid;
begin
    data_t = '0;
    vc_flit_valid = '0;
    if (label == HEAD || label == HEADTAIL) begin 
        data_t = {label, x_dest, y_dest, head_data};
    end 
    else begin
        data_t = {label, body_data};
    end
    if (vc_idx == 1) begin
        vc_flit_valid[1] = 1'b1;
    end
    else begin
        vc_flit_valid[0] = 1'b1;
    end

    @(negedge clk);
    data[port] = data_t;
    valid_flit[port] = vc_flit_valid;

    @(posedge clk); #1; // Small delay to allow outputs to stabilize after clock edge
    if (label == HEAD || label == HEADTAIL) begin
        $display("[%0t]-Flit received on (port,VC) (%s,%d) with label=%s, x_dest=%d, y_dest=%d, data=0x%h", $time, port.name(), vc_idx, label.name(), x_dest, y_dest, head_data);
    end
    else begin
        $display("[%0t]-Flit received on (port,VC) (%s,%d) with label=%s, data=0x%h", $time, port.name(), vc_idx, label.name(), data[port]);
    end
    $display("Total flit: 0x%h", data[port]); 
    $display("------------------------------\n");  

    @(negedge clk);
    valid_flit[port] = 2'b00;
end
endtask

task select_va_port (input port_t current_port , input logic [VC_SIZE-1:0] vc_idx);
port_t last_port; 
begin
    for (int p = 0; p < PORT_NUM; p++) begin
        if (va_if.out_port_set[current_port][vc_idx][p]) begin
            last_port = port_t'(p);
        end
    end
    va_if.port_new[current_port][vc_idx] = last_port;
end
endtask

task select_va_down_vc (input port_t current_port , input logic [VC_SIZE-1:0] vc_idx);
begin
    if (vc_class_o[current_port][vc_idx] == ESCAPE) begin
        $display ("[%0t]-Current VC %d is an escape VC", $time, vc_idx);
        $display("------------------------------\n");
        va_if.vc_new[current_port][vc_idx] = 0; // Assign escape VC
    end
    else begin
        $display ("[%0t]-Current VC %d is an adaptive VC", $time, vc_idx);
        $display("------------------------------\n");
        va_if.vc_new[current_port][vc_idx] = VC_SIZE'($urandom_range(0, VC_NUM-1)); // Randomly assign a downstream VC for testing
    end 
end
endtask

task virtual_channel_allocation (input port_t current_port, input logic [VC_SIZE-1:0] vc_idx); 
begin
    @(negedge clk);
    if (va_if.vc_request[current_port][vc_idx]) begin
        $display("[%0t]-Responding to VA request for VC %d", $time, vc_idx);
        select_va_port(current_port, vc_idx);
        select_va_down_vc(current_port, vc_idx);
        va_if.vc_valid[current_port][vc_idx] = 1'b1;
        #1; // Small delay to allow outputs to stabilize after clock edge
        $display("[%0t]-Port_new=%s, va_new_vc=%d", $time, va_if.port_new[current_port][vc_idx].name(), va_if.vc_new[current_port][vc_idx]);
        $display("------------------------------\n");
        @(negedge clk);
        va_if.vc_valid[current_port][vc_idx] = 1'b0;
    end
end
endtask

task switch_allocation (input port_t current_port, input logic [VC_SIZE-1:0] vc_idx); 
begin
    @(negedge clk);
    if (sa_if.switch_request[current_port][vc_idx] && sa_if.credits_exist[sa_if.out_port[current_port][vc_idx]][sa_if.downstream_vc[current_port][vc_idx]]) begin
        $display("[%0t]-Responding to SA request for port %s & VC %d", $time, current_port.name(), vc_idx);
        $display("------------------------------\n");

        sa_if.vc_sel[current_port] = vc_idx; // Select the requesting VC for switch allocation
        sa_if.downstream_vc[current_port][vc_idx] = va_if.vc_new[current_port][vc_idx]; // Use the same downstream VC assigned during VA for testing
        sa_if.valid_port_sel[current_port] = 1'b1;

        #1; // Small delay to allow outputs to stabilize after clock edge
        $display("[%0t]-Selected upstream (port: %s, VC: %d) for SA and flit=0x%h", $time, current_port.name(), sa_if.vc_sel[current_port], crossbar_if.flit[current_port]);
        $display("------------------------------\n");

        @(negedge clk);
        sa_if.valid_port_sel[current_port] = 1'b0;
    end
    else if (sa_if.switch_request[current_port][vc_idx] && !sa_if.credits_exist[sa_if.out_port[current_port][vc_idx]][sa_if.downstream_vc[current_port][vc_idx]]) begin
        $display("[%0t]-SA request for port %s & VC %d cannot be granted due to credit underflow", $time, current_port.name(), vc_idx);
        $display("------------------------------\n");
    end
end
endtask

task headtail_flit_simulation (input port_t current_port, input logic [VC_SIZE-1:0] vc_idx, input logic [DEST_ADDR_SIZE_X-1:0] x_dest, input logic [DEST_ADDR_SIZE_Y-1:0] y_dest);
begin
    receive_flit(current_port, vc_idx, HEADTAIL, x_dest, y_dest, HEAD_PAYLOAD_SIZE'({$urandom, $urandom}), 0);

    wait(va_if.vc_request[current_port][vc_idx] == 1'b1);
    $display("[%0t]-VA request for VC %d observed on %s port \n------------------------------\n", $time, vc_idx, current_port.name());
    virtual_channel_allocation(current_port, vc_idx);

    wait(sa_if.switch_request[current_port][vc_idx] == 1'b1);
    $display("[%0t]-SA request for VC %d observed on %s port \n------------------------------\n", $time, vc_idx, current_port.name());
    switch_allocation(current_port, vc_idx);
    
    @(negedge clk);
    credit_return_i[sa_if.out_port[current_port][vc_idx]][sa_if.downstream_vc[current_port][vc_idx]] = 1'b1; // Simulate credit return for the downstream VC after SA
    $display("[%0t]-Credit return for downstream port %s and VC %d\n------------------------------\n", $time, sa_if.out_port[current_port][vc_idx].name(), sa_if.downstream_vc[current_port][vc_idx]);
    @(negedge clk);
    credit_return_i[sa_if.out_port[current_port][vc_idx]][sa_if.downstream_vc[current_port][vc_idx]] = 1'b0; //Deassert credtit

    repeat(2) @(posedge clk);
end
endtask

task packet_simulation (input port_t current_port, input logic [VC_SIZE-1:0] vc_idx, input logic [DEST_ADDR_SIZE_X-1:0] x_dest, input logic [DEST_ADDR_SIZE_Y-1:0] y_dest);
begin
    receive_flit(current_port, vc_idx, HEAD, x_dest, y_dest, HEAD_PAYLOAD_SIZE'({$urandom, $urandom}), 0);

    wait(va_if.vc_request[current_port][vc_idx] == 1'b1);
    $display("[%0t]-VA request for VC %d observed on %s port \n------------------------------\n", $time, vc_idx, current_port.name());
    virtual_channel_allocation(current_port, vc_idx);

    wait(sa_if.switch_request[current_port][vc_idx] == 1'b1);
    $display("[%0t]-SA request for VC %d observed on %s port \n------------------------------\n", $time, vc_idx, current_port.name());
    switch_allocation(current_port, vc_idx);

    repeat (2) begin
        receive_flit(current_port, vc_idx, BODY, $urandom_range(0, MESH_SIZE_X-1), $urandom_range(0, MESH_SIZE_Y-1), 0, BODY_PAYLOAD_SIZE'({$urandom, $urandom}));
        switch_allocation(current_port, vc_idx);
    end

    receive_flit(current_port, vc_idx, TAIL, $urandom_range(0, MESH_SIZE_X-1), $urandom_range(0, MESH_SIZE_Y-1), 0, BODY_PAYLOAD_SIZE'({$urandom, $urandom}));
    switch_allocation(current_port, vc_idx);
    
    repeat (4) begin
        @(negedge clk);
        credit_return_i[sa_if.out_port[current_port][vc_idx]][sa_if.downstream_vc[current_port][vc_idx]] = 1'b1; // Simulate credit return for the downstream VC after SA
        $display("[%0t]-Credit return for downstream port %s and VC %d\n------------------------------\n", $time, sa_if.out_port[current_port][vc_idx].name(), sa_if.downstream_vc[current_port][vc_idx]);
        @(negedge clk);
        credit_return_i[sa_if.out_port[current_port][vc_idx]][sa_if.downstream_vc[current_port][vc_idx]] = 1'b0; //Deassert credtit
    end

    repeat(2) @(posedge clk);
end
endtask

task packet_credits_underflow_overflow (input port_t current_port, input logic [VC_SIZE-1:0] vc_idx, input logic [DEST_ADDR_SIZE_X-1:0] x_dest, input logic [DEST_ADDR_SIZE_Y-1:0] y_dest);
begin
    receive_flit(current_port, vc_idx, HEAD, x_dest, y_dest, HEAD_PAYLOAD_SIZE'({$urandom, $urandom}), 0);

    wait(va_if.vc_request[current_port][vc_idx] == 1'b1);
    $display("[%0t]-VA request for VC %d observed on %s port \n------------------------------\n", $time, vc_idx, current_port.name());
    virtual_channel_allocation(current_port, vc_idx);

    wait(sa_if.switch_request[current_port][vc_idx] == 1'b1);
    $display("[%0t]-SA request for VC %d observed on %s port \n------------------------------\n", $time, vc_idx, current_port.name());
    switch_allocation(current_port, vc_idx);

    repeat (2) begin
        receive_flit(current_port, vc_idx, BODY, $urandom_range(0, MESH_SIZE_X-1), $urandom_range(0, MESH_SIZE_Y-1), 0, BODY_PAYLOAD_SIZE'({$urandom, $urandom}));
        switch_allocation(current_port, vc_idx);
    end

    receive_flit(current_port, vc_idx, BODY, $urandom_range(0, MESH_SIZE_X-1), $urandom_range(0, MESH_SIZE_Y-1), 0, BODY_PAYLOAD_SIZE'({$urandom, $urandom}));
    switch_allocation(current_port, vc_idx);

    receive_flit(current_port, vc_idx, TAIL, $urandom_range(0, MESH_SIZE_X-1), $urandom_range(0, MESH_SIZE_Y-1), 0, BODY_PAYLOAD_SIZE'({$urandom, $urandom}));
    switch_allocation(current_port, vc_idx); // This SA should fail due to credit underflow, and we can check if the error signal is asserted for this VC

    @(negedge clk);
    credit_return_i[sa_if.out_port[current_port][vc_idx]][sa_if.downstream_vc[current_port][vc_idx]] = 1'b1; // Simulate credit return for the downstream VC after SA
    $display("[%0t]-Credit return for downstream port %s and VC %d\n------------------------------\n", $time, sa_if.out_port[current_port][vc_idx].name(), sa_if.downstream_vc[current_port][vc_idx]);
    @(negedge clk);
    credit_return_i[sa_if.out_port[current_port][vc_idx]][sa_if.downstream_vc[current_port][vc_idx]] = 1'b0; //Deassert credtit

    switch_allocation(current_port, vc_idx); // Attempt another SA after credit return to see if the next flit can be processed

    repeat (4) begin
        @(negedge clk);
        credit_return_i[sa_if.out_port[current_port][vc_idx]][sa_if.downstream_vc[current_port][vc_idx]] = 1'b1; // Simulate credit return for the downstream VC after SA
        $display("[%0t]-Credit return for downstream port %s and VC %d\n------------------------------\n", $time, sa_if.out_port[current_port][vc_idx].name(), sa_if.downstream_vc[current_port][vc_idx]);
        @(negedge clk);
        credit_return_i[sa_if.out_port[current_port][vc_idx]][sa_if.downstream_vc[current_port][vc_idx]] = 1'b0; //Deassert credtit
    end

    repeat(2) @(posedge clk);
end
endtask

initial begin
    reset_dut();
    
    headtail_flit_simulation(EAST, 1, 1, 1);
    packet_simulation(NORTH, 0, 2, 1);
    packet_credits_underflow_overflow(WEST, 1, 3, 3);

    $finish;
end

endmodule