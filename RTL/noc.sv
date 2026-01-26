package noc_params;

    // ------------------------------------------------------------------------
    // 1. Constants & Geometry
    // ------------------------------------------------------------------------
    localparam MESH_SIZE_X = 4;
    localparam MESH_SIZE_Y = 4;

    // $clog2(4) = 2 bits
    localparam DEST_ADDR_SIZE_X = $clog2(MESH_SIZE_X);
    localparam DEST_ADDR_SIZE_Y = $clog2(MESH_SIZE_Y);

    localparam VC_NUM   = 2;
    localparam VC_SIZE  = $clog2(VC_NUM);
    localparam VC_DEPTH = 4;

    localparam FLIT_WIDTH = 64; //Renamed

    localparam PORT_NUM  = 5;
    localparam PORT_SIZE = $clog2(PORT_NUM);

    // ------------------------------------------------------------------------
    // 2. Types & Labels (Must be defined before size calculations)
    // ------------------------------------------------------------------------
    typedef enum logic [1:0] {HEAD, BODY, TAIL, HEADTAIL} flit_label_t;
    typedef enum logic [2:0] {LOCAL, NORTH, SOUTH, WEST, EAST} port_t;

    // ------------------------------------------------------------------------
    // 3. Payload Calculations
    // ------------------------------------------------------------------------
    // Header overhead = Label (2) + X (2) + Y (2) = 6 bits
    localparam HEADER_SIZE = DEST_ADDR_SIZE_X + DEST_ADDR_SIZE_Y + $bits(flit_label_t);

    // Head Payload = 64 - 6 = 58 bits
    localparam HEAD_PAYLOAD_SIZE = FLIT_WIDTH - HEADER_SIZE;
    
    // Body Payload = 64 - 2 = 62 bits
    localparam BODY_PAYLOAD_SIZE = FLIT_WIDTH - $bits(flit_label_t);

    // ------------------------------------------------------------------------
    // 4. Packet Structures
    // ------------------------------------------------------------------------
    
    // The "View" inside a Head Flit (Total 62 bits)
    typedef struct packed {
        logic [DEST_ADDR_SIZE_X-1 : 0] x_dest;
        logic [DEST_ADDR_SIZE_Y-1 : 0] y_dest;
        logic [HEAD_PAYLOAD_SIZE-1: 0] head_pl;
    } head_data_t;

    // The Universal Flit Type (Total 64 bits)
    // We renamed 'flit_novc_t' to 'flit_t'
    typedef struct packed {
        flit_label_t flit_label; // [63:62]
        union packed {
            head_data_t                     head_data; // [61:0] if Head
            logic [BODY_PAYLOAD_SIZE-1 : 0] bt_pl;     // [61:0] if Body
        } data;
    } flit_t;

endpackage
