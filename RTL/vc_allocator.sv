import noc_params::*;

module vc_allocator #(
)(
    input rst,
    input clk,
    input [PORT_NUM-1:0][VC_NUM-1:0] idle_downstream_vc_i,
    input_block2vc_allocator.vc_allocator ib_if
);

    logic [PORT_NUM-1:0][VC_NUM-1:0][PORT_NUM-1:0] port_grant;
    port_t [PORT_NUM-1:0][VC_NUM-1:0] selected_out_port;
    logic [PORT_NUM-1:0][VC_SIZE-1:0] selected_out_vc;
    logic [PORT_NUM-1:0][VC_NUM-1:0][PORT_NUM-1:0] port_request;
    logic [PORT_NUM-1:0][VC_NUM-1:0] is_available_vc, is_available_vc_next;
    logic [PORT_NUM-1:0][VC_NUM-1:0][PORT_NUM-1:0][VC_NUM-1:0] eligible_vc_set_w;
    logic [PORT_NUM-1:0][VC_NUM-1:0] vc_request;
    logic [PORT_NUM-1:0][VC_NUM-1:0] vc_grant;
    logic [PORT_NUM-1:0] port_has_request;

    generate
        for (genvar i = 0; i < PORT_NUM; i++) begin
            for (genvar j = 0; j < VC_NUM; j++) begin
                round_robin_arbiter #(
                 .AGENTS_NUM(PORT_NUM)
                ) rr_arbiter (
                    .rst(rst),
                    .clk(clk),
                    .requests_i(port_request[i][j]),
                    .grants_o(port_grant[i][j])
                );
            end
        end
    endgenerate

    generate
    for (genvar p = 0; p < PORT_NUM; p++) begin

        round_robin_arbiter #(
            .AGENTS_NUM(VC_NUM)
        ) vc_rr (
            .rst(rst),
            .clk(clk),
            .requests_i(vc_request[p]),
            .grants_o(vc_grant[p])
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
        port_request = '0;
        vc_request = '0;
        selected_out_port = '0;
        selected_out_vc = '0;
        port_has_request = '0;

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

        for(int up_port = 0; up_port < PORT_NUM; up_port = up_port + 1)
        begin
            for(int up_vc = 0; up_vc < VC_NUM; up_vc = up_vc + 1)
            begin
                port_request[up_port][up_vc] = agents_mask(eligible_vc_set_w[up_port][up_vc]);
            end
        end

        for (int up_port = 0; up_port < PORT_NUM; up_port = up_port + 1) begin
            for (int up_vc = 0; up_vc < VC_NUM; up_vc = up_vc + 1) begin
                for (int down_port = 0; down_port < PORT_NUM; down_port = down_port + 1) begin
                    if (port_grant[up_port][up_vc][down_port]) begin
                        port_has_request[down_port] = 1'b1;
                    end  
                end
            end
        end

        foreach (port_has_request[down_port]) begin
            if (port_has_request[down_port])
                vc_request[down_port] = is_available_vc[down_port];
            else vc_request[down_port] = '0;
        end  
      
        for (int down_port = 0; down_port < PORT_NUM; down_port = down_port + 1) begin
            for (int down_vc = 0; down_vc < VC_NUM; down_vc = down_vc + 1) begin
                if (vc_grant[down_port][down_vc]) begin
                    selected_out_vc[down_port] = down_vc;
                end
            end
        end

        for (int up_port = 0; up_port < PORT_NUM; up_port = up_port + 1) begin
            for (int up_vc = 0; up_vc < VC_NUM; up_vc = up_vc + 1) begin
                for (int down_port = 0; down_port < PORT_NUM; down_port = down_port + 1) begin
                    if (port_grant[up_port][up_vc][down_port]) begin
                        selected_out_port[up_port][up_vc] = down_port;
                        ib_if.vc_new[up_port][up_vc] = selected_out_vc[down_port];
                        ib_if.vc_valid[up_port][up_vc] = 1'b1;
                        is_available_vc_next[selected_out_port[up_port][up_vc]][ib_if.vc_new[up_port][up_vc]] = 1'b0;
                    end  
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
        eligible_vc_set = '0;

        foreach (out_port_mask[up_port]) begin
             foreach (out_port_mask[up_port][up_vc]) begin
                logic is_escape_up;
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

    function automatic logic [PORT_NUM-1:0] agents_mask (
        input logic [PORT_NUM-1:0][VC_NUM-1:0] eligible_per_input_vc
    );
        
        int max_counter = 0;
        logic any_valid = 0;
        agents_mask = '0;

        for (int down_port = 0; down_port < PORT_NUM; down_port ++) begin
            int count = 0;
            for (int down_vc = 0; down_vc < VC_NUM; down_vc ++) begin
                if (eligible_per_input_vc[down_port][down_vc]) begin
                    count++;
                    any_valid = 1'b1;
                end
            end
            if (count > max_counter) begin
                max_counter = count;
                agents_mask = '0;
                agents_mask[down_port] = 1'b1;
            end 
            else if (count == max_counter && count != 0) begin
                agents_mask[down_port] = 1'b1;
            end            
        end
        if (!any_valid) begin
                agents_mask = '0;
            end 
    endfunction

endmodule