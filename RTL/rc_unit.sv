import noc_params::*;

module rc_unit #(
    parameter int unsigned X_CURRENT = MESH_SIZE_X/2,
    parameter int unsigned Y_CURRENT = MESH_SIZE_Y/2
)(
    input logic [DEST_ADDR_SIZE_X-1 : 0] x_dest_i,
    input logic [DEST_ADDR_SIZE_Y-1 : 0] y_dest_i,
    //input vc_class_t vc_class_i,
    input logic rc_valid_i,
    output logic [PORT_NUM-1:0] adaptive_port_set,
    output logic [PORT_NUM-1:0] escape_port_set
);

    logic go_north, go_south, go_west, go_east, stay_local;
    localparam logic [DEST_ADDR_SIZE_X-1 : 0] X_CUR = DEST_ADDR_SIZE_X'(X_CURRENT);
    localparam logic [DEST_ADDR_SIZE_Y-1 : 0] Y_CUR = DEST_ADDR_SIZE_Y'(Y_CURRENT);


    /*
    Combinational logic:
    - the route computation follows a DOR (Dimension-Order Routing) algorithm,
      with the nodes of the Network-on-Chip arranged in a 2D mesh structure,
      hence with 5 inputs and 5 outputs per node (except for boundary routers),
      i.e., both for input and output:
        * left, right, up and down links to the adjacent nodes
        * one link to the end node
    - the 2D Mesh coordinates scheme is mapped as following:
        * X increasing from Left to Right
        * Y increasing from  Down to Up
    - the output port encoding is as follows:
            LOCAL = 0, NORTH = 1, SOUTH = 2, WEST = 3, EAST = 4
    */

    /* verilator lint_off UNSIGNED */
    /* verilator lint_off CMPCONST */

    always_comb
    begin
        adaptive_port_set = '0;
        escape_port_set = '0;
        go_north = 0;
        go_south = 0;
        go_west = 0;
        go_east = 0;
        stay_local = 0;
        
        if (rc_valid_i) begin

            go_north = (y_dest_i > Y_CUR);
            go_south = (y_dest_i < Y_CUR);
            go_west = (x_dest_i < X_CUR);
            go_east = (x_dest_i > X_CUR);
            stay_local = (x_dest_i == X_CUR) && (y_dest_i == Y_CUR);

            
            //ESCAPE OUTPORT MASK SET
            if (go_west) begin
                escape_port_set[WEST] = 1'b1; // Only WEST is eligible
            end 
            else if (go_east) begin
                escape_port_set[EAST] = 1'b1; // Only EAST is eligible
            end 
            else if (go_north) begin
                escape_port_set[NORTH] = 1'b1; // Only NORTH is eligible
            end 
            else if (go_south) begin
                escape_port_set[SOUTH] = 1'b1; // Only SOUTH is eligible
            end 
            else begin
                escape_port_set[LOCAL] = 1'b1; // Only LOCAL is eligible
            end

            //ADAPTIVE OUTPORT MASK SET
            if (go_west)  adaptive_port_set[WEST]  = 1'b1;
            if (go_east)  adaptive_port_set[EAST]  = 1'b1;
            if (go_north) adaptive_port_set[NORTH] = 1'b1;
            if (go_south) adaptive_port_set[SOUTH] = 1'b1;
            if (stay_local) adaptive_port_set[LOCAL] = 1'b1;
                
        end

    end

    /* verilator lint_on CMPCONST */
    /* verilator lint_on UNSIGNED */
        

endmodule
