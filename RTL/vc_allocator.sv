import noc_params::*;

// ------------------------------------------------------------
// Virtual Channel Allocator (Separable Input-First, Flattened)
// - Allocates (output port, VC) pairs to upstream VCs
// - Uses 2-stage arbitration over flattened resources
// - Guarantees one-to-one mapping (no collisions)
// ------------------------------------------------------------

module vc_allocator (
    input rst,
    input clk,
    input [PORT_NUM-1:0][VC_NUM-1:0] idle_downstream_vc_i,
    input_block2vc_allocator.vc_allocator ib_if
);

    // Number of resources ((port, VC) pairs)
    localparam NUM_RESOURCES = PORT_NUM * VC_NUM; // Total downstream VC resources (port × VC)
    // Number of requesting agents (input VCs)
    localparam NUM_AGENTS = PORT_NUM * VC_NUM; //Up VCs on upstream ports
    /* Flattened index mapping:
    agent_id  = up_port * VC_NUM + up_vc
    resource_id = down_port * VC_NUM + down_vc */

    
    logic [NUM_AGENTS-1:0][NUM_RESOURCES-1:0] requests_1;
    logic [NUM_AGENTS-1:0][NUM_RESOURCES-1:0] grants_1;
    logic [NUM_RESOURCES-1:0][NUM_AGENTS-1:0] grants_2;
    logic [NUM_RESOURCES-1:0][NUM_AGENTS-1:0] requests_2;
    logic [PORT_NUM-1:0][VC_NUM-1:0] is_available_vc, is_available_vc_next;
    logic [PORT_NUM-1:0][VC_NUM-1:0][PORT_NUM-1:0][VC_NUM-1:0] eligible_vc_set_w;


    // ------------------------------------------------------------
    // Stage 1 Arbitration (Input-side)
    // Each agent selects exactly ONE desired resource
    // Output is one-hot per agent (grant_stage1)
    // ------------------------------------------------------------
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

    // ------------------------------------------------------------
    // Stage 2 Arbitration (Output-side)
    // Each resource selects exactly ONE winning agent
    // Guarantees exclusive allocation per (port, VC)
    // ------------------------------------------------------------
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

    
    always_comb
    begin

        is_available_vc_next = is_available_vc;

        for(int up_port = 0; up_port < PORT_NUM; up_port = up_port + 1)
        begin
            for(int up_vc = 0; up_vc < VC_NUM; up_vc = up_vc + 1)
            begin
                ib_if.vc_valid[up_port][up_vc] = 1'b0;
                ib_if.vc_new[up_port][up_vc] = {VC_SIZE{1'bx}};
                ib_if.port_new[up_port][up_vc] = port_t'('x);
            end
        end

        for (int down_port = 0; down_port < PORT_NUM; down_port = down_port + 1) begin
            for (int down_vc = 0; down_vc < VC_NUM; down_vc = down_vc + 1) begin
                if (idle_downstream_vc_i[down_port][down_vc]) begin
                    is_available_vc_next[down_port][down_vc] = 1'b1;
                end
            end
        end

        eligible_vc_set_w = eligible_vc_set(ib_if.out_port_mask, is_available_vc, ib_if.credits_exist, ib_if.vc_class);

        // ------------------------------------------------------------
        // Stage 1 Requests (Agent → Resource)
        // Each agent requests all eligible (port, VC) resources
        // Result: req_stage1[agent][resource]
        // ------------------------------------------------------------
        for (int up_port = 0; up_port < PORT_NUM; up_port = up_port + 1) begin
            for (int up_vc = 0; up_vc < VC_NUM; up_vc = up_vc + 1) begin
                for (int down_port = 0; down_port < PORT_NUM; down_port = down_port + 1) begin
                    for (int down_vc = 0; down_vc < VC_NUM; down_vc = down_vc + 1) begin
                       automatic int agent_id = up_port * VC_NUM + up_vc;
                       automatic int resource_id = down_port * VC_NUM + down_vc;
                       requests_1[agent_id][resource_id] = eligible_vc_set_w[up_port][up_vc][down_port][down_vc] && ib_if.vc_request[up_port][up_vc]; 
                    end
                end
            end
        end


        // ------------------------------------------------------------
        // Transpose (No logic, only wiring)
        // Converts:
        //   grant_stage1[agent][resource]
        // → req_stage2[resource][agent]
        // So each resource sees all requesting agents
        // ------------------------------------------------------------
        for (int agent = 0; agent < NUM_AGENTS; agent = agent + 1) begin
            for (int resource = 0; resource < NUM_RESOURCES; resource = resource + 1) begin
                requests_2[resource][agent] = grants_1[agent][resource];
            end
        end

        
        // ------------------------------------------------------------
        // Final Allocation (Handshake)
        // Allocation occurs ONLY if agent wins Stage 2:
        //   grant_stage2[resource][agent] == 1
        // This enforces:
        // - No collisions
        // - One-to-one mapping
        // ------------------------------------------------------------
        for (int resource = 0; resource < NUM_RESOURCES; resource = resource + 1) begin
            for (int agent = 0; agent < NUM_AGENTS; agent = agent + 1) begin
                if (grants_2[resource][agent]) begin
                    automatic int up_port = agent / VC_NUM;
                    automatic int up_vc = agent % VC_NUM;
                    automatic int down_port = resource / VC_NUM; // Decode flattened resource index into hardware coordinates
                    automatic int down_vc = resource % VC_NUM;
                    ib_if.vc_new[up_port][up_vc] = down_vc[VC_SIZE-1:0]; // Output the allocated VC number to the input block
                    ib_if.port_new[up_port][up_vc] = port_t'(down_port); // Output the allocated port number to the input block
                    ib_if.vc_valid[up_port][up_vc] = 1'b1;
                    is_available_vc_next[down_port][down_vc] = 1'b0;
                    end  
                end
            end

    end
    

    // ------------------------------------------------------------
    // Eligibility Computation
    // Determines valid (agent → resource) pairs based on:
    // - Routing (out_port_mask)
    // - VC availability
    // - Credit availability
    // - VC class constraints (deadlock avoidance)
    // ------------------------------------------------------------
    function automatic logic [PORT_NUM-1:0][VC_NUM-1:0][PORT_NUM-1:0][VC_NUM-1:0] eligible_vc_set (
        input logic [PORT_NUM-1:0][VC_NUM-1:0][PORT_NUM-1:0] out_port_mask,
        input logic [PORT_NUM-1:0][VC_NUM-1:0] is_available_vc,
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
                        for (int down_vc = 0; down_vc < VC_NUM; down_vc = down_vc + 1) begin
                            class_valid = !(is_escape_up && vc_class[down_port][down_vc] == ADAPTIVE);
                            if (is_available_vc[down_port][down_vc] && credits[down_port][down_vc] && class_valid) begin
                                eligible_vc_set[up_port][up_vc][down_port][down_vc] = 1'b1;
                            end
                        end
                    end
                end
            end
        end
    endfunction

endmodule