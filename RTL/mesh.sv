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
    generate
        for(row=0; row<MESH_SIZE_Y; row++)
        begin: mesh_row
            for(col=0; col<MESH_SIZE_X; col++)
            begin: mesh_col
                //interfaces instantiation
                router2router local_up();
                router2router north_up();
                router2router south_up();
                router2router west_up();
                router2router east_up();
                router2router local_down();
                router2router north_down();
                router2router south_down();
                router2router west_down();
                router2router east_down();
                //router instantiation
                router #(
                    .BUFFER_SIZE(VC_DEPTH),
                    .X_CURRENT(col),
                    .Y_CURRENT(row)
                )
                router (
                    .clk(clk),
                    .rst(rst),
                    //upstream interfaces connections 
                    .router_if_local_up(local_up),
                    .router_if_north_up(north_up),
                    .router_if_south_up(south_up),
                    .router_if_west_up(west_up),
                    .router_if_east_up(east_up),
                    //downstream interfaces connections
                    .router_if_local_down(local_down),
                    .router_if_north_down(north_down),
                    .router_if_south_down(south_down),
                    .router_if_west_down(west_down),
                    .router_if_east_down(east_down),
                    .error_o(error_o[col][row])
                );

                // South Boundary: Row 0 has no neighbor below it (Decreasing Y)
                if (row == 0) begin : south_edge_tieoff
                    assign south_down.data = '0;
                    assign south_down.is_valid = 1'b0;
                    assign south_up.credits = '0;
                    assign south_up.is_allocatable = '0;
                end

                // North Boundary: Row Max has no neighbor above it (Increasing Y)
                if (row == MESH_SIZE_Y - 1) begin : north_edge_tieoff
                    assign north_down.data = '0;
                    assign north_down.is_valid = 1'b0;
                    assign north_up.credits = '0;
                    assign north_up.is_allocatable = '0;
                end

                // West Boundary: Col 0 has no neighbor to the left
                if (col == 0) begin : west_edge_tieoff
                    assign west_down.data = '0;
                    assign west_down.is_valid = 1'b0;
                    assign west_up.credits = '0;
                    assign west_up.is_allocatable = '0;
                end

                // East Boundary: Col Max has no neighbor to the right
                if (col == MESH_SIZE_X - 1) begin : east_edge_tieoff
                    assign east_down.data = '0;
                    assign east_down.is_valid = 1'b0;
                    assign east_up.credits = '0;
                    assign east_up.is_allocatable = '0;
                end
            end
        end

        for(row=0; row<MESH_SIZE_Y-1; row++)
        begin: vertical_links_row
            for(col=0; col<MESH_SIZE_X; col++)
            begin: vertical_links_col
                router_link link_one (
                    .router_if_up(mesh_row[row].mesh_col[col].north_up),
                    .router_if_down(mesh_row[row+1].mesh_col[col].south_down)
                );

                router_link link_two (
                    .router_if_up(mesh_row[row+1].mesh_col[col].south_up),
                    .router_if_down(mesh_row[row].mesh_col[col].north_down)
                );
                
            end
        end

        for(row=0; row<MESH_SIZE_Y; row++)
        begin: horizontal_links_row
            for(col=0; col<MESH_SIZE_X-1; col++)
            begin: horizontal_links_col
                router_link link_one (
                    .router_if_up(mesh_row[row].mesh_col[col].east_up),
                    .router_if_down(mesh_row[row].mesh_col[col+1].west_down)
                );

                router_link link_two (
                    .router_if_up(mesh_row[row].mesh_col[col+1].west_up),
                    .router_if_down(mesh_row[row].mesh_col[col].east_down)
                );

            end
        end

        for(row=0; row<MESH_SIZE_Y; row++)
        begin: node_connection_row
            for(col=0; col<MESH_SIZE_X; col++)
            begin: node_connection_col
                node_link node_link (
                    .router_if_up(mesh_row[row].mesh_col[col].local_down),
                    .router_if_down(mesh_row[row].mesh_col[col].local_up),
                    .data_i(data_i[col][row]),
                    .is_valid_i(is_valid_i[col][row]),
                    .credits_o(credits_o[col][row]),
                    .is_allocatable_o(is_allocatable_o[col][row]),
                    .data_o(data_o[col][row]),
                    .is_valid_o(is_valid_o[col][row]),
                    .credits_i(credits_i[col][row]),
                    .is_allocatable_i(is_allocatable_i[col][row])
                );
            end
        end

    endgenerate

endmodule
