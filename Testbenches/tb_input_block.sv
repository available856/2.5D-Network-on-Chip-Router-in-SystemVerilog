`timescale 1ns / 1ps

import noc_params::*;


module tb_input_block;

parameter CLK_PERIOD = 10; // 100MHz clock

flit_t data [PORT_NUM-1:0];
logic valid_flit [PORT_NUM-1:0];
credits_t credit_return_i [PORT_NUM-1:0];
logic rst;
logic clk;
input_block2crossbar crossbar_if();
input_block2switch_allocator sa_if();
input_block2vc_allocator va_if();
logic [VC_NUM-1:0] vc_allocatable_o [PORT_NUM-1:0];
logic [VC_NUM-1:0] error_o [PORT_NUM-1:0];
credits_t credit_return_o [PORT_NUM-1:0];   

logic reset_done;
flit_t expected_flit[PORT_NUM][VC_NUM][16];
int written[PORT_NUM][VC_NUM], consumed[PORT_NUM][VC_NUM];
int blocked_cycles = 0;

//For simultaneous packet test
port_t current_port [1:0];
logic [VC_SIZE-1:0] vc_idx [1:0];
logic [DEST_ADDR_SIZE_X-1:0] x_dest [1:0];
logic [DEST_ADDR_SIZE_Y-1:0] y_dest [1:0];

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


// Keep one small expected-data list per input VC; the DUT rewrites only vc_id.
always @(posedge clk) begin
    if (rst) begin
        for (int p = 0; p < PORT_NUM; p++) for (int v = 0; v < VC_NUM; v++) begin
            written[p][v] = 0; consumed[p][v] = 0;
        end
    end
    else if (reset_done) begin
        for (int p = 0; p < PORT_NUM; p++) begin
            if (error_o[p] != '0) $fatal(1, "Input Block error on port %0d", p);
            if (valid_flit[p]) begin
                int v; v = int'(data[p].vc_id);
                if (written[p][v] == 16) $fatal(1, "Expected-data list full");
                expected_flit[p][v][written[p][v]] = data[p];
                written[p][v]++;
            end
            for (int v = 0; v < VC_NUM; v++) begin
                if (sa_if.switch_request[p][v] && !sa_if.credits_exist[sa_if.out_port[p][v]][sa_if.downstream_vc[p][v]])
                    blocked_cycles++;
            end
            if (sa_if.valid_port_sel[p]) begin
                flit_t expected;
                int v; v = int'(sa_if.vc_sel[p]);
                if (!sa_if.switch_request[p][v] || consumed[p][v] == written[p][v] ||
                    !sa_if.credits_exist[sa_if.out_port[p][v]][sa_if.downstream_vc[p][v]])
                    $fatal(1, "Invalid switch grant in Input Block test");
                expected = expected_flit[p][v][consumed[p][v]];
                expected.vc_id = sa_if.downstream_vc[p][v];
                if (crossbar_if.flit[p] !== expected) $fatal(1, "Input Block payload/order mismatch");
                consumed[p][v]++;
            end
        end
    end
end

initial begin
    #(CLK_PERIOD*250);
    $fatal(1, "Input Block test timed out");
end


task receive_flit (input port_t port, input logic [VC_SIZE-1:0] vc_idx, input flit_label_t label, input logic [DEST_ADDR_SIZE_X-1:0] x_dest, input logic [DEST_ADDR_SIZE_Y-1:0] y_dest,
input logic [HEAD_PAYLOAD_SIZE-1:0] head_data, input logic [BODY_PAYLOAD_SIZE-1:0] body_data);
flit_t data_t;
begin
    data_t = '0;
    if (label == HEAD || label == HEADTAIL) begin 
        data_t = {label, vc_idx, x_dest, y_dest, head_data};
    end 
    else begin
        data_t = {label, vc_idx, body_data};
    end


    @(negedge clk);
    data[port] = data_t;
    valid_flit[port] = 1'b1;

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
    valid_flit[port] = 1'b0;
end
endtask

task select_va_port (input port_t current_port , input logic [VC_SIZE-1:0] vc_idx);
port_t last_port; 
begin
    last_port = LOCAL;
    // The updated interface provides separate adaptive and XY escape masks.
    for (int p = 0; p < PORT_NUM; p++) begin
        if ((vc_idx == ESCAPE && va_if.escape_port_set[current_port][vc_idx][p]) ||
            (vc_idx == ADAPTIVE && va_if.adaptive_port_set[current_port][vc_idx][p])) begin
            last_port = port_t'(p);
        end
    end
    va_if.port_new[current_port][vc_idx] = last_port;
end
endtask

task select_va_down_vc (input port_t current_port , input logic [VC_SIZE-1:0] vc_idx);
begin
    if (vc_idx == ESCAPE) begin
        $display ("[%0t]-Current VC %d is an escape VC", $time, vc_idx);
        $display("------------------------------\n");
        va_if.vc_new[current_port][vc_idx] = 0; // Assign escape VC
    end
    else begin
        $display ("[%0t]-Current VC %d is an adaptive VC", $time, vc_idx);
        $display("------------------------------\n");
        va_if.vc_new[current_port][vc_idx] = ADAPTIVE; // Basic VA stub keeps this packet adaptive
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
        if (sa_if.out_port[current_port][vc_idx] !== va_if.port_new[current_port][vc_idx] ||
            sa_if.downstream_vc[current_port][vc_idx] !== va_if.vc_new[current_port][vc_idx])
            $fatal(1, "VA grant was not saved by the input VC");
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
        // downstream_vc is driven by the input block after VA, not by this stub.
        sa_if.valid_port_sel[current_port] = 1'b1;

        #1; // Small delay to allow outputs to stabilize after clock edge
        if (crossbar_if.flit[current_port].vc_id !== sa_if.downstream_vc[current_port][vc_idx])
            $fatal(1, "Crossbar flit has the wrong downstream VC");
        $display("[%0t]-Selected upstream (port: %s, VC: %d) for SA and flit=0x%h", $time, current_port.name(), sa_if.vc_sel[current_port], crossbar_if.flit[current_port]);
        $display("------------------------------\n");

        @(negedge clk);
        sa_if.valid_port_sel[current_port] = 1'b0;
        if (!credit_return_o[current_port][vc_idx])
            $fatal(1, "Switch grant did not dequeue a flit and return credit");
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

task simultaneous_va (input port_t current_port [1:0], input logic [VC_SIZE-1:0] vc_idx [1:0]); 
begin
    @(negedge clk);
    if (va_if.vc_request[current_port[0]][vc_idx[0]] && va_if.vc_request[current_port[1]][vc_idx[1]]) begin        
        for (int i = 0; i < 2; i++) begin
            $display("[%0t]-Responding to VA request for (port, VC) (%s, %d)", $time, current_port[i].name(), vc_idx[i]);
            select_va_port(current_port[i], vc_idx[i]);        
            select_va_down_vc(current_port[i], vc_idx[i]);                
            va_if.vc_valid[current_port[i]][vc_idx[i]] = 1'b1;
        end
               
        
        #1; // Small delay to allow outputs to stabilize after clock edge

        for (int i = 0; i < 2; i++) begin
            $display("[%0t]-Port_new=%s, va_new_vc=%d", $time, va_if.port_new[current_port[i]][vc_idx[i]].name(), va_if.vc_new[current_port[i]][vc_idx[i]]);
            $display("------------------------------\n");
        end

        @(negedge clk);
        for (int i = 0; i < 2; i++) begin
            va_if.vc_valid[current_port[i]][vc_idx[i]] = 1'b0;
        end
    end
    else $error("[%0t]-Simultaneous VA requests not observed for the specified ports and VCs", $time);
end
endtask

task simultaneous_sa (input port_t current_port [1:0], input logic [VC_SIZE-1:0] vc_idx [1:0]); 
begin
    @(negedge clk);
    if ( (sa_if.switch_request[current_port[0]][vc_idx[0]] && sa_if.credits_exist[sa_if.out_port[current_port[0]][vc_idx[0]]][sa_if.downstream_vc[current_port[0]][vc_idx[0]]]) && (sa_if.switch_request[current_port[1]][vc_idx[1]] && sa_if.credits_exist[sa_if.out_port[current_port[1]][vc_idx[1]]][sa_if.downstream_vc[current_port[1]][vc_idx[1]]]) ) begin
        for (int i = 0; i < 2; i++) begin
            $display("[%0t]-Responding to SA request for port %s & VC %d", $time, current_port[i].name(), vc_idx[i]);
            $display("------------------------------\n");

            sa_if.vc_sel[current_port[i]] = vc_idx[i]; // Select the requesting VC for switch allocation
            // The input block already saved the downstream VC during VA.
            sa_if.valid_port_sel[current_port[i]] = 1'b1;
        end

        #1; // Small delay to allow outputs to stabilize after clock edge

        for (int i = 0; i < 2; i++) begin
            $display("[%0t]-Selected upstream (port: %s, VC: %d) for SA and flit=0x%h", $time, current_port[i].name(), sa_if.vc_sel[current_port[i]], crossbar_if.flit[current_port[i]]);
            $display("------------------------------\n");
        end
        
        @(negedge clk);
        for (int i = 0; i < 2; i++) begin
            sa_if.valid_port_sel[current_port[i]] = 1'b0;
        end
    end

    else $error("[%0t]-Simultaneous SA requests with valid credits not observed for the specified ports and VCs", $time);
    
end
endtask

task simultaneous_receive_flit (input port_t port[ 1:0], input logic [VC_SIZE-1:0] vc_idx[1:0], input flit_label_t label [1:0], input logic [DEST_ADDR_SIZE_X-1:0] x_dest [1:0], input logic [DEST_ADDR_SIZE_Y-1:0] y_dest [1:0],
input logic [HEAD_PAYLOAD_SIZE-1:0] head_data [1:0], input logic [BODY_PAYLOAD_SIZE-1:0] body_data [1:0]);
flit_t data_t [1:0];
begin
    for (int i = 0; i < 2; i++) begin
        data_t[i] = '0;
        
        if (label[i] == HEAD || label[i] == HEADTAIL) begin 
            data_t[i] = {label[i], vc_idx[i], x_dest[i], y_dest[i], head_data[i]};
        end 
        else begin
            data_t[i] = {label[i], vc_idx[i], body_data[i]};
        end
    end

    @(negedge clk);
    for (int i = 0; i < 2; i++) begin
        data[port[i]] = data_t[i];
        valid_flit[port[i]] = 1'b1;
    end

    @(posedge clk); #1; // Small delay to allow outputs to stabilize after clock edge
    for (int i = 0; i < 2; i++) begin
        if (label[i] == HEAD || label[i] == HEADTAIL) begin
            $display("[%0t]-Flit received on (port,VC) (%s,%d) with label=%s, x_dest=%d, y_dest=%d, data=0x%h", $time, port[i].name(), vc_idx[i], label[i].name(), x_dest[i], y_dest[i], head_data[i]);
        end
        else begin
            $display("[%0t]-Flit received on (port,VC) (%s,%d) with label=%s, data=0x%h", $time, port[i].name(), vc_idx[i], label[i].name(), data[port[i]]);
        end
        $display("Total flit: 0x%h", data[port[i]]); 
        $display("------------------------------\n");  
    end

    @(negedge clk);
    for (int i = 0; i < 2; i++) begin
        valid_flit[port[i]] = 1'b0;
    end
end
endtask

task simultaneous_packets (input port_t current_port [1:0], input logic [VC_SIZE-1:0] vc_idx [1:0], input logic [DEST_ADDR_SIZE_X-1:0] x_dest [1:0], input logic [DEST_ADDR_SIZE_Y-1:0] y_dest [1:0]);
begin
    flit_label_t label [1:0];
    logic [HEAD_PAYLOAD_SIZE-1:0] head_data [1:0];
    logic [BODY_PAYLOAD_SIZE-1:0] body_data [1:0];
    logic [DEST_ADDR_SIZE_X-1:0] x_dest_body [1:0];
    logic [DEST_ADDR_SIZE_Y-1:0] y_dest_body [1:0];

    for (int i = 0; i < 2; i++) begin
        label[i] = HEAD;
        head_data[i] = HEAD_PAYLOAD_SIZE'({$urandom, $urandom});
        body_data[i] = '0; // No body data for head flit
        x_dest_body[i] = '0;
        y_dest_body[i] = '0;
    end

    simultaneous_receive_flit(current_port, vc_idx, label, x_dest, y_dest, head_data, body_data);

    for (int i = 0; i < 2; i++) begin
        wait(va_if.vc_request[current_port[i]][vc_idx[i]] == 1'b1);
        $display("[%0t]-VA request for VC %d observed on %s port \n------------------------------\n", $time, vc_idx[i], current_port[i].name());
    end
    simultaneous_va(current_port, vc_idx);

    for (int i = 0; i < 2; i++) begin
        wait(sa_if.switch_request[current_port[i]][vc_idx[i]] == 1'b1);
        $display("[%0t]-SA request for VC %d observed on %s port \n------------------------------\n", $time, vc_idx[i], current_port[i].name());
    end
    simultaneous_sa(current_port, vc_idx);

    for (int i = 0; i < 2; i++) begin
        label[i] = BODY;
        head_data[i] = '0; // No head data for body flit
        body_data[i] = BODY_PAYLOAD_SIZE'({$urandom, $urandom});
        x_dest_body[i] = $urandom_range(0, MESH_SIZE_X-1);
        y_dest_body[i] = $urandom_range(0, MESH_SIZE_Y-1);
    end
    repeat (2) begin
        simultaneous_receive_flit(current_port, vc_idx, label, x_dest_body, y_dest_body, head_data, body_data);
        simultaneous_sa(current_port, vc_idx);
    end

    for (int i = 0; i < 2; i++) begin
        label[i] = TAIL;
        head_data[i] = '0; // No head data for body flit
        body_data[i] = BODY_PAYLOAD_SIZE'({$urandom, $urandom});
        x_dest_body[i] = $urandom_range(0, MESH_SIZE_X-1);
        y_dest_body[i] = $urandom_range(0, MESH_SIZE_Y-1);
    end
    simultaneous_receive_flit(current_port, vc_idx, label, x_dest_body, y_dest_body, head_data, body_data);
    simultaneous_sa(current_port, vc_idx);

    repeat (4) begin
        @(negedge clk);
        for (int i = 0; i < 2; i++) begin
            credit_return_i[sa_if.out_port[current_port[i]][vc_idx[i]]][sa_if.downstream_vc[current_port[i]][vc_idx[i]]] = 1'b1; // Simulate credit return for the downstream VC after SA
            $display("[%0t]-Credit return for downstream port %s and VC %d\n------------------------------\n", $time, sa_if.out_port[current_port[i]][vc_idx[i]].name(), sa_if.downstream_vc[current_port[i]][vc_idx[i]]);
        end
        @(negedge clk);
        for (int i = 0; i < 2; i++) begin
            credit_return_i[sa_if.out_port[current_port[i]][vc_idx[i]]][sa_if.downstream_vc[current_port[i]][vc_idx[i]]] = 1'b0; //Deassert credtit
        end
    end

    repeat(2) @(posedge clk);
end
endtask


initial begin
    reset_dut();
    
    headtail_flit_simulation(EAST, 1, 0, 1);
    packet_simulation(NORTH, 0, 1, 0);
    packet_credits_underflow_overflow(WEST, 1, 0, 0);
    current_port[0] = SOUTH; current_port[1] = EAST;
    vc_idx[0] = 0; vc_idx[1] = 1;
    x_dest[0] = 1; y_dest[0] = 0;
    x_dest[1] = 0; y_dest[1] = 0;
    simultaneous_packets(current_port, vc_idx, x_dest, y_dest);

    @(negedge clk);
    for (int p = 0; p < PORT_NUM; p++) for (int v = 0; v < VC_NUM; v++) begin
        if (consumed[p][v] != written[p][v]) $fatal(1, "Input Block did not drain");
        if (dut.credits_counter[p][v] != VC_DEPTH) $fatal(1, "Credits were not restored");
    end
    if (blocked_cycles == 0) $fatal(1, "Credit blocking was not exercised");
    $display("Input Block basic tests PASSED");
    $finish;
end

endmodule
