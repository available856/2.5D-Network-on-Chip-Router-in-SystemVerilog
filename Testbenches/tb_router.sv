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

        // 2. IMMEDIATE VC Release
        if (router_if_local_up.is_valid && (router_if_local_up.data.flit_label == TAIL || router_if_local_up.data.flit_label == HEADTAIL))
            router_if_local_up.is_allocatable[router_if_local_up.data.vc_id] <= 1'b1;

        if (router_if_north_up.is_valid && (router_if_north_up.data.flit_label == TAIL || router_if_north_up.data.flit_label == HEADTAIL))
            router_if_north_up.is_allocatable[router_if_north_up.data.vc_id] <= 1'b1;

        if (router_if_south_up.is_valid && (router_if_south_up.data.flit_label == TAIL || router_if_south_up.data.flit_label == HEADTAIL))
            router_if_south_up.is_allocatable[router_if_south_up.data.vc_id] <= 1'b1;

        if (router_if_west_up.is_valid && (router_if_west_up.data.flit_label == TAIL || router_if_west_up.data.flit_label == HEADTAIL))
            router_if_west_up.is_allocatable[router_if_west_up.data.vc_id] <= 1'b1;

        if (router_if_east_up.is_valid && (router_if_east_up.data.flit_label == TAIL || router_if_east_up.data.flit_label == HEADTAIL))
            router_if_east_up.is_allocatable[router_if_east_up.data.vc_id] <= 1'b1;



        // 3. Credit Stalling Logic
        // --- LOCAL ---
        if (credit_stall) begin
            if (router_if_local_up.is_valid) 
                credits_pending[LOCAL][router_if_local_up.data.vc_id] <= credits_pending[LOCAL][router_if_local_up.data.vc_id] + 1;
        end 
        else begin
            // Drain backlog (max 1 credit per cycle per VC)
            for (int vc = 0; vc < VC_NUM; vc++) begin
                if (credits_pending[LOCAL][vc] > 0) begin
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
                if (credits_pending[NORTH][vc] > 0) begin
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
                if (credits_pending[SOUTH][vc] > 0) begin
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
                if (credits_pending[WEST][vc] > 0) begin
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
                if (credits_pending[EAST][vc] > 0) begin
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
            body_dest_x[i] = DEST_ADDR_SIZE_X'($urandom_range(0,3));
            body_test_y[i] = DEST_ADDR_SIZE_Y'($urandom_range(0,3));
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
        x_dest[0] = 3;
        y_dest[0] = 2;
        x_dest[1] = 3;
        y_dest[1] = 2;

        parallel_receive_flit(up_router, x_dest, y_dest, label, vc_id);
        parallel_receive_flit(up_router, x_dest, y_dest, '{BODY, BODY}, vc_id);
        parallel_receive_flit(up_router, x_dest, y_dest, '{TAIL, TAIL}, vc_id);
 
        repeat (10) @(posedge clk);
    end
    endtask

    task single_flit_test;
        begin
            $display("[%0t] Starting Single-flit packet test...", $time);
            $display("-------------------------------");
            repeat(2) @(posedge clk);
            receive_flit(LOCAL, 2, 3, HEADTAIL, 1, HEAD_PAYLOAD_SIZE'({$urandom,$urandom}), '0); //Single HEADTAIL Y routing - adaptive VC
            repeat(5) @(posedge clk);
            receive_flit(LOCAL, 2, 3, HEADTAIL, 1, HEAD_PAYLOAD_SIZE'({$urandom,$urandom}), '0); //Single HEADTAIL to test VC reuse
            repeat(5) @(posedge clk);
            receive_flit(NORTH, 1, 0, HEADTAIL, 0, HEAD_PAYLOAD_SIZE'({$urandom,$urandom}), '0); //Single HEADTAIL XY routing - escape VC
            repeat(5) @(posedge clk);
            receive_flit(NORTH, 1, 0, HEADTAIL, 0, HEAD_PAYLOAD_SIZE'({$urandom,$urandom}), '0); //Single HEADTAIL to test VC reuse
            repeat(5) @(posedge clk);
        end
    endtask

    task multi_flit_test;
        begin
            $display("[%0t] Starting Multi-flit packet test...", $time);
            $display("-------------------------------");
            receive_flit(LOCAL, 3, 3, HEAD, 1, HEAD_PAYLOAD_SIZE'({$urandom,$urandom}), '0); //Adaptive Routing - adaptive VC
            receive_flit(LOCAL, DEST_ADDR_SIZE_X'($urandom_range(0,3)), DEST_ADDR_SIZE_Y'($urandom_range(0,3)), BODY, 1, '0, BODY_PAYLOAD_SIZE'({$urandom,$urandom})); //Body flit
            receive_flit(LOCAL, DEST_ADDR_SIZE_X'($urandom_range(0,3)), DEST_ADDR_SIZE_Y'($urandom_range(0,3)), BODY, 1, '0, BODY_PAYLOAD_SIZE'({$urandom,$urandom})); //Body flit
            receive_flit(LOCAL, DEST_ADDR_SIZE_X'($urandom_range(0,3)), DEST_ADDR_SIZE_Y'($urandom_range(0,3)), TAIL, 1, '0, BODY_PAYLOAD_SIZE'({$urandom,$urandom})); //Tail flit 
            repeat(2) @(posedge clk);
        end
    endtask

    task credit_stall_test;
        begin
            $display("[%0t] Starting Credit Stalling test...", $time);
            $display("-------------------------------");
            credit_stall = 1; // Enable credit stalling
            receive_flit(NORTH, 1, 1, HEAD, 1, HEAD_PAYLOAD_SIZE'({$urandom,$urandom}), '0); // This flit will be accepted but credits will be stalled, causing backpressure
            receive_flit(NORTH, $urandom_range(0,3), $urandom_range(0,3), BODY, 1, '0, BODY_PAYLOAD_SIZE'({$urandom,$urandom})); 
            receive_flit(NORTH, $urandom_range(0,3), $urandom_range(0,3), BODY, 1, '0, BODY_PAYLOAD_SIZE'({$urandom,$urandom})); 
            receive_flit(NORTH, $urandom_range(0,3), $urandom_range(0,3), BODY, 1, '0, BODY_PAYLOAD_SIZE'({$urandom,$urandom}));
            receive_flit(NORTH, $urandom_range(0,3), $urandom_range(0,3), TAIL, 1, '0, BODY_PAYLOAD_SIZE'({$urandom,$urandom}));
            repeat (5) @(posedge clk);
            credit_stall = 0; // Disable credit stalling to allow backlogged credits to be processed
            repeat (6) @(posedge clk); 
        end
    endtask

    always_ff @(posedge clk) begin
        #2;
        if (reset_done) begin
            $display("[%0t]-Upstream links Status:", $time);
            $display("LOCAL UP: data=0x%h, is_valid=%b, credits=%b, is_allocatable=%b", router_if_local_up.data, router_if_local_up.is_valid, router_if_local_up.credits, router_if_local_up.is_allocatable);
            $display("NORTH UP: data=0x%h, is_valid=%b, credits=%b, is_allocatable=%b", router_if_north_up.data, router_if_north_up.is_valid, router_if_north_up.credits, router_if_north_up.is_allocatable);
            $display("SOUTH UP: data=0x%h, is_valid=%b, credits=%b, is_allocatable=%b", router_if_south_up.data, router_if_south_up.is_valid, router_if_south_up.credits, router_if_south_up.is_allocatable);
            $display("WEST UP: data=0x%h, is_valid=%b, credits=%b, is_allocatable=%b", router_if_west_up.data, router_if_west_up.is_valid, router_if_west_up.credits, router_if_west_up.is_allocatable);
            $display("EAST UP: data=0x%h, is_valid=%b, credits=%b, is_allocatable=%b", router_if_east_up.data, router_if_east_up.is_valid, router_if_east_up.credits, router_if_east_up.is_allocatable);
            $display("[%0t]-Downstream links Status:", $time);
            $display("LOCAL DOWN: data=0x%h, is_valid=%b, credits=%b, is_allocatable=%b", router_if_local_down.data, router_if_local_down.is_valid, router_if_local_down.credits, router_if_local_down.is_allocatable);
            $display("NORTH DOWN: data=0x%h, is_valid=%b, credits=%b, is_allocatable=%b", router_if_north_down.data, router_if_north_down.is_valid, router_if_north_down.credits, router_if_north_down.is_allocatable);
            $display("SOUTH DOWN: data=0x%h, is_valid=%b, credits=%b, is_allocatable=%b", router_if_south_down.data, router_if_south_down.is_valid, router_if_south_down.credits, router_if_south_down.is_allocatable);
            $display("WEST DOWN: data=0x%h, is_valid=%b, credits=%b, is_allocatable=%b", router_if_west_down.data, router_if_west_down.is_valid, router_if_west_down.credits, router_if_west_down.is_allocatable);
            $display("EAST DOWN: data=0x%h, is_valid=%b, credits=%b, is_allocatable=%b", router_if_east_down.data, router_if_east_down.is_valid, router_if_east_down.credits, router_if_east_down.is_allocatable);
            $display("------------------------------\n");

            for (int i = 0; i < PORT_NUM; i++) begin
                for (int j = 0; j < VC_NUM; j++) begin
                    if (error[i][j]) begin
                        $error("[%0t]-Error detected on port %0d, VC %0d", $time, i, j);
                    end
                end
            end

        end
    end

    initial begin
        reset_dut();

        single_flit_test();
        multi_flit_test();
        credit_stall_test();
        parallel_packet_test();



        $finish;
    end

endmodule

