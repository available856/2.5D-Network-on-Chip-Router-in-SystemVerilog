`timescale 1ns/1ps

import noc_params::*;

module tb_mesh;

parameter CLK_PERIOD = 10;

logic clk;
logic rst;
logic reset_done;
// Small scoreboard for the basic packets below; vc_id may change at each hop.
flit_t expected_flit[64];
bit arrived[64];
int head_of[64], previous[64], output_vc[64];
int input_head[MESH_SIZE_X][MESH_SIZE_Y][VC_NUM], input_last[MESH_SIZE_X][MESH_SIZE_Y][VC_NUM];
int source_credit[MESH_SIZE_X][MESH_SIZE_Y][VC_NUM];
bit source_busy[MESH_SIZE_X][MESH_SIZE_Y][VC_NUM];
int sent = 0, received = 0;

logic [VC_NUM-1:0] error_o [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][PORT_NUM-1:0];

flit_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] data_o;
logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] is_valid_o;
credits_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] credits_o;
logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][VC_NUM-1:0] is_allocatable_o;


credits_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] credits_i;
logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][VC_NUM-1:0] is_allocatable_i;
flit_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] data_i;
logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] is_valid_i;

mesh dut (.*);

initial begin
    clk = 0;
    rst = 0;
    reset_done = 0;

    forever #(CLK_PERIOD/2) clk = ~clk;
end

task reset_dut;
begin
    @(negedge clk) rst = 1;

    data_i = '0;
    is_valid_i = '0;
    credits_i = '0;
    is_allocatable_i = '0;
    for (int x = 0; x < MESH_SIZE_X; x++) for (int y = 0; y < MESH_SIZE_Y; y++)
        for (int v = 0; v < VC_NUM; v++) source_credit[x][y][v] = VC_DEPTH;

    repeat (2) @(negedge clk);
    rst = 0;
    @(negedge clk) reset_done = 1;
    @(posedge clk);   
    #1 $display ("--------------------------\n[%0t]-DUT was reset!", $time);
    $display ("--------------------------\n");
end
endtask

function automatic flit_t without_vc(input flit_t flit);
    flit.vc_id = 0;
    return flit;
endfunction

// Sources obey credits and wait for a VC release before starting a new packet.
function automatic bit can_inject(input int x, y, v, input flit_label_t label);
    return source_credit[x][y][v] > 0 &&
        ((label == HEAD || label == HEADTAIL) ? !source_busy[x][y][v] : source_busy[x][y][v]);
endfunction

always @(posedge clk) begin
    if (reset_done && !rst) begin
        for (int x = 0; x < MESH_SIZE_X; x++) for (int y = 0; y < MESH_SIZE_Y; y++) begin
            for (int p = 0; p < PORT_NUM; p++) if (error_o[x][y][p] != '0) $fatal(1, "Mesh router error at (%0d,%0d)", x, y);
            for (int v = 0; v < VC_NUM; v++) begin
                if (credits_o[x][y][v]) source_credit[x][y][v]++;
                if (is_allocatable_o[x][y][v]) source_busy[x][y][v] = 0;
            end
            if (is_valid_i[x][y]) begin
                int v; v = int'(data_i[x][y].vc_id);
                if (sent == 64) $fatal(1, "Mesh scoreboard full");
                expected_flit[sent] = data_i[x][y];
                if (data_i[x][y].flit_label == HEAD || data_i[x][y].flit_label == HEADTAIL) begin
                    if (source_busy[x][y][v]) $fatal(1, "Source reused a busy VC");
                    source_busy[x][y][v] = 1;
                    input_head[x][y][v] = sent; input_last[x][y][v] = -1;
                end
                head_of[sent] = input_head[x][y][v]; previous[sent] = input_last[x][y][v];
                input_last[x][y][v] = sent;
                source_credit[x][y][v]--; sent++;
            end
            for (int v = 0; v < VC_NUM; v++) if (source_credit[x][y][v] < 0 || source_credit[x][y][v] > VC_DEPTH)
                $fatal(1, "Source credit mismatch");
        end
        for (int x = 0; x < MESH_SIZE_X; x++) for (int y = 0; y < MESH_SIZE_Y; y++) if (is_valid_o[x][y]) begin
            int match_id, h;
            flit_t flit;
            flit = data_o[x][y]; match_id = -1;
            for (int i = 0; i < sent; i++) if (!arrived[i] && without_vc(expected_flit[i]) === without_vc(flit)) begin
                match_id = i; break;
            end
            if (match_id < 0) $fatal(1, "Mesh duplicate or corrupted output");
            h = head_of[match_id];
            if (int'(expected_flit[h].data.head_data.x_dest) != x || int'(expected_flit[h].data.head_data.y_dest) != y)
                $fatal(1, "Packet reached the wrong destination");
            if (previous[match_id] >= 0 && !arrived[previous[match_id]]) $fatal(1, "Mesh reordered a packet");
            if (match_id == h) begin
                output_vc[h] = int'(flit.vc_id);
                if (dut.mesh_row[0].mesh_col[0].router_inst.vc_allocator.ADAPTIVE_TIMEOUT != 0 &&
                    expected_flit[h].vc_id == ESCAPE && flit.vc_id != ESCAPE)
                    $fatal(1, "Escape returned to adaptive");
            end
            if (int'(flit.vc_id) != output_vc[h]) $fatal(1, "Destination VC changed within a packet");
            arrived[match_id] = 1; received++;
        end
    end
end

// Check actual XY HEAD hops, including both VC classes when timeout is zero.
for (genvar y = 0; y < MESH_SIZE_Y; y++) begin: check_row
    for (genvar x = 0; x < MESH_SIZE_X; x++) begin: check_col
        always @(posedge clk) if (reset_done && !rst) begin
            for (int p = 0; p < PORT_NUM; p++) if (dut.mesh_row[y].mesh_col[x].router_inst.is_valid_out[p]) begin
                flit_t flit;
                port_t expected;
                flit = dut.mesh_row[y].mesh_col[x].router_inst.data_out[p];
                if ((dut.mesh_row[y].mesh_col[x].router_inst.vc_allocator.ADAPTIVE_TIMEOUT == 0 || flit.vc_id == ESCAPE) &&
                    (flit.flit_label == HEAD || flit.flit_label == HEADTAIL)) begin
                    if (flit.data.head_data.x_dest < x) expected = WEST;
                    else if (flit.data.head_data.x_dest > x) expected = EAST;
                    else if (flit.data.head_data.y_dest < y) expected = SOUTH;
                    else if (flit.data.head_data.y_dest > y) expected = NORTH;
                    else expected = LOCAL;
                    if (port_t'(p) != expected) $fatal(1, "Hop did not follow XY");
                end
            end
        end
    end
end

// Bounded drain checks also catch lost flits and permanent stalls.
task wait_for_delivery;
begin
    for (int i = 0; i < 100 && received != sent; i++) @(negedge clk);
    if (received != sent) $fatal(1, "Mesh did not drain: sent=%0d received=%0d", sent, received);
    repeat (3) @(negedge clk);
end
endtask

always @(posedge clk) begin
    automatic logic [VC_SIZE-1:0] vc_id = 0;
    credits_i <= '0;
    is_allocatable_i <= '0;
    for (int row = 0; row < MESH_SIZE_Y; row++) begin
        for (int col = 0; col < MESH_SIZE_X; col++) begin
            if (is_valid_o[col][row]) begin
                vc_id = data_o[col][row].vc_id;
                credits_i[col][row][vc_id] <= 1'b1;
                if (data_o[col][row].flit_label == HEADTAIL || data_o[col][row].flit_label == TAIL)
                    is_allocatable_i[col][row][vc_id] <= 1'b1;                
            end
        end
    end
end

task flit_injection (input logic [VC_SIZE-1:0] vc_id, input logic [DEST_ADDR_SIZE_X-1 : 0] x_cur,
       input logic [DEST_ADDR_SIZE_Y-1 : 0] y_cur, input logic [DEST_ADDR_SIZE_X-1 : 0] x_dest,
       input logic [DEST_ADDR_SIZE_Y-1 : 0] y_dest, input flit_label_t flit_label);
       automatic flit_t flit = '0; 
    begin
        flit.flit_label = flit_label;
        flit.vc_id = vc_id;
        if (flit_label == HEAD || flit_label == HEADTAIL) begin
            flit.data.head_data.x_dest = x_dest;
            flit.data.head_data.y_dest = y_dest;
            flit.data.head_data.head_pl = HEAD_PAYLOAD_SIZE'({$urandom,$urandom});
        end
        else begin
            flit.data = BODY_PAYLOAD_SIZE'({$urandom,$urandom});
        end

        @(negedge clk);
        while (!can_inject(int'(x_cur), int'(y_cur), int'(vc_id), flit_label)) @(negedge clk);
        $display("[%0t]-Inserting %s flit on VC %d with payload %h", $time, flit.flit_label.name(), vc_id, flit.data.head_data.head_pl);
        data_i[x_cur][y_cur] = flit;
        is_valid_i[x_cur][y_cur] = 1'b1;

        @(negedge clk);
        data_i[x_cur][y_cur] = '0;
        is_valid_i[x_cur][y_cur] = 1'b0;
    end
endtask

task double_flit_injection (input logic [VC_SIZE-1:0] vc_id [2], input logic [DEST_ADDR_SIZE_X-1 : 0] x_cur [2],
       input logic [DEST_ADDR_SIZE_Y-1 : 0] y_cur [2], input logic [DEST_ADDR_SIZE_X-1 : 0] x_dest [2],
       input logic [DEST_ADDR_SIZE_Y-1 : 0] y_dest[2], input flit_label_t flit_label[2]);
       automatic flit_t flit [2];
       for (int i = 0; i < 2; i++) begin
            flit[i] = '0;
       end
    begin
        for (int i = 0; i < 2; i++) begin
            flit[i].flit_label = flit_label[i];
            flit[i].vc_id = vc_id[i];
            if (flit_label[i] == HEAD || flit_label[i] == HEADTAIL) begin
                flit[i].data.head_data.x_dest = x_dest[i];
                flit[i].data.head_data.y_dest = y_dest[i];
                flit[i].data.head_data.head_pl = HEAD_PAYLOAD_SIZE'({$urandom,$urandom});
            end
            else begin
                flit[i].data = BODY_PAYLOAD_SIZE'({$urandom,$urandom});
            end    
        end
        
        @(negedge clk);
        while (!can_inject(int'(x_cur[0]), int'(y_cur[0]), int'(vc_id[0]), flit_label[0]) ||
               !can_inject(int'(x_cur[1]), int'(y_cur[1]), int'(vc_id[1]), flit_label[1])) @(negedge clk);
        for (int i = 0; i < 2; i++) begin
            $display("[%0t]-Inserting %s flit on VC %d with payload %h", $time, flit[i].flit_label.name(), vc_id[i], flit[i].data.head_data.head_pl);
            data_i[x_cur[i]][y_cur[i]] = flit[i];
            is_valid_i[x_cur[i]][y_cur[i]] = 1'b1;
        end
        

        @(negedge clk);
        for (int i = 0; i < 2; i++) begin
            data_i[x_cur[i]][y_cur[i]] = '0;
            is_valid_i[x_cur[i]][y_cur[i]] = 1'b0;
        end
        
    end
endtask

task headtail_injection (input logic [VC_SIZE-1:0] vc_id, input logic [DEST_ADDR_SIZE_X-1 : 0] x_cur,
       input logic [DEST_ADDR_SIZE_Y-1 : 0] y_cur, input logic [DEST_ADDR_SIZE_X-1 : 0] x_dest,
       input logic [DEST_ADDR_SIZE_Y-1 : 0] y_dest);
    begin
        flit_injection(vc_id, x_cur, y_cur, x_dest, y_dest, HEADTAIL);
        repeat (20) @(posedge clk);
    end
endtask

task multiflit_packet_injection (input logic [VC_SIZE-1:0] vc_id, input logic [DEST_ADDR_SIZE_X-1 : 0] x_cur,
       input logic [DEST_ADDR_SIZE_Y-1 : 0] y_cur, input logic [DEST_ADDR_SIZE_X-1 : 0] x_dest,
       input logic [DEST_ADDR_SIZE_Y-1 : 0] y_dest);
    begin
      flit_injection(vc_id, x_cur, y_cur, x_dest, y_dest, HEAD);
      flit_injection(vc_id, x_cur, y_cur, DEST_ADDR_SIZE_X'($urandom), DEST_ADDR_SIZE_Y'($urandom), BODY);
      flit_injection(vc_id, x_cur, y_cur, DEST_ADDR_SIZE_X'($urandom), DEST_ADDR_SIZE_Y'($urandom), BODY);
      flit_injection(vc_id, x_cur, y_cur, DEST_ADDR_SIZE_X'($urandom), DEST_ADDR_SIZE_Y'($urandom), BODY);
      flit_injection(vc_id, x_cur, y_cur, DEST_ADDR_SIZE_X'($urandom), DEST_ADDR_SIZE_Y'($urandom), TAIL);
      repeat (25) @(posedge clk);
    end
endtask

task parallel_multiflit_packet_injection (input logic [VC_SIZE-1:0] vc_id[2], input logic [DEST_ADDR_SIZE_X-1 : 0] x_cur[2],
       input logic [DEST_ADDR_SIZE_Y-1 : 0] y_cur[2], input logic [DEST_ADDR_SIZE_X-1 : 0] x_dest[2],
       input logic [DEST_ADDR_SIZE_Y-1 : 0] y_dest[2]);
    begin
      double_flit_injection(vc_id, x_cur, y_cur, x_dest, y_dest, '{HEAD,HEAD});
      double_flit_injection(vc_id, x_cur, y_cur, '{DEST_ADDR_SIZE_X'($urandom), DEST_ADDR_SIZE_X'($urandom)}, '{DEST_ADDR_SIZE_Y'($urandom), DEST_ADDR_SIZE_Y'($urandom)}, '{BODY,BODY});
      double_flit_injection(vc_id, x_cur, y_cur, '{DEST_ADDR_SIZE_X'($urandom), DEST_ADDR_SIZE_X'($urandom)}, '{DEST_ADDR_SIZE_Y'($urandom), DEST_ADDR_SIZE_Y'($urandom)}, '{BODY,BODY});
      double_flit_injection(vc_id, x_cur, y_cur, '{DEST_ADDR_SIZE_X'($urandom), DEST_ADDR_SIZE_X'($urandom)}, '{DEST_ADDR_SIZE_Y'($urandom), DEST_ADDR_SIZE_Y'($urandom)}, '{BODY,BODY});
      double_flit_injection(vc_id, x_cur, y_cur, '{DEST_ADDR_SIZE_X'($urandom), DEST_ADDR_SIZE_X'($urandom)}, '{DEST_ADDR_SIZE_Y'($urandom), DEST_ADDR_SIZE_Y'($urandom)}, '{TAIL,TAIL});
      repeat (40) @(posedge clk);
    end
endtask


initial begin
    reset_dut;
    
    // Single-flit escape, adaptive and local delivery in the 2x2 mesh.
    headtail_injection(ESCAPE, 1, 1, 0, 0);
    wait_for_delivery();
    headtail_injection(ADAPTIVE, 0, 0, 1, 1);
    wait_for_delivery();
    headtail_injection(ADAPTIVE, 1, 1, 1, 1);
    wait_for_delivery();

    // A packet longer than the FIFO depth, then two-source contention.
    multiflit_packet_injection(ADAPTIVE, 1, 1, 0, 0);
    wait_for_delivery();
    parallel_multiflit_packet_injection('{ADAPTIVE,ESCAPE},'{1,0},'{0,1},'{0,0},'{0,0});
    wait_for_delivery();
    parallel_multiflit_packet_injection('{ADAPTIVE,ADAPTIVE},'{0,1},'{0,1},'{1,0},'{1,0});
    wait_for_delivery();

    for (int x = 0; x < MESH_SIZE_X; x++) for (int y = 0; y < MESH_SIZE_Y; y++) for (int v = 0; v < VC_NUM; v++) begin
        if (source_credit[x][y][v] != VC_DEPTH || source_busy[x][y][v]) $fatal(1, "Source VC/credits were not restored");
    end
    if (sent != 28) $fatal(1, "A basic mesh scenario was skipped");
    $display("Mesh basic tests PASSED: %0d flits delivered", received);
    $finish;
end

initial begin
    #(CLK_PERIOD*1000);
    $fatal(1, "Mesh test timed out");
end

endmodule
