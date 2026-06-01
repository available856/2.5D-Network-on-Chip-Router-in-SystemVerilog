import noc_params::*;

interface router2router;

    flit_t data;
    logic is_valid;
    credits_t credits;
    logic [VC_NUM-1:0] is_allocatable;
    vc_class_t vc_class;

    modport upstream (
        output data,
        output is_valid,
        input credits,
        input is_allocatable
    );

    modport downstream (
        input data,
        input is_valid,
        output credits,
        output is_allocatable
    );

endinterface
