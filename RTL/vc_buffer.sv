`timescale 1ns/1ps

import noc_params::*;

module vc_buffer #(

parameter BUFFER_SIZE = VC_DEPTH

)(

input flit_t data_i,

input read_i,

input write_i,

input [VC_SIZE-1:0] vc_new_i,

input vc_valid_i,

input port_t out_port_i,

input rst,

input clk,

output flit_t data_o,

output flit_t peek_o,

output logic is_full_o,

output logic is_empty_o,

output port_t out_port_o,

output logic vc_request_o,

output logic switch_request_o,

output logic vc_allocatable_o,

output logic [VC_SIZE-1:0] downstream_vc_o,

output logic error_o

);

enum logic [1:0] {IDLE, RC, VA, SA} ss, ss_next;

logic [VC_SIZE-1:0] downstream_vc_next;



logic read_cmd, write_cmd;

logic end_packet, end_packet_next;

logic vc_allocatable_next;

logic error_next;

port_t latched_out_port;

port_t out_port_next;


//flit_t peek_flit;

//flit_t read_flit;




/*
 VC Input Buffer (vc_buffer)

 - Single input Virtual Channel buffer for a wormhole NoC router.
 - Buffering is decoupled from control: flits may be buffered regardless of FSM
   state, subject only to buffer space (credit-based flow control).
 - FSM reacts only to architectural events:
       * write_cmd (successful write)
       * read_cmd  (successful read)
       * buffer occupancy (is_empty_o)
 - write_i / read_i represent intent only and are never used for protocol logic.

 Assumptions:
 - FIFO provides First-Word-Fall-Through (FWFT) semantics:
       * if is_empty_o == 0, peek_o is valid.
 - Exactly one packet may occupy this VC at a time.
*/



circular_buffer #(

    .BUFFER_SIZE(BUFFER_SIZE)

)

circular_buffer (

    .data_i(data_i),

    .read_i(read_cmd),

    .write_i(write_cmd),

    .rst(rst),

    .clk(clk),

    .data_o(data_o),

    .peek_o(peek_o),

    .is_full(is_full_o),

    .is_empty(is_empty_o)

);


/*
 Sequential state update:
 - Registers FSM state, routing decision, downstream VC, and packet tracking.
 - end_packet indicates that the tail flit of the current packet is about to be
   buffered (post-posedge) and not yet dequeued.
 - vc_allocatable_o is a one-cycle pulse when the VC is released.
*/

always_ff @(posedge clk, posedge rst)

begin

    if(rst)

    begin

        ss                  <= IDLE;

        out_port_o          <= LOCAL;

        downstream_vc_o     <= 0;

        end_packet          <= 0;

        vc_allocatable_o    <= 0;

        error_o             <= 0;

    end

    else

    begin

        ss                  <= ss_next;

        out_port_o          <= out_port_next;

        downstream_vc_o     <= downstream_vc_next;

        end_packet          <= end_packet_next;

        vc_allocatable_o    <= vc_allocatable_next;

        error_o             <= error_next;

    end

end



/*
 Latch output port only when a HEAD/HEADTAIL flit is successfully written.
 Prevents dependence on transient upstream routing signals.
*/

always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            latched_out_port <= LOCAL;
        end
        else if (write_cmd && (data_i.flit_label == HEAD || data_i.flit_label == HEADTAIL)) begin
            latched_out_port <= out_port_i;
        end
    end


/*
 Architectural event signals:
 - write_cmd: flit successfully inserted into FIFO.
 - read_cmd : flit successfully removed from FIFO.
 FSM reasoning is based exclusively on these signals.
*/

assign write_cmd = write_i && !is_full_o;
assign read_cmd = read_i && !is_empty_o;



/*
 VC Control FSM

 IDLE:
   - VC inactive. Transition to RC when FIFO becomes non-empty.

 RC:
   - Exactly one unvalidated flit present.
   - peek_o must be HEAD or HEADTAIL (FWFT assumed).
   - Output port is finalized here.

 VA:
   - Header validated.
   - Requests downstream VC.
   - BODY/TAIL flits may continue buffering.
   - end_packet prevents packet interleaving.

 SA:
   - Downstream VC allocated.
   - Flits may traverse switch.
   - VC released when tail flit is dequeued.

 Notes:
 - peek_o is used only for control.
 - data_i is considered only when write_cmd is asserted.
 - All protocol correctness is enforced here.
*/



always_comb

begin



    ss_next = ss;

    out_port_next = out_port_o;

    downstream_vc_next = downstream_vc_o;



    //read_cmd = 0;

    //write_cmd = 0;



    end_packet_next = end_packet;

    error_next = 0;



    vc_request_o = 0;

    switch_request_o = 0;

    vc_allocatable_next = 0;



    unique case(ss)

        IDLE:

        begin

          if (!is_empty_o)
          
            begin
              ss_next = RC;
            end
            


          if (vc_valid_i || read_cmd)
            begin
              error_next = 1;
              ss_next = IDLE;
            end

          if (write_cmd && data_i.flit_label == HEADTAIL)
            begin
              end_packet_next = 1;
            end

        end

        /*
        The vc_buffer assumes that the upstream logic only presents 
        a HEAD or HEADTAIL flit as the first flit of a packet. 
        Any violation is detected in RC and flagged as error.
        */

        RC: 
        
        begin
        
          if (peek_o.flit_label == HEAD || peek_o.flit_label == HEADTAIL)
            begin
              ss_next = VA;
              out_port_next = latched_out_port;
            end
        
          if (vc_valid_i || read_cmd || peek_o.flit_label == BODY || peek_o.flit_label == TAIL)
            begin
              error_next = 1;
              ss_next = IDLE;
            end
        
        end
        
        VA:

        begin

            if(vc_valid_i)

            begin

                ss_next = SA;

                downstream_vc_next = vc_new_i;

            end



            vc_request_o = 1;


            if((write_cmd && (end_packet || data_i.flit_label == HEAD || data_i.flit_label == HEADTAIL)) || read_cmd)

            begin

                error_next = 1;
                ss_next = VA;

            end

            if(write_cmd && data_i.flit_label == TAIL)

            begin

                end_packet_next = 1;

            end

        end



        SA:

        begin

            if(read_cmd && (peek_o.flit_label == TAIL || peek_o.flit_label == HEADTAIL))

            begin

                ss_next = IDLE;

                vc_allocatable_next = 1;

                end_packet_next = 0;

            end



            if(!is_empty_o)

            begin

                switch_request_o = 1;

            end


            if(vc_valid_i || (write_cmd && (end_packet || data_i.flit_label == HEAD || data_i.flit_label == HEADTAIL)))

            begin

                error_next = 1;

            end

            if(write_cmd && data_i.flit_label == TAIL)

            begin

                end_packet_next = 1;

            end

        end



        default:

        begin

            ss_next = IDLE;

            vc_allocatable_next = 1;

            error_next = 1;

            end_packet_next = 0;

        end



    endcase

end

endmodule