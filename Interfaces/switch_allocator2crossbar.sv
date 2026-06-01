import noc_params::*;

interface switch_allocator2crossbar;

    logic [PORT_SIZE-1:0] input_port_sel [PORT_NUM-1:0]; //Output port corresponds to which input port
    logic [PORT_NUM-1:0] valid_flit; // Flit valid on the output port

    modport switch_allocator (
        output input_port_sel,
        output valid_flit
    );

    modport crossbar (
        input input_port_sel,
        input valid_flit
    );

endinterface
