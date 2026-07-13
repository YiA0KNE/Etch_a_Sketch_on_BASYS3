module vga_controller #(
    // Horizontal parameters (measured in clock cycles/lines)
    parameter H_ACTIVE    =  'd640, //Hor Addr Video Time
    parameter H_FRONT     =  'd16,  //Hor Front Porch      
    parameter H_PULSE     =  'd96,  //Hor Sync Time          
    parameter H_BACK      =  'd48,  //Hor Back Porch      

    // Vertical parameters (measured in clock cycles/lines)
    parameter V_ACTIVE    =  'd480, //V Addr Video Time    
    parameter V_FRONT     =  'd10,   //V Front Porch        
    parameter V_PULSE     =  'd2,   //V Sync Time        
    parameter V_BACK      =  'd33,  //V Back Porch      

    parameter COLOURW     =  'd4        
)(
    input   logic                               pix_clk, // 25 MHz is ok for 640x480, 60Hz
    input   logic                               rst_ni, // Active low
    input   logic    [3*COLOURW - 1:0]          colour_i, // Pixel color data (RRRRGGGGBBBB)

    output logic                                hsynct_o, // HSYNC (to VGA connector)
    output logic                                vsynct_o, // VSYNC (to VGA connctor)
    
    output logic    [COLOURW-1:0]               red_o, // RED (to VGA connector)
    output logic    [COLOURW-1:0]               green_o, // GREEN (to VGA connector)
    output logic    [COLOURW-1:0]               blue_o, // BLUE (to VGA connector)

    output logic    [$clog2(H_ACTIVE + H_FRONT + H_PULSE + H_BACK)-1:0] next_x_o, // Next pixel X coordinate
    output logic    [$clog2(V_ACTIVE + V_FRONT + V_PULSE + V_BACK)-1:0] next_y_o  // Next pixel Y coordinate 
    
);

    // total width of the horizontal and vertical counters
    localparam H_WIDTH_TOTAL = H_ACTIVE + H_FRONT + H_PULSE + H_BACK;
    localparam V_WIDTH_TOTAL = V_ACTIVE + V_FRONT + V_PULSE + V_BACK;

    //values for easy logic
    localparam   LOW     = 1'b0;
    localparam   HIGH    = 1'b1;

    //ceiling for total width
    localparam H_CNT_WIDTH = $clog2(H_WIDTH_TOTAL);
    localparam V_CNT_WIDTH = $clog2(V_WIDTH_TOTAL);

    //sizing the counters
    reg [H_CNT_WIDTH-1:0] h_counter;
    reg [V_CNT_WIDTH-1:0] v_counter;

    //horizontal counter
    always@(posedge pix_clk) begin
        if (!rst_ni) begin
            h_counter   <= 'd0;
        end else begin
            h_counter   <= ((h_counter == H_WIDTH_TOTAL-1) ? 'd0 : (h_counter + 'd1));
        end
    end

    //vertical counter
    always@(posedge pix_clk) begin
        if (!rst_ni) begin
            v_counter   <= 'd0;
        end else begin
            v_counter   <= (h_counter == H_WIDTH_TOTAL-1) ? ((v_counter == V_WIDTH_TOTAL-1) ? 'd0 : (v_counter + 'd1)) : v_counter;
        end
    end

    //in sync or active zone?
    wire h_sync_area = (h_counter >= (H_ACTIVE + H_FRONT)) && (h_counter <  (H_ACTIVE + H_FRONT + H_PULSE));
    wire v_sync_area = (v_counter >= (V_ACTIVE + V_FRONT)) && (v_counter <  (V_ACTIVE + V_FRONT + V_PULSE));
    wire active_area = (h_counter < H_ACTIVE) && (v_counter < V_ACTIVE);

    //assign output values - to VGA connector
    assign hsynct_o = (!rst_ni) ? HIGH : (h_sync_area ? LOW : HIGH);
    assign vsynct_o = (!rst_ni) ? HIGH : (v_sync_area ? LOW : HIGH);

    //assign colour values - to VGA connector
    assign red_o   = (!rst_ni || !active_area) ? {COLOURW{1'b0}} : colour_i[3*COLOURW-1 -: COLOURW];
    assign green_o = (!rst_ni || !active_area) ? {COLOURW{1'b0}} : colour_i[2*COLOURW-1 -: COLOURW];
    assign blue_o  = (!rst_ni || !active_area) ? {COLOURW{1'b0}} : colour_i[COLOURW-1:0];

    //next values
    assign next_x_o = h_counter;
    assign next_y_o = v_counter;

endmodule