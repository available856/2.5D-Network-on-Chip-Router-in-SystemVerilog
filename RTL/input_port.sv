import noc_params::*;

module input_port #(
    parameter BUFFER_SIZE = VC_DEPTH,
    parameter X_CURRENT = MESH_SIZE_X/2,
    parameter Y_CURRENT = MESH_SIZE_Y/2
)(
    input flit_t data_i,
    input [VC_NUM-1:0] valid_flit_i,
    input port_t [VC_NUM-1:0] port_new_i,
    input rst,
    input clk,
    input [VC_SIZE-1:0] sa_sel_vc_i,
    input [VC_SIZE-1:0] va_new_vc_i [VC_NUM-1:0],
    input [VC_NUM-1:0] va_valid_i,
    input sa_valid_i,
    output flit_t xb_flit_o,
    output logic [VC_NUM-1:0] is_allocatable_vc_o,
    output logic [VC_NUM-1:0] va_request_o,
    output logic sa_request_o [VC_NUM-1:0],
    output logic [VC_SIZE-1:0] sa_downstream_vc_o [VC_NUM-1:0],
    output port_t [VC_NUM-1:0] out_port_o,
    output logic [VC_NUM-1:0][PORT_NUM-1:0] out_port_set_o,
    output logic [VC_NUM-1:0] is_full_o,
    output logic [VC_NUM-1:0] is_empty_o,
    output logic [VC_NUM-1:0] error_o,
    output vc_class_t [VC_NUM-1:0] vc_class_o
);

    flit_t [VC_NUM-1:0] data_out;
    flit_t peek_o [VC_NUM-1:0];


    logic [VC_NUM-1:0] read_cmd;
    logic [VC_NUM-1:0] write_cmd;

    logic [VC_NUM-1:0][DEST_ADDR_SIZE_X-1:0] x_dest;
    logic [VC_NUM-1:0][DEST_ADDR_SIZE_Y-1:0] y_dest;
    logic [VC_NUM-1:0] rc_valid;
    logic [VC_NUM-1:0][PORT_NUM-1:0] rc_product;

    
    generate
        for(genvar vc=0; vc<VC_NUM; vc++)
        begin: generate_virtual_channels
            vc_buffer #(
                .BUFFER_SIZE(BUFFER_SIZE),
                .VC_ID(vc)
            )
            vc_buffer (
                .data_i(data_i),
                .read_i(read_cmd[vc]),
                .write_i(write_cmd[vc]),
                .vc_new_i(va_new_vc_i[vc]),
                .vc_valid_i(va_valid_i[vc]),
                .out_port_i(port_new_i[vc]),
                .rst(rst),
                .clk(clk),
                .data_o(data_out[vc]),
                .peek_o(peek_o[vc]),
                .is_full_o(is_full_o[vc]),
                .is_empty_o(is_empty_o[vc]),
                .out_port_o(out_port_o[vc]),
                .vc_request_o(va_request_o[vc]),
                .switch_request_o(sa_request_o[vc]),
                .vc_allocatable_o(is_allocatable_vc_o[vc]),
                .downstream_vc_o(sa_downstream_vc_o[vc]),
                .error_o(error_o[vc]),
                .vc_class_o(vc_class_o[vc])
            );
        end
    endgenerate

    generate
        for (genvar vc=0; vc<VC_NUM; vc++) begin : generate_rc_units
            rc_unit #(
                .X_CURRENT(X_CURRENT),
                .Y_CURRENT(Y_CURRENT)
            ) rc_unit (
                .x_dest_i(x_dest[vc]),
                .y_dest_i(y_dest[vc]),
                .vc_class_i(vc_class_o[vc]),
                .eligible_port_set(rc_product[vc])
            );
            assign out_port_set_o[vc] = rc_valid[vc] ? rc_product[vc] : '0; // If RC is valid, use RC product; else, no eligible ports
        end
    endgenerate


    /*
    Combinational logic:
    - if the input flit is valid, assert the write command of the corresponding
      virtual channel buffer where the flit has to be stored;
    - assert the read command of the virtual channel buffer selected by the
      interfaced switch allocator and propagate at the crossbar interface the
      corresponding flit.
    */
    always_comb
    begin
        for (int vc=0; vc<VC_NUM; vc++) begin
            x_dest[vc] = '0;
            y_dest[vc] = '0;
            rc_valid[vc] = 1'b0;
            if ((peek_o[vc].flit_label == HEAD || peek_o[vc].flit_label == HEADTAIL) && !is_empty_o[vc] ) begin
                x_dest[vc] = peek_o[vc].data.head_data.x_dest;
                y_dest[vc] = peek_o[vc].data.head_data.y_dest;
                rc_valid[vc] = 1'b1;
            end
        end
        
        write_cmd = valid_flit_i; // One-hot vector indicating which VC has a valid flit to write

        read_cmd = {VC_NUM{1'b0}};
        if(sa_valid_i)
            read_cmd[sa_sel_vc_i] = 1;
        xb_flit_o = data_out[sa_sel_vc_i];
    end

endmodule
