import noc_params::*;

module vc_allocator #(
)(
    input rst,
    input clk,
    input [PORT_NUM-1:0][VC_NUM-1:0] idle_downstream_vc_i,
    input_block2vc_allocator.vc_allocator ib_if
);

    localparam NUM_RESOURCES = PORT_NUM * VC_NUM; //Down VCs on downstream ports
    localparam NUM_AGENTS = PORT_NUM * VC_NUM; //Up VCs on upstream ports

    
    logic [NUM_AGENTS-1:0][NUM_RESOURCES-1:0] requests_1;
    logic [NUM_AGENTS-1:0][NUM_RESOURCES-1:0] grants_1;
    logic [NUM_RESOURCES-1:0][NUM_AGENTS-1:0] grants_2;
    logic [NUM_RESOURCES-1:0][NUM_AGENTS-1:0] requests_2;
    logic [PORT_NUM-1:0][VC_NUM-1:0] is_available_vc, is_available_vc_next;
    logic [PORT_NUM-1:0][VC_NUM-1:0][PORT_NUM-1:0][VC_NUM-1:0] eligible_vc_set_w;

    generate
        for (genvar i = 0; i < NUM_AGENTS; i++) begin
            round_robin_arbiter #(
                .AGENTS_NUM(NUM_RESOURCES)
            ) rr_1 (
                .rst(rst),
                .clk(clk),
                .requests_i(requests_1[i]),
                .grants_o(grants_1[i])
            );
        end
    endgenerate

    generate
    for (genvar p = 0; p < NUM_RESOURCES; p++) begin
        round_robin_arbiter #(
            .AGENTS_NUM(NUM_AGENTS)
        ) rr_2 (
            .rst(rst),
            .clk(clk),
            .requests_i(requests_2[p]),
            .grants_o(grants_2[p])
        );
    end
    endgenerate


    /*
    Sequential logic:
    - reset on the rising edge of the rst input;
    - update the availability of downstream Virtual Channels.
    */
    always_ff@(posedge clk, posedge rst)
    begin
        if(rst)
        begin
            is_available_vc <= {PORT_NUM*VC_NUM{1'b1}};
        end
        else
        begin
            is_available_vc <= is_available_vc_next;
        end
    end

    /*
    Combinational logic:
    - compute the request matrix for the internal Separable Input-First
      Allocator, by setting to 1 the upstream Virtual Channels which are
      requesting for the allocation of a downstream Virtual Channel and
      whose associated downstream Input Port has at least one available
      Virtual Channel;
    - compute the outputs of the module from the grants matrix obtained
      from the Separable Input-First allocator and update the next
      value for the availability of downstream Virtual Channels if
      they have just been allocated;
    - update the next value for the availability of downstream Virtual
      Channels after their eventual deallocations.
    */
    always_comb
    begin

        is_available_vc_next = is_available_vc;

        for(int up_port = 0; up_port < PORT_NUM; up_port = up_port + 1)
        begin
            for(int up_vc = 0; up_vc < VC_NUM; up_vc = up_vc + 1)
            begin
                ib_if.vc_valid[up_port][up_vc] = 1'b0;
                ib_if.vc_new[up_port][up_vc] = {VC_SIZE{1'bx}};
            end
        end

        eligible_vc_set_w = eligible_vc_set(ib_if.out_port_mask, idle_downstream_vc_i, ib_if.credits_exist, ib_if.vc_class);

        requests_1 = eligible_vc_set_w;

        for (int agent = 0; agent < NUM_AGENTS; agent = agent + 1) begin
            for (int resource = 0; resource < NUM_RESOURCES; resource = resource + 1) begin
                requests_2[resource][agent] = grants_1[agent][resource];
            end
        end

        for (int resource = 0; resource < NUM_RESOURCES; resource = resource + 1) begin
            for (int agent = 0; agent < NUM_AGENTS; agent = agent + 1) begin
                if (grants_2[resource][agent]) begin
                    int up_port = agent / VC_NUM;
                    int up_vc = agent % VC_NUM;
                    int down_port = resource / VC_NUM;
                    int down_vc = resource % VC_NUM;
                    ib_if.vc_new[up_port][up_vc] = down_vc;
                    ib_if.vc_valid[up_port][up_vc] = 1'b1;
                    is_available_vc_next[down_port][down_vc] = 1'b0;
                    end  
                end
            end

        for(int down_port = 0; down_port < PORT_NUM; down_port = down_port + 1)
        begin
            for(int down_vc = 0; down_vc < VC_NUM; down_vc = down_vc + 1)
            begin
                if(!is_available_vc[down_port][down_vc] && idle_downstream_vc_i[down_port][down_vc])
                begin
                    is_available_vc_next[down_port][down_vc] = 1'b1;
                end
            end
        end
    end
    //Functions

    function automatic logic [PORT_NUM-1:0][VC_NUM-1:0][PORT_NUM-1:0][VC_NUM-1:0] eligible_vc_set (
        input logic [PORT_NUM-1:0][VC_NUM-1:0][PORT_NUM-1:0] out_port_mask,
        input logic [PORT_NUM-1:0][VC_NUM-1:0] is_idle_vc,
        input logic [PORT_NUM-1:0][VC_NUM-1:0] credits,
        input vc_class_t [PORT_NUM-1:0][VC_NUM-1:0] vc_class //Escape or Adaptive enum
        );

        logic class_valid;
        logic is_escape_up;
        eligible_vc_set = '0;

        foreach (out_port_mask[up_port]) begin
             foreach (out_port_mask[up_port][up_vc]) begin
                is_escape_up = (vc_class[up_port][up_vc] == ESCAPE); 
                foreach (out_port_mask[up_port][up_vc][down_port]) begin
                    if (out_port_mask[up_port][up_vc][down_port]) begin
                        foreach (is_idle_vc[down_port][down_vc]) begin
                            class_valid = !(is_escape_up && vc_class[down_port][down_vc] == ADAPTIVE);
                            if (is_idle_vc[down_port][down_vc] && credits[down_port][down_vc] && class_valid) begin
                                eligible_vc_set[up_port][up_vc][down_port][down_vc] = 1'b1;
                            end
                        end
                    end
                end
            end
        end
    endfunction

endmodule