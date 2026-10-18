`timescale 1ns / 1ps
import noc_params::*;

module tb_router;

    parameter CLK_PERIOD = 10; // 100MHz clock

    //clock and reset
    logic clk;
    logic rst;

    logic [VC_NUM-1:0] error [PORT_NUM-1:0];

    logic credit_stall; // Signal to indicate if the testbench should stall due to lack of credits
    logic [PORT_NUM-1:0][VC_NUM-1:0][VC_COUNT:0] credits_pending; // Track pending credits for each port, VC, and buffer slot
    
    logic reset_done;
    // Match each transmitted flit, preserving packet order and its selected route.
    flit_t expected_flit[64];
    bit arrived[64];
    int head_of[64], previous[64], routed_port[64], routed_vc[64];
    int input_head[PORT_NUM][VC_NUM], input_last[PORT_NUM][VC_NUM];
    int sent = 0, received = 0;

    //interfaces
    router2router router_if_local_up();
    router2router router_if_north_up();
    router2router router_if_south_up();
    router2router router_if_west_up();
    router2router router_if_east_up();

    router2router router_if_local_down();
    router2router router_if_north_down();
    router2router router_if_south_down();
    router2router router_if_west_down();
    router2router router_if_east_down();

    //DUT
    router #(
        .BUFFER_SIZE(VC_DEPTH),
        .X_CURRENT(MESH_SIZE_X/2),
        .Y_CURRENT(MESH_SIZE_Y/2)
    ) dut (
        .clk(clk),
        .rst(rst),
        .router_if_local_up(router_if_local_up),
        .router_if_north_up(router_if_north_up),
        .router_if_south_up(router_if_south_up),
        .router_if_west_up(router_if_west_up),
        .router_if_east_up(router_if_east_up),
        .router_if_local_down(router_if_local_down),
        .router_if_north_down(router_if_north_down),
        .router_if_south_down(router_if_south_down),
        .router_if_west_down(router_if_west_down),
        .router_if_east_down(router_if_east_down),
        .error_o(error)
    );

    //clock generation
    initial begin
        clk = 0;
        rst = 0;
        reset_done = 0;
        credit_stall = 0;
        credits_pending = '0;
    end

    always #(CLK_PERIOD/2) clk = ~clk;

    task reset_dut;
        begin
        @(negedge clk);
        rst = 1;
        router_if_local_down.data = '0; router_if_local_down.is_valid = 0;
        router_if_north_down.data = '0; router_if_north_down.is_valid = 0;
        router_if_south_down.data = '0; router_if_south_down.is_valid = 0;
        router_if_west_down.data = '0; router_if_west_down.is_valid = 0;
        router_if_east_down.data = '0; router_if_east_down.is_valid = 0;
        repeat(2) @(negedge clk);
        rst = 0;
        @(posedge clk);
        #1; // Small delay to ensure reset is deasserted before starting the test
        reset_done = 1;
        $display("[%0t]-DUT reset complete\n------------------------------\n", $time);
        @(negedge clk);
        end
    endtask

    
    always_ff @(posedge clk) begin
    
        // 1. Default State: Clear pulses
        router_if_local_up.credits <= '0;
        router_if_north_up.credits <= '0;
        router_if_south_up.credits <= '0;
        router_if_west_up.credits  <= '0;
        router_if_east_up.credits  <= '0;

        router_if_local_up.is_allocatable <= '0;
        router_if_north_up.is_allocatable <= '0;
        router_if_south_up.is_allocatable <= '0;
        router_if_west_up.is_allocatable  <= '0;
        router_if_east_up.is_allocatable  <= '0;

        // 2. IMMEDIATE VC Release && Credits upstream signaling
        if (router_if_local_up.is_valid) begin
            if (!credit_stall)
                router_if_local_up.credits[router_if_local_up.data.vc_id] <= 1'b1;
            if (router_if_local_up.data.flit_label == TAIL || router_if_local_up.data.flit_label == HEADTAIL)
                    router_if_local_up.is_allocatable[router_if_local_up.data.vc_id] <= 1'b1;
        end 

        if (router_if_north_up.is_valid) begin
            if (!credit_stall)
                router_if_north_up.credits[router_if_north_up.data.vc_id] <= 1'b1;
            if (router_if_north_up.data.flit_label == TAIL || router_if_north_up.data.flit_label == HEADTAIL)
                router_if_north_up.is_allocatable[router_if_north_up.data.vc_id] <= 1'b1;
        end

        if (router_if_south_up.is_valid) begin
            if (!credit_stall)
                router_if_south_up.credits[router_if_south_up.data.vc_id] <= 1'b1;
            if (router_if_south_up.data.flit_label == TAIL || router_if_south_up.data.flit_label == HEADTAIL)
                router_if_south_up.is_allocatable[router_if_south_up.data.vc_id] <= 1'b1;
        end

        if (router_if_west_up.is_valid) begin
            if (!credit_stall)
                router_if_west_up.credits[router_if_west_up.data.vc_id] <= 1'b1;
            if (router_if_west_up.data.flit_label == TAIL || router_if_west_up.data.flit_label == HEADTAIL)
                router_if_west_up.is_allocatable[router_if_west_up.data.vc_id] <= 1'b1;
        end

        if (router_if_east_up.is_valid) begin
            if (!credit_stall)
                router_if_east_up.credits[router_if_east_up.data.vc_id] <= 1'b1;
            if (router_if_east_up.data.flit_label == TAIL || router_if_east_up.data.flit_label == HEADTAIL)
                router_if_east_up.is_allocatable[router_if_east_up.data.vc_id] <= 1'b1;
        end


        // 3. Credit Stalling Logic
        // --- LOCAL ---
        if (credit_stall) begin
            if (router_if_local_up.is_valid) 
                credits_pending[LOCAL][router_if_local_up.data.vc_id] <= credits_pending[LOCAL][router_if_local_up.data.vc_id] + 1;
        end 
        else begin
            // Drain backlog when a new flit is not already returning this VC's credit.
            for (int vc = 0; vc < VC_NUM; vc++) begin
                if (credits_pending[LOCAL][vc] > 0 && !(router_if_local_up.is_valid && router_if_local_up.data.vc_id == vc)) begin
                    router_if_local_up.credits[vc] <= 1'b1;
                    credits_pending[LOCAL][vc] <= credits_pending[LOCAL][vc] - 1;
                end
            end
        end

        // --- NORTH ---
        if (credit_stall) begin
            if (router_if_north_up.is_valid) 
                credits_pending[NORTH][router_if_north_up.data.vc_id] <= credits_pending[NORTH][router_if_north_up.data.vc_id] + 1;
        end 
        else begin 
            for (int vc = 0; vc < VC_NUM; vc++) begin
                if (credits_pending[NORTH][vc] > 0 && !(router_if_north_up.is_valid && router_if_north_up.data.vc_id == vc)) begin
                    router_if_north_up.credits[vc] <= 1'b1;
                    credits_pending[NORTH][vc] <= credits_pending[NORTH][vc] - 1;
                end
            end
        end

        // --- SOUTH ---
        if (credit_stall) begin
            if (router_if_south_up.is_valid) 
                credits_pending[SOUTH][router_if_south_up.data.vc_id] <= credits_pending[SOUTH][router_if_south_up.data.vc_id] + 1;
        end 
        else begin
            for (int vc = 0; vc < VC_NUM; vc++) begin
                if (credits_pending[SOUTH][vc] > 0 && !(router_if_south_up.is_valid && router_if_south_up.data.vc_id == vc)) begin
                    router_if_south_up.credits[vc] <= 1'b1;
                    credits_pending[SOUTH][vc] <= credits_pending[SOUTH][vc] - 1;
                end
            end
        end

        // --- WEST ---
        if (credit_stall) begin
            if (router_if_west_up.is_valid) 
                credits_pending[WEST][router_if_west_up.data.vc_id] <= credits_pending[WEST][router_if_west_up.data.vc_id] + 1;
        end 
        else begin
            for (int vc = 0; vc < VC_NUM; vc++) begin
                if (credits_pending[WEST][vc] > 0 && !(router_if_west_up.is_valid && router_if_west_up.data.vc_id == vc)) begin
                    router_if_west_up.credits[vc] <= 1'b1;
                    credits_pending[WEST][vc] <= credits_pending[WEST][vc] - 1;
                end
            end
        end

        // --- EAST ---
        if (credit_stall) begin
            if (router_if_east_up.is_valid) 
                credits_pending[EAST][router_if_east_up.data.vc_id] <= credits_pending[EAST][router_if_east_up.data.vc_id] + 1;
        end 
        else begin
            for (int vc = 0; vc < VC_NUM; vc++) begin
                if (credits_pending[EAST][vc] > 0 && !(router_if_east_up.is_valid && router_if_east_up.data.vc_id == vc)) begin
                    router_if_east_up.credits[vc] <= 1'b1;
                    credits_pending[EAST][vc] <= credits_pending[EAST][vc] - 1;
                end
            end
        end

    end

    task receive_flit (port_t up_router, input [DEST_ADDR_SIZE_X-1:0] x_dest, input [DEST_ADDR_SIZE_Y-1:0] y_dest, input flit_label_t label,
        logic [VC_SIZE-1:0] vc_id, logic [HEAD_PAYLOAD_SIZE-1:0] head_pl, logic [BODY_PAYLOAD_SIZE-1:0] bt_pl);
        flit_t flit;

    begin
        flit = '0;
        @(negedge clk);

        if (label == HEAD || label == HEADTAIL) begin
            flit.flit_label = label;
            flit.vc_id = vc_id; 
            flit.data.head_data.x_dest = x_dest;
            flit.data.head_data.y_dest = y_dest;
            flit.data.head_data.head_pl = head_pl;
        end
        else begin
            flit.flit_label = label;
            flit.vc_id = vc_id; 
            flit.data.bt_pl = bt_pl;
        end

        case (up_router)
            LOCAL: begin
                router_if_local_down.data = flit;
                router_if_local_down.is_valid = 1;
                $display("[%0t] Sending flit", $time);
                $display("data=0x%h valid=%b", router_if_local_down.data, router_if_local_down.is_valid);
                @(negedge clk);
                router_if_local_down.is_valid = 0; // Deassert valid after one cycle
                router_if_local_down.data = '0; // Clear data after sending
            end 
            NORTH: begin
                router_if_north_down.data = flit;
                router_if_north_down.is_valid = 1;
                $display("[%0t] Sending flit", $time);
                $display("data=0x%h valid=%b", router_if_north_down.data, router_if_north_down.is_valid);
                @(negedge clk);
                router_if_north_down.is_valid = 0; // Deassert valid after one cycle
                router_if_north_down.data = '0; // Clear data after sending
            end
            SOUTH: begin
                router_if_south_down.data = flit;
                router_if_south_down.is_valid = 1;
                $display("[%0t] Sending flit", $time);
                $display("data=0x%h valid=%b", router_if_south_down.data, router_if_south_down.is_valid);
                @(negedge clk);
                router_if_south_down.is_valid = 0; // Deassert valid after one cycle
                router_if_south_down.data = '0; // Clear data after sending
            end
            WEST: begin
                router_if_west_down.data = flit;
                router_if_west_down.is_valid = 1;
                $display("[%0t] Sending flit", $time);
                $display("data=0x%h valid=%b", router_if_west_down.data, router_if_west_down.is_valid);
                @(negedge clk);
                router_if_west_down.is_valid = 0; // Deassert valid after one cycle
                router_if_west_down.data = '0; // Clear data after sending
            end
            EAST: begin
                router_if_east_down.data = flit;
                router_if_east_down.is_valid = 1;
                $display("[%0t] Sending flit", $time);
                $display("data=0x%h valid=%b", router_if_east_down.data, router_if_east_down.is_valid);
                @(negedge clk);
                router_if_east_down.is_valid = 0; // Deassert valid after one cycle
                router_if_east_down.data = '0; // Clear data after sending
            end
            default: $error("[%0t]-Invalid up_router value: %0d", $time, up_router);
        endcase
    
        @(posedge clk);

    end
    endtask

    task parallel_receive_flit(port_t up_router [2], input [DEST_ADDR_SIZE_X-1:0] x_dest [2], input [DEST_ADDR_SIZE_Y-1:0] y_dest [2], input flit_label_t label [2],
        logic [VC_SIZE-1:0] vc_id [2]);
        flit_t flit [2];
        logic [DEST_ADDR_SIZE_X-1:0] body_dest_x [2];
        logic [DEST_ADDR_SIZE_Y-1:0] body_test_y [2];
        logic [HEAD_PAYLOAD_SIZE-1:0] head_pl [2];
        logic [BODY_PAYLOAD_SIZE-1:0] bt_pl [2];

    begin
        for (int i = 0; i < 2; i++) begin
            flit[i] = '0;
            body_dest_x[i] = DEST_ADDR_SIZE_X'($urandom_range(0,MESH_SIZE_X-1));
            body_test_y[i] = DEST_ADDR_SIZE_Y'($urandom_range(0,MESH_SIZE_Y-1));
            head_pl[i] = HEAD_PAYLOAD_SIZE'({$urandom,$urandom});
            bt_pl[i] = BODY_PAYLOAD_SIZE'({$urandom,$urandom});
        end

        @(negedge clk);

        for (int i = 0; i < 2; i++) begin
            if (label[i] == HEAD || label[i] == HEADTAIL) begin
                flit[i].flit_label = label[i];
                flit[i].vc_id = vc_id[i];
                flit[i].data.head_data.x_dest = x_dest[i];
                flit[i].data.head_data.y_dest = y_dest[i];
            flit[i].data.head_data.head_pl = head_pl[i];
            end
            else begin
                flit[i].flit_label = label[i];
                flit[i].vc_id = vc_id[i]; 
                flit[i].data.bt_pl = bt_pl[i];
            end
        end

        for (int i = 0; i < 2; i++) begin
            case (up_router[i])
                LOCAL: begin
                    router_if_local_down.data = flit[i];
                    router_if_local_down.is_valid = 1;
                    $display("[%0t] Sending flit", $time);
                    $display("data=0x%h valid=%b", router_if_local_down.data, router_if_local_down.is_valid);
                end 
                NORTH: begin
                    router_if_north_down.data = flit[i];
                    router_if_north_down.is_valid = 1;
                    $display("[%0t] Sending flit", $time);
                    $display("data=0x%h valid=%b", router_if_north_down.data, router_if_north_down.is_valid);
                end
                SOUTH: begin
                    router_if_south_down.data = flit[i];
                    router_if_south_down.is_valid = 1;
                    $display("[%0t] Sending flit", $time);
                    $display("data=0x%h valid=%b", router_if_south_down.data, router_if_south_down.is_valid);
                end
                WEST: begin
                    router_if_west_down.data = flit[i];
                    router_if_west_down.is_valid = 1;
                    $display("[%0t] Sending flit", $time);
                    $display("data=0x%h valid=%b", router_if_west_down.data, router_if_west_down.is_valid);
                end
                EAST: begin
                    router_if_east_down.data = flit[i];
                    router_if_east_down.is_valid = 1;
                    $display("[%0t] Sending flit", $time);
                    $display("data=0x%h valid=%b", router_if_east_down.data, router_if_east_down.is_valid);
                end
                default: $error("[%0t]-Invalid up_router value: %0d", $time, up_router);
            endcase
        end

        @(negedge clk);
        for (int i = 0; i < 2; i++) begin
            case (up_router[i])
            LOCAL: begin
                router_if_local_down.is_valid = 0;
                router_if_local_down.data = '0; 
            end
            NORTH: begin
                router_if_north_down.is_valid = 0; 
                router_if_north_down.data = '0; 
            end
            SOUTH: begin
                router_if_south_down.is_valid = 0; 
                router_if_south_down.data = '0; 
            end
            WEST: begin
                router_if_west_down.is_valid = 0; 
                router_if_west_down.data = '0;
            end
            EAST: begin
                router_if_east_down.is_valid = 0;
                router_if_east_down.data = '0;
            end
                default: $error("[%0t]-Invalid up_router value: %0d", $time, up_router[i]); 
            endcase
        end
    
        @(posedge clk);
        
    end
    endtask


    task parallel_packet_test;
        port_t up_router [2];
        logic [DEST_ADDR_SIZE_X-1:0] x_dest [2];
        logic [DEST_ADDR_SIZE_Y-1:0] y_dest [2];
        flit_label_t label [2];
        logic [VC_SIZE-1:0] vc_id [2];
    begin

        $display("[%0t] Starting Parallel packet test...", $time);
        $display("-------------------------------");

        up_router[0] = SOUTH;
        up_router[1] = WEST;
        vc_id[0] = 0;
        vc_id[1] = 1;
        label[0] = HEAD;
        label[1] = HEAD;
        x_dest[0] = 0;
        y_dest[0] = 1;
        x_dest[1] = 0;
        y_dest[1] = 1;

        parallel_receive_flit(up_router, x_dest, y_dest, label, vc_id);
        parallel_receive_flit(up_router, x_dest, y_dest, '{BODY, BODY}, vc_id);
        parallel_receive_flit(up_router, x_dest, y_dest, '{TAIL, TAIL}, vc_id);
 
        repeat (6) @(posedge clk);
    end
    endtask

    task single_flit_test;
        begin
            $display("[%0t] Starting Single-flit packet test...", $time);
            $display("-------------------------------");
            repeat(2) @(posedge clk);
            receive_flit(LOCAL, 1, 1, HEADTAIL, 0, HEAD_PAYLOAD_SIZE'({$urandom,$urandom}), '0); // Local ejection
            repeat(5) @(posedge clk);
            receive_flit(LOCAL, 1, 0, HEADTAIL, 1, HEAD_PAYLOAD_SIZE'({$urandom,$urandom}), '0); //Single HEADTAIL Y routing - adaptive VC
            repeat(5) @(posedge clk);
            receive_flit(LOCAL, 1, 0, HEADTAIL, 1, HEAD_PAYLOAD_SIZE'({$urandom,$urandom}), '0); //Single HEADTAIL to test VC reuse
            repeat(5) @(posedge clk);
            receive_flit(NORTH, 0, 0, HEADTAIL, 0, HEAD_PAYLOAD_SIZE'({$urandom,$urandom}), '0); //Single HEADTAIL XY routing - escape VC
            repeat(5) @(posedge clk);
            receive_flit(NORTH, 0, 0, HEADTAIL, 0, HEAD_PAYLOAD_SIZE'({$urandom,$urandom}), '0); //Single HEADTAIL to test VC reuse
            repeat(5) @(posedge clk);
        end
    endtask

    task multi_flit_test;
        begin
            $display("[%0t] Starting Multi-flit packet test...", $time);
            $display("-------------------------------");
            receive_flit(LOCAL, 0, 0, HEAD, 1, HEAD_PAYLOAD_SIZE'({$urandom,$urandom}), '0); //Adaptive Routing - adaptive VC
            receive_flit(LOCAL, DEST_ADDR_SIZE_X'($urandom_range(0,MESH_SIZE_X-1)), DEST_ADDR_SIZE_Y'($urandom_range(0,MESH_SIZE_Y-1)), BODY, 1, '0, BODY_PAYLOAD_SIZE'({$urandom,$urandom})); //Body flit
            receive_flit(LOCAL, DEST_ADDR_SIZE_X'($urandom_range(0,MESH_SIZE_X-1)), DEST_ADDR_SIZE_Y'($urandom_range(0,MESH_SIZE_Y-1)), BODY, 1, '0, BODY_PAYLOAD_SIZE'({$urandom,$urandom})); //Body flit
            receive_flit(LOCAL, DEST_ADDR_SIZE_X'($urandom_range(0,MESH_SIZE_X-1)), DEST_ADDR_SIZE_Y'($urandom_range(0,MESH_SIZE_Y-1)), TAIL, 1, '0, BODY_PAYLOAD_SIZE'({$urandom,$urandom})); //Tail flit 
            repeat(5) @(posedge clk);
        end
    endtask

    task credit_stall_test;
        int before_stall;
        begin
            $display("[%0t] Starting Credit Stalling test...", $time);
            $display("-------------------------------");
            @(negedge clk);
            before_stall = received;
            credit_stall = 1; // Withhold returns until one VC's credits are exhausted
            receive_flit(NORTH, 0, 1, HEAD, 1, HEAD_PAYLOAD_SIZE'({$urandom,$urandom}), '0); // This flit will be accepted but credits will be stalled, causing backpressure
            receive_flit(NORTH, $urandom_range(0,MESH_SIZE_X-1), $urandom_range(0,MESH_SIZE_Y-1), BODY, 1, '0, BODY_PAYLOAD_SIZE'({$urandom,$urandom})); 
            receive_flit(NORTH, $urandom_range(0,MESH_SIZE_X-1), $urandom_range(0,MESH_SIZE_Y-1), BODY, 1, '0, BODY_PAYLOAD_SIZE'({$urandom,$urandom})); 
            receive_flit(NORTH, $urandom_range(0,MESH_SIZE_X-1), $urandom_range(0,MESH_SIZE_Y-1), BODY, 1, '0, BODY_PAYLOAD_SIZE'({$urandom,$urandom}));
            receive_flit(NORTH, $urandom_range(0,MESH_SIZE_X-1), $urandom_range(0,MESH_SIZE_Y-1), TAIL, 1, '0, BODY_PAYLOAD_SIZE'({$urandom,$urandom}));
            repeat (5) @(posedge clk);
            @(negedge clk);
            if (received-before_stall != VC_DEPTH) $fatal(1, "Credit stall did not stop the fifth flit");
            credit_stall = 0; // Return credits and allow the tail to continue
            repeat (6) @(posedge clk); 
        end
    endtask

    function automatic flit_t without_vc(input flit_t flit);
        flit.vc_id = 0;
        return flit;
    endfunction

    function automatic port_t xy_port(input flit_t flit);
        if (flit.data.head_data.x_dest < MESH_SIZE_X/2) return WEST;
        if (flit.data.head_data.x_dest > MESH_SIZE_X/2) return EAST;
        if (flit.data.head_data.y_dest < MESH_SIZE_Y/2) return SOUTH;
        if (flit.data.head_data.y_dest > MESH_SIZE_Y/2) return NORTH;
        return LOCAL;
    endfunction

    // Sample transfers on their accepting edge, rather than after FIFO updates.
    always @(posedge clk) begin
        if (reset_done && !rst) begin
            for (int p = 0; p < PORT_NUM; p++) begin
                if (error[p] != '0) $fatal(1, "Router error on input %0d", p);
                if (dut.is_valid_in[p]) begin
                    int v; v = int'(dut.data_in[p].vc_id);
                    if (sent == 64 || dut.input_block.is_full[p][v]) $fatal(1, "Router input/scoreboard full");
                    expected_flit[sent] = dut.data_in[p];
                    if (dut.data_in[p].flit_label == HEAD || dut.data_in[p].flit_label == HEADTAIL) begin
                        input_head[p][v] = sent;
                        input_last[p][v] = -1;
                    end
                    head_of[sent] = input_head[p][v]; previous[sent] = input_last[p][v];
                    input_last[p][v] = sent;
                    sent++;
                end
            end
            for (int p = 0; p < PORT_NUM; p++) if (dut.is_valid_out[p]) begin
                int match_id, h;
                flit_t flit;
                flit = dut.data_out[p]; match_id = -1;
                for (int i = 0; i < sent; i++) if (!arrived[i] && without_vc(expected_flit[i]) === without_vc(flit)) begin
                    match_id = i; break;
                end
                if (match_id < 0) $fatal(1, "Router duplicate or corrupted output");
                h = head_of[match_id];
                if (previous[match_id] >= 0 && !arrived[previous[match_id]]) $fatal(1, "Router reordered a packet");
                if (match_id == h) begin
                    if (dut.vc_allocator.ADAPTIVE_TIMEOUT == 0 || flit.vc_id == ESCAPE) begin
                        if (p != int'(xy_port(flit))) $fatal(1, "Output did not follow XY");
                    end
                    else if (!((p == WEST && flit.data.head_data.x_dest < MESH_SIZE_X/2) ||
                               (p == SOUTH && flit.data.head_data.y_dest < MESH_SIZE_Y/2) ||
                               (p == LOCAL && flit.data.head_data.x_dest == MESH_SIZE_X/2 && flit.data.head_data.y_dest == MESH_SIZE_Y/2)))
                        $fatal(1, "Adaptive output is not a minimal 2x2 route");
                    if (dut.vc_allocator.ADAPTIVE_TIMEOUT != 0 && expected_flit[h].vc_id == ESCAPE && flit.vc_id != ESCAPE)
                        $fatal(1, "Escape returned to adaptive");
                    routed_port[h] = p; routed_vc[h] = int'(flit.vc_id);
                end
                if (p != routed_port[h] || int'(flit.vc_id) != routed_vc[h]) $fatal(1, "Packet route/VC changed after HEAD");
                arrived[match_id] = 1; received++;
            end
        end
    end

    task wait_for_delivery;
    begin
        for (int i = 0; i < 100 && received != sent; i++) @(negedge clk);
        if (received != sent) $fatal(1, "Router did not drain: sent=%0d received=%0d", sent, received);
        repeat (3) @(negedge clk); // Let final credit and release pulses return.
    end
    endtask

    initial begin
        reset_dut();

        single_flit_test();
        wait_for_delivery();
        multi_flit_test();
        wait_for_delivery();
        credit_stall_test();
        wait_for_delivery();
        parallel_packet_test();
        wait_for_delivery();
        for (int p = 0; p < PORT_NUM; p++) for (int v = 0; v < VC_NUM; v++) begin
            if (dut.input_block.credits_counter[p][v] != VC_DEPTH || credits_pending[p][v] != 0)
                $fatal(1, "Router credits were not fully restored");
        end
        if (sent != 20) $fatal(1, "A basic router scenario was skipped");
        $display("Router basic tests PASSED: %0d flits delivered", received);
        $finish;
    end

    initial begin
        #(CLK_PERIOD*500);
        $fatal(1, "Router test timed out");
    end

endmodule

