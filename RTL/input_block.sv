import noc_params::*;

module input_block #(
    parameter BUFFER_SIZE = VC_DEPTH,
    parameter X_CURRENT = MESH_SIZE_X/2,
    parameter Y_CURRENT = MESH_SIZE_Y/2
)(
    input flit_t data_i [PORT_NUM-1:0],
    input valid_flit_i [PORT_NUM-1:0],
    input credit_t credit_return_i [PORT_NUM-1:0],
    input rst,
    input clk,
    input_block2crossbar.input_block crossbar_if,
    input_block2switch_allocator.input_block sa_if,
    input_block2vc_allocator.input_block va_if,
    output logic [VC_NUM-1:0] vc_allocatable_o [PORT_NUM-1:0],
    output logic [VC_NUM-1:0] error_o [PORT_NUM-1:0],
    output vc_class_t [PORT_NUM-1:0][VC_NUM-1:0] vc_class_o
);
    
    logic [VC_NUM-1:0] is_full [PORT_NUM-1:0];
    logic [VC_NUM-1:0] is_empty [PORT_NUM-1:0];

    port_t [VC_NUM-1:0] out_port [PORT_NUM-1:0];

    logic [PORT_NUM-1:0][VC_NUM-1:0][VC_COUNT-1:0] credits_counter;
    logic [PORT_NUM-1:0][VC_NUM-1:0][VC_COUNT-1:0] credits_counter_next ;
    logic [PORT_NUM-1:0][VC_NUM-1:0] credits_exist; 
    logic [PORT_NUM-1:0][VC_NUM-1:0] flit_consumed; // Indicates if a flit has been consumed from the output port and VC
    

    assign sa_if.out_port = out_port;
    assign va_if.credits_exist = credits_exist;
    assign sa_if.credits_exist = credits_exist;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            for (int ip = 0; ip < PORT_NUM; ip++) begin
                for (int vc = 0; vc < VC_NUM; vc++) begin
                    credits_counter[ip][vc] <= VC_DEPTH;
                end
            end
        end 
        else begin
            credits_counter <= credits_counter_next;
        end
    end

    /*
    The Input Block module contains all the PORT_NUM
    Input Ports composing the Router, making it easier
    to connect all of them through one single interface
    per each other module, i.e., the Crossbar, the
    Virtual Channel Allocator and the Switch Allocator.
    */
    genvar ip;
    generate
        for(ip=0; ip<PORT_NUM; ip++)
        begin: generate_input_ports
            input_port #(
                .BUFFER_SIZE(VC_DEPTH),
                .X_CURRENT(X_CURRENT),
                .Y_CURRENT(Y_CURRENT)
            )
            input_port (
                .data_i(data_i[ip]),
                .valid_flit_i(valid_flit_i[ip]),
                .rst(rst),
                .clk(clk),
                .sa_sel_vc_i(sa_if.vc_sel[ip]),
                .port_new_i(va_if.port_new[ip]),
                .va_new_vc_i(va_if.vc_new[ip]),
                .va_valid_i(va_if.vc_valid[ip]),
                .sa_valid_i(sa_if.valid_sel[ip]),
                .xb_flit_o(crossbar_if.flit[ip]),
                .is_allocatable_vc_o(vc_allocatable_o[ip]),
                .va_request_o(va_if.vc_request[ip]),
                .sa_request_o(sa_if.switch_request[ip]),
                .sa_downstream_vc_o(sa_if.downstream_vc[ip]),
                .out_port_set_o(va_if.out_port_set[ip]),
                .out_port_o(out_port[ip]),
                .is_full_o(is_full[ip]),
                .is_empty_o(is_empty[ip]),
                .error_o(error_o[ip]),
                .vc_class_o(vc_class_o[ip])
            );
        end
    endgenerate

    always_comb begin
        credits_counter_next = credits_counter;
        flit_consumed = '0;

    for (int down_port = 0; down_port < PORT_NUM; down_port++) begin
        for (int down_vc = 0; down_vc < VC_NUM; down_vc++) begin
            credits_exist[down_port][down_vc] = (credits_counter[down_port][down_vc] > 0);
        end
    end


    for (int up_port = 0; up_port < PORT_NUM; up_port++) begin
        if (sa_if.valid_sel[up_port]) begin
            automatic int up_vc = sa_if.vc_sel[up_port];
            automatic port_t down_port = sa_if.out_port[up_port][up_vc];
            automatic int down_vc = sa_if.downstream_vc[up_port][up_vc];
            flit_consumed[down_port][down_vc] = 1'b1;
        end
    end

            
    for (int down_port = 0; down_port < PORT_NUM; down_port++) begin
        for (int down_vc = 0; down_vc < VC_NUM; down_vc++) begin
            case ({flit_consumed[down_port][down_vc], credit_return_i[down_port].credit_valid[down_vc]})
                2'b01: credits_counter_next[down_port][down_vc] = (credits_counter[down_port][down_vc] == VC_DEPTH) ? VC_DEPTH : credits_counter[down_port][down_vc] + 1;
                2'b10: credits_counter_next[down_port][down_vc] = (credits_counter[down_port][down_vc] == 0) ? 0 : credits_counter[down_port][down_vc] - 1;
                default : credits_counter_next[down_port][down_vc] = credits_counter[down_port][down_vc];
            endcase
        end
    end

    end
endmodule
