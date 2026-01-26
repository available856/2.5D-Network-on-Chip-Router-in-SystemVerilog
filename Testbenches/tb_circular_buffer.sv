`timescale 1ns/1ns

`include "circular_buffer.sv"

import noc_params::*;

module tb_circular_buffer;

    // --------------------------------------------------
    // Clock / Reset
    // --------------------------------------------------
    logic clk;
    logic rst;

    initial clk = 0;
    always #5 clk = ~clk;   // 100 MHz clock

    // --------------------------------------------------
    // DUT signals
    // --------------------------------------------------
    flit_t data_i;
    flit_t data_o;
    flit_t peek_o;

    logic read_i;
    logic write_i;
    logic is_full;
    logic is_empty;

    // --------------------------------------------------
    // Instantiate DUT
    // --------------------------------------------------
    circular_buffer #(
        .BUFFER_SIZE(VC_DEPTH)
    ) dut (.*);

    // --------------------------------------------------
    // Test sequence
    // --------------------------------------------------
    initial begin
        // Default values
        rst =     1;
        read_i =  0;
        write_i=  0;
        data_i = '0;

        // Hold reset for a couple of cycles
        repeat (2) @(posedge clk);
        rst <= 0;

      $display("[%0t]---- Reset released ----",$time);

        // --------------------------------------------------
        // Write 4 flits
        // --------------------------------------------------
      repeat (VC_DEPTH) begin
            @(posedge clk);
          
            write_i <= 1;
            data_i.flit_label <= HEAD;   // label not functionally important here
            data_i.data.bt_pl <= $random;
          #1 $display("[%0t] WRITE flit = %h", $time,data_i.data.bt_pl);
        end

        @(posedge clk);
        write_i <= 0;//Stop Writing
      
      // CHECK: Buffer should be FULL now
        #1;
        if (is_full) $display("[%0t] SUCCESS: Buffer is FULL.", $time);
        else         $error("[%0t] FAIL: Buffer should be full!", $time);

        // --------------------------------------------------
        // Observe peek (non-destructive)
        // --------------------------------------------------
        @(posedge clk);
        $display("[%0t] PEEK flit = %h (is_empty=%0d)",
                 $time, peek_o.data.bt_pl, is_empty);
      
       // --------------------------------------------------
        // Read 2 flits back
        // --------------------------------------------------
      repeat (2) begin
            @(posedge clk);
            read_i <= 1;

            @(posedge clk); // data_o updates on read
            read_i <= 0;

         #1 $display("[%0t] READ flit = %h (is_empty=%0d)",
                     $time, data_o.data.bt_pl, is_empty);  
          
        end

       // --------------------------------------------------
        // Write 2 flits
        // --------------------------------------------------
      repeat (2) begin
            @(posedge clk);
          
            write_i <= 1;
            data_i.flit_label <= HEAD;   // label not functionally important here
            data_i.data.bt_pl <= $random;
          #1 $display("[%0t] WRITE flit = %h", $time,data_i.data.bt_pl);
        end

        @(posedge clk);
        write_i <= 0;
      

        // --------------------------------------------------
        // Final state
        // --------------------------------------------------
        @(posedge clk);
        $display("[%0t] DONE (is_empty=%0d, is_full=%0d)",
                 $time, is_empty, is_full);

        $finish;
    end

endmodule
