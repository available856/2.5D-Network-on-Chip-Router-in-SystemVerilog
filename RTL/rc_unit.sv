import noc_params::*;

module rc_unit #(
    parameter X_CURRENT = 0,
    parameter Y_CURRENT = 0,
    parameter DEST_ADDR_SIZE_X = $clog2(MESH_SIZE_X),
    parameter DEST_ADDR_SIZE_Y = $clog2(MESH_SIZE_Y)
)(
    input logic [DEST_ADDR_SIZE_X-1 : 0] x_dest_i,
    input logic [DEST_ADDR_SIZE_Y-1 : 0] y_dest_i,
    input vc_class_t vc_class_i,
    output logic [PORT_NUM-1:0] eligible_port_set // Output port eligibility mask for this (port_id, vc_id) input agent
);

    logic signed [DEST_ADDR_SIZE_X-1 : 0] x_distance;
    logic signed [DEST_ADDR_SIZE_Y-1 : 0] y_distance;
    assign x_distance = x_dest_i - X_CURRENT;
    assign y_distance = y_dest_i - Y_CURRENT;

    logic go_north, go_south, go_west, go_east, stay_local;

    

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
    always_comb
    begin
        eligible_port_set = '0; // Default: no eligible ports

        go_north = (y_distance > 0);
        go_south = (y_distance < 0);
        go_west = (x_distance < 0);
        go_east = (x_distance > 0);
        //stay_local = (x_distance == 0 && y_distance == 0);

        if (vc_class_i == ESCAPE) begin
            if (go_west) begin
                eligible_port_set[WEST] = 1'b1; // Only WEST is eligible
            end 
            else if (go_east) begin
                eligible_port_set[EAST] = 1'b1; // Only EAST is eligible
            end 
            else if (go_north) begin
                eligible_port_set[NORTH] = 1'b1; // Only NORTH is eligible
            end 
            else if (go_south) begin
                eligible_port_set[SOUTH] = 1'b1; // Only SOUTH is eligible
            end 
            else begin
                eligible_port_set[LOCAL] = 1'b1; // Only LOCAL is eligible
            end
        end 
        else begin
            if (go_west)  eligible_port_set[WEST]  = 1'b1;
            if (go_east)  eligible_port_set[EAST]  = 1'b1;
            if (go_north) eligible_port_set[NORTH] = 1'b1;
            if (go_south) eligible_port_set[SOUTH] = 1'b1;

            if (!(go_west || go_east || go_north || go_south))
                eligible_port_set[LOCAL] = 1'b1;
            end

    end

endmodule
