import noc_params::*;

module crossbar(
    input_block2crossbar.crossbar ib_if,
    switch_allocator2crossbar.crossbar sa_if,
    output flit_t data_o [PORT_NUM-1:0]  //Indexing output ports
);

    /*
    Combinational logic:
    on each output, propagate the corresponding input
    according to the current selection
    */
    always_comb
    begin
        for(int out_port = 0; out_port < PORT_NUM; out_port = out_port + 1)
        begin
            if (sa_if.valid_flit[out_port]) begin
                data_o[out_port] = ib_if.flit[sa_if.input_port_sel[out_port]];
            end
            else begin
                data_o[out_port] = '0;
            end
        end

    end

endmodule
