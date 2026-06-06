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

    vc_class_t vc_class_o;

    flit_t expected_q[$];
    int error_count = 0;

    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------
    vc_buffer #(
        .BUFFER_SIZE(BUFFER_SIZE),
        .VC_ID(0) // Set VC_ID to 0 for ESCAPE class
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
            @(negedge clk);
            rst = 1;
            write_i = 0;
            read_i = 0;
            vc_valid_i = 0;
            data_i = '0;
            out_port_i = LOCAL;
            @(negedge clk);
            rst = 0;
            @(negedge clk);
        end
    endtask


    task send_flit(input flit_label_t label, input logic [BODY_PAYLOAD_SIZE-1:0] data, input logic [VC_SIZE-1:0] vc_id,
        input port_t out_port);
        out_port_i = LOCAL; // Default to LOCAL for non-HEAD flits
        begin
            wait(!is_full_o);
            @(negedge clk);
            write_i = 1;
            data_i = flit_t'({label, vc_id, data});

            if (label == HEAD || label == HEADTAIL)
                out_port_i = out_port; // Set output port for the packet

            expected_q.push_back(data_i);
            $display("Data pushed to queue. -- [%0t]", $time);

            @(negedge clk);
            write_i = 0;
        end
    endtask

    task    validate_port (input port_t expected_port);
        begin
            if (out_port_o !== expected_port) begin
                $display("[FAIL] Output port mismatch! Expected: %0d, Got: %0d -- [%0t]", expected_port, out_port_o, $time);
                error_count++;
            end 
            else
                $display("[PASS] Correct output port %0d -- [%0t]", expected_port.name(), $time);
        end
    endtask

    task grant_vc(input logic [VC_SIZE-1:0] id);
        begin
            wait(vc_request_o);
            @(negedge clk);
            vc_valid_i = 1;
            vc_new_i = id;
            @(negedge clk);
            vc_valid_i = 0;
        end
    endtask


    task consume_flits(input int count);
        flit_t expected_flit;
        begin
            for (int i = 0; i < count; i++) begin
                wait(switch_request_o);
                @(negedge clk);
                read_i = 1;
                @(negedge clk);
                read_i = 0;

            if (expected_q.size() == 0) begin
                $display("[FAIL] Queue empty but DUT produced data!--[%0t]", $time);
                error_count++;
            end 

            else begin
                expected_flit = expected_q.pop_front();
                expected_flit.vc_id = dut.downstream_vc_o;
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

        send_flit(HEAD, VC_SIZE'($urandom), BODY_PAYLOAD_SIZE'($urandom), NORTH); // Set output port for the packet
        grant_vc(0);
        validate_port(NORTH);
        send_flit(BODY, VC_SIZE'($urandom), BODY_PAYLOAD_SIZE'($urandom), NORTH);
        send_flit(TAIL, VC_SIZE'($urandom), BODY_PAYLOAD_SIZE'($urandom), NORTH);

        consume_flits(3);

        wait(vc_allocatable_o);
            $display("[PASS] Standard packet released VC-[%0t]", $time);

        #(CLK_PERIOD*3);

        // --------------------------------------------------------
        // 2. Single-Flit Packet (HEADTAIL)
        // --------------------------------------------------------
        $display("Scenario 2: HEADTAIL-[%0t]", $time);

        send_flit(HEADTAIL, VC_SIZE'($urandom), BODY_PAYLOAD_SIZE'($urandom), EAST); // Set output port for the packet    
        grant_vc(1);
        validate_port(EAST);
        consume_flits(1);

        wait(vc_allocatable_o);
            $display("[PASS] HEADTAIL released VC-[%0t]", $time);

        #(CLK_PERIOD*3);

        // --------------------------------------------------------
        // 3. Illegal HEAD During Active Packet
        // --------------------------------------------------------
        $display("Scenario 3: Illegal interleaving-[%0t]", $time);

        send_flit(HEAD, VC_SIZE'($urandom), BODY_PAYLOAD_SIZE'($urandom), SOUTH); // Set output port for the packet
        grant_vc(0);
        validate_port(SOUTH);

        wait(switch_request_o);

        send_flit(HEAD, VC_SIZE'($urandom), BODY_PAYLOAD_SIZE'($urandom), SOUTH); // Illegal HEAD while first packet is active

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
