`timescale 1ns/1ps

import noc_params::*;

module tb_mesh;

parameter CLK_PERIOD = 10;

logic clk;
logic rst;
logic reset_done;

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

    repeat (2) @(negedge clk);
    rst = 0;
    @(negedge clk) reset_done = 1;
    @(posedge clk);   
    #1 $display ("--------------------------\n[%0t]-DUT was reset!", $time);
    $display ("--------------------------\n");
end
endtask

always @(posedge clk) begin
    #2;
    $display("--------------------------\n[%0t]-Output Nodes:",$time);
    for (int row = 0; row < MESH_SIZE_Y; row++) begin
        for (int col = 0; col < MESH_SIZE_X; col++) begin
            if (data_o[col][row] != '0)
                $display("Data: 0x%h, X: %0d, Y: %0d", data_o[col][row], col, row);
            if (is_valid_o[col][row])
                $display("Valid: %b, X: %0d, Y: %0d", is_valid_o[col][row], col, row);
            if (credits_o[col][row] != '0)
                $display("Credits: %b, X: %0d, Y: %0d", credits_o[col][row], col, row);
            if (is_allocatable_o[col][row])
                $display("Allocatable %b, X: %0d, Y: %0d", is_allocatable_o[col][row], col, row);
        end
    end
    $display("--------------------------\n[%0t]-Input Nodes:",$time);
    for (int row = 0; row < MESH_SIZE_Y; row++) begin
        for (int col = 0; col < MESH_SIZE_X; col++) begin
            if (data_i[col][row] != '0)
                $display("Data: 0x%h, X: %0d, Y: %0d", data_i[col][row], col, row);
            if (is_valid_i[col][row])
                $display("Valid: %b, X: %0d, Y: %0d", is_valid_i[col][row], col, row);
            if (credits_i[col][row] != '0)
                $display("Credits: %b, X: %0d, Y: %0d", credits_i[col][row], col, row);
            if (is_allocatable_i[col][row])
                $display("Allocatable %b, X: %0d, Y: %0d", is_allocatable_i[col][row], col, row);
        end
    end
    $display("--------------------------\n");
end

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
    
    //headtail_injection(1, 1, 1, 2, 2);
    //headtail_injection(1, 1, 1, 2, 2);
    //multiflit_packet_injection(1,3,2,0,0);
    parallel_multiflit_packet_injection('{0,0},'{3,2},'{2,3},'{0,0},'{0,0});

    $finish;
end

endmodule