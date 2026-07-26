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
    localparam VC_COUNT = $clog2(VC_DEPTH);

    localparam FLIT_WIDTH = 64; //Renamed

    localparam PORT_NUM  = 5;
    localparam PORT_SIZE = $clog2(PORT_NUM);

    // ------------------------------------------------------------------------
    // 2. Types & Labels (Must be defined before size calculations)
    // ------------------------------------------------------------------------
    typedef enum logic [1:0] {HEAD, BODY, TAIL, HEADTAIL} flit_label_t;
    typedef enum logic [2:0] {LOCAL, NORTH, SOUTH, WEST, EAST} port_t;
    typedef enum logic [0:0] {ESCAPE, ADAPTIVE} vc_class_t;

    // ------------------------------------------------------------------------
    // 3. Payload Calculations
    // ------------------------------------------------------------------------
    // Header overhead = Label (2) + X (2) + Y (2) = 6 bits
    localparam HEADER_SIZE = DEST_ADDR_SIZE_X + DEST_ADDR_SIZE_Y + $bits(flit_label_t);

    // Head Payload = 64 - 6 - 1 = 57 bits
    localparam HEAD_PAYLOAD_SIZE = FLIT_WIDTH - HEADER_SIZE - $bits(VC_SIZE);
    
    // Body Payload = 64 - 2 - 1 = 61 bits
    localparam BODY_PAYLOAD_SIZE = FLIT_WIDTH - $bits(flit_label_t) - $bits(VC_SIZE);

    // ------------------------------------------------------------------------
    // 4. Packet Structures
    // ------------------------------------------------------------------------
    
    // The "View" inside a Head Flit (Total 61 bits)
    typedef struct packed {
        logic [DEST_ADDR_SIZE_X-1 : 0] x_dest;
        logic [DEST_ADDR_SIZE_Y-1 : 0] y_dest;
        logic [HEAD_PAYLOAD_SIZE-1: 0] head_pl;
    } head_data_t;

    // The Universal Flit Type (Total 64 bits)
    // We renamed 'flit_novc_t' to 'flit_t'
    typedef struct packed {
        flit_label_t flit_label; // [63:62]
        logic [VC_SIZE-1:0] vc_id; // [61]
        union packed {
            head_data_t                     head_data; // [60:0] if Head
            logic [BODY_PAYLOAD_SIZE-1 : 0] bt_pl;     // [60:0] if Body
        } data;
    } flit_t;

    //2-bit vector - Parallel credits
    typedef logic [VC_NUM-1:0] credits_t;

    typedef struct packed {
        flit_t flit_pb;
        credits_t credits_pb;
    } flit_pb_t;  //Piggybacked flit with credits - 66 bits                  

endpackage
