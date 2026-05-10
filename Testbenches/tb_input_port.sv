`timescale 1ns/1ps

import noc_params::*;

module tb_input_port;

parameter CLK_PERIOD = 10; // 100MHz clock

flit_t data_i;
logic [VC_NUM-1:0] valid_flit_i;
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
logic [VC_NUM-1:0][PORT_NUM-1:0] out_port_set_o;
credits_t credit_return_o;
logic [VC_NUM-1:0] is_full_o;
logic [VC_NUM-1:0] is_empty_o;
logic [VC_NUM-1:0] error_o;
vc_class_t [VC_NUM-1:0] vc_class_o;

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
    .out_port_set_o(out_port_set_o),
    .credit_return_o(credit_return_o),
    .is_full_o(is_full_o),
    .is_empty_o(is_empty_o),
    .error_o(error_o),
    .vc_class_o(vc_class_o)
);

initial begin
    clk = 0;
    rst = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

task reset_dut;
begin
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
end
endtask

task receive_flit_simple (input logic [VC_SIZE-1:0] vc_idx, input flit_label_t label, input logic [DEST_ADDR_SIZE_X-1:0] x_dest, input logic [DEST_ADDR_SIZE_Y-1:0] y_dest,
input logic [HEAD_PAYLOAD_SIZE-1:0] head_data,input logic [BODY_PAYLOAD_SIZE-1:0] body_data);
flit_t data;
begin
    data = '0;
    if (label == HEAD || label == HEADTAIL) begin 
        data = {label, x_dest, y_dest, head_data};
    end 
    else begin
        data = {label, body_data};
    end


    @(negedge clk);
    data_i = data;
    valid_flit_i[vc_idx] = 1'b1;

    
    @(posedge clk); #1;
    if (label == HEAD || label == HEADTAIL) begin
        $display("[%0t]-Flit received with label=%s, x_dest=%d, y_dest=%d, data=0x%h", $time, label.name(), x_dest, y_dest, head_data);
    end
    else begin
        $display("[%0t]-Flit received with label=%s, data=0x%h", $time, label.name(), data_i);
    end

    if (vc_idx == 0) begin
        if (dut.generate_virtual_channels[0].vc_buffer.peek_o == data_i) begin
            $display("[%0t]-Peeked flit matches input data", $time);
        end 
        else begin
            $error("[%0t]-Error: Peeked flit does not match input data. Expected: %h, Got: %h", $time, data_i, dut.generate_virtual_channels[0].vc_buffer.peek_o);
        end
    end
    else begin
        if (dut.generate_virtual_channels[1].vc_buffer.peek_o == data_i) begin
            $display("[%0t]-Peeked flit matches input data", $time);
        end 
        else begin
            $error("[%0t]-Error: Peeked flit does not match input data. Expected: %h, Got: %h", $time, data_i, dut.generate_virtual_channels[1].vc_buffer.peek_o);
        end
    end
    

    @(negedge clk);
    valid_flit_i[vc_idx] = 1'b0;
end
endtask

task virtual_channel_allocation (); 

endtask

always @(posedge clk) begin
    #2; // Small delay to allow outputs to stabilize before printing
    $display("[%0t]-Outputs: xb_flit_o=0x%h, is_allocatable_vc_o=%b, va_request_o=%b, sa_request_o=%b, sa_downstream_vc_o=%b, out_port_o=%s, out_port_set_o [E W S N L] =%b, credit_return_o=%h, is_full_o=%b, is_empty_o=%b, error_o=%b, vc_class_o=%s", 
        $time, xb_flit_o, is_allocatable_vc_o[1], va_request_o[1], sa_request_o[1], sa_downstream_vc_o[1], out_port_o[1].name(), out_port_set_o[1], credit_return_o[1], is_full_o[1], is_empty_o[1], error_o[1], vc_class_o[1].name());
end

initial begin
    reset_dut();

    //Receive a simple flit
    receive_flit_simple(1, HEADTAIL, 0, 3, HEAD_PAYLOAD_SIZE'({$urandom(), $urandom()}), 0);
    wait (va_request_o[1] == 1'b1);
    $display("[%0t]-VA request for VC 1 observed", $time);
    @(posedge clk);     

$finish;
end
  
endmodule