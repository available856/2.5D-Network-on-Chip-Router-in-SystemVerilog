`timescale 1ns/1ps

import noc_params::*;

module tb_vc_buffer;

    // ------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------
    parameter CLK_PERIOD  = 10;
    parameter BUFFER_SIZE = VC_DEPTH;

    // ------------------------------------------------------------
    // Signals
    // ------------------------------------------------------------
    logic clk;
    logic rst;

    flit_t data_i;
    logic  write_i;
    logic  read_i;

    logic [VC_SIZE-1:0] vc_new_i;
    logic vc_valid_i;
    port_t out_port_i;

    flit_t data_o;
    flit_t peek_o;

    logic  is_full_o;
    logic  is_empty_o;

    port_t out_port_o;

    logic vc_request_o;
    logic switch_request_o;
    logic vc_allocatable_o;
    logic [VC_SIZE-1:0] downstream_vc_o;
    logic error_o;

    flit_t expected_q[$];
    int error_count = 0;

    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------
    vc_buffer #(
        .BUFFER_SIZE(BUFFER_SIZE)
    ) dut (.*);

    // ------------------------------------------------------------
    // Clock
    // ------------------------------------------------------------
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // ------------------------------------------------------------
    // Tasks
    // ------------------------------------------------------------

    task reset_dut();
        begin
            rst = 1;
            write_i = 0;
            read_i = 0;
            vc_valid_i = 0;
            data_i = '0;
            #(CLK_PERIOD*2);
            rst = 0;
            #(CLK_PERIOD*2);
        end
    endtask


    task send_flit(input flit_label_t label, input logic [BODY_PAYLOAD_SIZE-1:0] data);
        begin
            wait(!is_full_o);
            @(posedge clk);
            write_i = 1;
            data_i = flit_t'({label, data});

            if (data_i.flit_label == HEAD || data_i.flit_label == HEADTAIL)
                out_port_i = NORTH;

            expected_q.push_back(data_i);
            $display("Data pushed to queue. -- [%0t]", $time);

            @(posedge clk);
            write_i = 0;
        end
    endtask


    task grant_vc(input logic [VC_SIZE-1:0] id);
        begin
            wait(vc_request_o);
            @(posedge clk);
            vc_valid_i = 1;
            vc_new_i = id;
            @(posedge clk);
            vc_valid_i = 0;
        end
    endtask


    task consume_flits(input int count);
        flit_t expected_flit;
        begin
            for (int i = 0; i < count; i++) begin
                wait(switch_request_o);
                @(posedge clk);
                read_i = 1;
                @(posedge clk);
                read_i = 0;

            if (expected_q.size() == 0) begin
                $display("[FAIL] Queue empty but DUT produced data!--[%0t]", $time);
                error_count++;
            end 

            else begin
                expected_flit = expected_q.pop_front();
                $display("Data extracted from queue. -- [%0t]", $time);
                if (data_o !== expected_flit) begin
                    $display("[FAIL] Data mismatch! Expected: %h, Got: %h --[%0t]", expected_flit, data_o, $time);
                    error_count++;
            end
            end
            end
        end
    endtask

    // ------------------------------------------------------------
    // Test Sequence
    // ------------------------------------------------------------
    initial begin
        $display("\n--- VC Buffer Basic Test ---[%0t]", $time);
        reset_dut();

        // --------------------------------------------------------
        // 1. Standard Packet (HEAD -> BODY -> TAIL)
        // --------------------------------------------------------
        $display("Scenario 1: Standard packet-[%0t]", $time);

        send_flit(HEAD, {2'b00, 60'hAAAAAAAAAAAAAAA});
        grant_vc(2);
        send_flit(BODY, {2'b00, 60'hBBBBBBBBBBBBBBB});
        send_flit(TAIL, {2'b00, 60'hCCCCCCCCCCCCCCC});

        consume_flits(3);

        wait (vc_allocatable_o)
            $display("[PASS] Standard packet released VC-[%0t]", $time);

        #(CLK_PERIOD*3);

        // --------------------------------------------------------
        // 2. Single-Flit Packet (HEADTAIL)
        // --------------------------------------------------------
        $display("Scenario 2: HEADTAIL-[%0t]", $time);

        send_flit(HEADTAIL, {2'b00, 60'hDEADBEEFDEADBEF});
        grant_vc(1);
        consume_flits(1);

        wait (vc_allocatable_o)
            $display("[PASS] HEADTAIL released VC-[%0t]", $time);

        #(CLK_PERIOD*3);

        // --------------------------------------------------------
        // 3. Illegal HEAD During Active Packet
        // --------------------------------------------------------
        $display("Scenario 3: Illegal interleaving-[%0t]", $time);

        send_flit(HEAD, {2'b00, 60'h111111111111111});
        grant_vc(3);

        wait(switch_request_o);

        send_flit(HEAD, {2'b00, 60'h222222222222222}); // Illegal HEAD while first packet is active

       wait(error_o);
            $display("[PASS] Illegal HEAD correctly flagged-[%0t]", $time);
            expected_q.delete();

        #(CLK_PERIOD*5);
        
        if (error_count == 0)
            $display("\n[PASS] All tests passed! ---[%0t]", $time);
        else
            $display("\n[FAIL] %0d errors detected! ---[%0t]", error_count, $time);

        $display("\n--- Test Finished ---[%0t]", $time);
        $finish;
    end

endmodule
