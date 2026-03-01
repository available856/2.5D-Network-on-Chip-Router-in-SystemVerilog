module round_robin_arbiter #(
    parameter AGENTS_NUM = 4
)(
    input rst,
    input clk,
    input [AGENTS_NUM-1:0] requests_i,
    output logic [AGENTS_NUM-1:0] grants_o
);

    localparam int AGENTS_PTR_SIZE = $clog2(AGENTS_NUM);

    logic [AGENTS_PTR_SIZE-1:0] highest_priority, highest_priority_next;

    /*
    Sequential logic:
    - reset on the rising edge of the rst input;
    - update the agent with the highest priority with
      respect to the Round-Robin arbitration policy.
    */
    always_ff@(posedge clk, posedge rst)
    begin
        if(rst)
        begin
            highest_priority <= 0;
        end
        else
        begin
            highest_priority <= highest_priority_next;
        end
    end

    /*
    Combinational logic:
    - among all the agents requesting for the shared resource,
      grant the first one in ascending order starting
      from the current highest priority agent;
    - set as the next highest priority agent
      the one following the granted agent.
    */

    always_comb
    begin
        int idx, next_idx;
        grants_o = {AGENTS_NUM{1'b0}};
        highest_priority_next = highest_priority;
        for(int i = 0; i < AGENTS_NUM; i = i + 1)
        begin
            idx = highest_priority + i;

            if (idx >= AGENTS_NUM)
                idx = idx - AGENTS_NUM;

            next_idx = idx + 1;

            if (next_idx >= AGENTS_NUM)
                next_idx = 0;
                
            if(requests_i[idx])
            begin
                grants_o[idx] = 1'b1;
                highest_priority_next = next_idx[AGENTS_PTR_SIZE-1:0];
                break;
            end
        end
    end

endmodule