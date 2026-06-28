import noc_params::*;

module mesh (
    input clk,
    input rst,
    output logic [VC_NUM-1:0] error_o [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][PORT_NUM-1:0],
    
    //connections to all local Router interfaces
    output flit_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] data_o,
    output logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] is_valid_o,
    input credits_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] credits_i,
    input [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][VC_NUM-1:0] is_allocatable_i,
    input flit_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] data_i,
    input [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] is_valid_i,
    output credits_t [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0] credits_o,
    output logic [MESH_SIZE_X-1:0][MESH_SIZE_Y-1:0][VC_NUM-1:0] is_allocatable_o
);

    genvar row, col;

    // --------------------------------------------------------
    // Flattened router2router Instance Arrays (Genus Compatible)
    // --------------------------------------------------------
    localparam H_LINKS_TOTAL = (MESH_SIZE_X + 1) * MESH_SIZE_Y;
    localparam V_LINKS_TOTAL = MESH_SIZE_X * (MESH_SIZE_Y + 1);

    router2router h_western [H_LINKS_TOTAL-1:0] ();
    router2router h_eastern [H_LINKS_TOTAL-1:0] ();
    router2router v_northern [V_LINKS_TOTAL-1:0] ();
    router2router v_southern [V_LINKS_TOTAL-1:0] ();

    generate
        for(row=0; row<MESH_SIZE_Y; row++)
        begin: mesh_row
            for(col=0; col<MESH_SIZE_X; col++)
            begin: mesh_col
                
                // 1D Index Calculation for Router (col,row)
                localparam int IDX_H_CURR = (col * MESH_SIZE_Y) + row;
                localparam int IDX_H_NEXT = ((col + 1) * MESH_SIZE_Y) + row;
                
                localparam int IDX_V_CURR = (col * (MESH_SIZE_Y + 1)) + row;
                localparam int IDX_V_NEXT = (col * (MESH_SIZE_Y + 1)) + (row + 1);

                // Local Link Instantiations
                router2router local_up_link();
                router2router local_down_link();
                router2router north_up_link();
                router2router north_down_link();
                router2router south_up_link();
                router2router south_down_link();
                router2router west_up_link();
                router2router west_down_link();
                router2router east_up_link();
                router2router east_down_link();

                // Router Instantiation
                router #(
                    .BUFFER_SIZE(VC_DEPTH),
                    .X_CURRENT(col),
                    .Y_CURRENT(row)
                )
                router_inst (
                    .clk(clk),
                    .rst(rst),       
                     
                    .router_if_local_up  (local_up_link),
                    .router_if_local_down(local_down_link),

                    .router_if_north_up  (north_up_link),
                    .router_if_north_down(north_down_link),

                    .router_if_south_up  (south_up_link),
                    .router_if_south_down(south_down_link),
                    
                    .router_if_west_up   (west_up_link),
                    .router_if_west_down (west_down_link),

                    .router_if_east_up   (east_up_link),
                    .router_if_east_down (east_down_link),
                    
                    .error_o(error_o[col][row])
                );

                // Node Link Instantiation
                node_link node_link_inst (
                    .router_if_down  (local_up_link),
                    .router_if_up    (local_down_link),
                    
                    .data_i          (data_i[col][row]),
                    .is_valid_i      (is_valid_i[col][row]),
                    .credits_o       (credits_o[col][row]),
                    .is_allocatable_o(is_allocatable_o[col][row]),
                    .data_o          (data_o[col][row]),
                    .is_valid_o      (is_valid_o[col][row]),
                    .credits_i       (credits_i[col][row]),
                    .is_allocatable_i(is_allocatable_i[col][row])
                );

                // NORTH Connections
                assign v_northern[IDX_V_NEXT].data           = north_up_link.data;
                assign v_northern[IDX_V_NEXT].is_valid       = north_up_link.is_valid;
                assign north_up_link.credits                 = v_northern[IDX_V_NEXT].credits;
                assign north_up_link.is_allocatable          = v_northern[IDX_V_NEXT].is_allocatable;

                assign north_down_link.data                  = v_southern[IDX_V_NEXT].data;
                assign north_down_link.is_valid              = v_southern[IDX_V_NEXT].is_valid;
                assign v_southern[IDX_V_NEXT].credits        = north_down_link.credits;
                assign v_southern[IDX_V_NEXT].is_allocatable = north_down_link.is_allocatable;

                // SOUTH Connections
                assign v_southern[IDX_V_CURR].data           = south_up_link.data;
                assign v_southern[IDX_V_CURR].is_valid       = south_up_link.is_valid;
                assign south_up_link.credits                 = v_southern[IDX_V_CURR].credits;
                assign south_up_link.is_allocatable          = v_southern[IDX_V_CURR].is_allocatable;

                assign south_down_link.data                  = v_northern[IDX_V_CURR].data;
                assign south_down_link.is_valid              = v_northern[IDX_V_CURR].is_valid;
                assign v_northern[IDX_V_CURR].credits        = south_down_link.credits;
                assign v_northern[IDX_V_CURR].is_allocatable = south_down_link.is_allocatable;

                // WEST Connections
                assign h_western[IDX_H_CURR].data            = west_up_link.data;
                assign h_western[IDX_H_CURR].is_valid        = west_up_link.is_valid;
                assign west_up_link.credits                  = h_western[IDX_H_CURR].credits;
                assign west_up_link.is_allocatable           = h_western[IDX_H_CURR].is_allocatable;

                assign west_down_link.data                   = h_eastern[IDX_H_CURR].data;
                assign west_down_link.is_valid               = h_eastern[IDX_H_CURR].is_valid;
                assign h_eastern[IDX_H_CURR].credits         = west_down_link.credits;
                assign h_eastern[IDX_H_CURR].is_allocatable  = west_down_link.is_allocatable;

                // EAST Connections
                assign h_eastern[IDX_H_NEXT].data            = east_up_link.data;
                assign h_eastern[IDX_H_NEXT].is_valid        = east_up_link.is_valid;
                assign east_up_link.credits                  = h_eastern[IDX_H_NEXT].credits;
                assign east_up_link.is_allocatable           = h_eastern[IDX_H_NEXT].is_allocatable;

                assign east_down_link.data                   = h_western[IDX_H_NEXT].data;
                assign east_down_link.is_valid               = h_western[IDX_H_NEXT].is_valid;
                assign h_western[IDX_H_NEXT].credits         = east_down_link.credits;
                assign h_western[IDX_H_NEXT].is_allocatable  = east_down_link.is_allocatable;


                // Boundary Tie-offs
                
                // West Boundary (Col 0)
                if (col == 0) begin : west_edge_tieoff
                    assign h_eastern[IDX_H_CURR].data           = '0;
                    assign h_eastern[IDX_H_CURR].is_valid       = 1'b0;
                    assign h_western[IDX_H_CURR].credits        = '0;
                    assign h_western[IDX_H_CURR].is_allocatable = '0;
                end

                // East Boundary (Col Max)
                if (col == MESH_SIZE_X - 1) begin : east_edge_tieoff
                    assign h_western[IDX_H_NEXT].data           = '0;
                    assign h_western[IDX_H_NEXT].is_valid       = 1'b0;
                    assign h_eastern[IDX_H_NEXT].credits        = '0;
                    assign h_eastern[IDX_H_NEXT].is_allocatable = '0;
                end

                // South Boundary (Row 0)
                if (row == 0) begin : south_edge_tieoff
                    assign v_northern[IDX_V_CURR].data           = '0;
                    assign v_northern[IDX_V_CURR].is_valid       = 1'b0;
                    assign v_southern[IDX_V_CURR].credits        = '0;
                    assign v_southern[IDX_V_CURR].is_allocatable = '0;
                end

                // North Boundary (Row Max)
                if (row == MESH_SIZE_Y - 1) begin : north_edge_tieoff
                    assign v_southern[IDX_V_NEXT].data           = '0;
                    assign v_southern[IDX_V_NEXT].is_valid       = 1'b0;
                    assign v_northern[IDX_V_NEXT].credits        = '0;
                    assign v_northern[IDX_V_NEXT].is_allocatable = '0;
                end

            end
        end
    endgenerate

endmodule
