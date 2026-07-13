module moving_square_gen #(
    parameter H_ACTIVE = 640,
    parameter V_ACTIVE = 480,

    parameter COLOURW  = 4,
    parameter SQ_SIZE  = 60,

    parameter STEP     = 4 // pixels moved per frame
)(
    input  wire                             pix_clk,
    input  wire                             rst_ni,
    input  wire                             frame_tick, //pulse once per full frame

    input  wire     [$clog2(H_ACTIVE)-1:0]  x_i, //next X pixel coords
    input  wire     [$clog2(V_ACTIVE)-1:0]  y_i, //next Y pixel coords

    output logic    [3*COLOURW-1:0]         colour_o //RRRRGGGGBBBB
);

    //max X, Y positions so it doesn't clip off screen 
    localparam SQ_X_MAX = H_ACTIVE - SQ_SIZE; 
    localparam SQ_Y_MAX = V_ACTIVE - SQ_SIZE;

    //square position
    logic [$clog2(H_ACTIVE)-1:0] sq_x;  
    logic [$clog2(V_ACTIVE)-1:0] sq_y; 

    //direction of movement
    logic dir_x, dir_y; //0 = left/up, 1 = right/down

    //change direction if we overshoot the edge
    logic next_dir_x, next_dir_y;

    //horizontal position / bounce
    always @(posedge pix_clk) begin
        if (!rst_ni) begin
            sq_x  <= 0; //reset square to left edge
            dir_x <= 1'b1; //reset direction to moving right
        end else if (frame_tick) begin
            
            next_dir_x = dir_x; //default: keep current direction

            //flip direction before we would overshoot either edge
            if (dir_x && (sq_x + STEP > SQ_X_MAX)) next_dir_x = 1'b0;
            else if (!dir_x && (sq_x < STEP))      next_dir_x = 1'b1;

            dir_x <= next_dir_x; //store direction for next frame
            sq_x  <= next_dir_x ? sq_x + STEP : sq_x - STEP; //step position using new direction
        end
    end

    //vertical position / bounce
    always @(posedge pix_clk) begin
        if (!rst_ni) begin
            sq_y  <= 0; //reset square to top edge
            dir_y <= 1'b1; //reset direction to moving down
        end else if (frame_tick) begin
            
            next_dir_y = dir_y; //default: keep current direction

            //flip direction before we would overshoot either edge
            if (dir_y && (sq_y + STEP > SQ_Y_MAX)) next_dir_y = 1'b0;
            else if (!dir_y && (sq_y < STEP))      next_dir_y = 1'b1;

            dir_y <= next_dir_y; //store direction for next frame
            sq_y  <= next_dir_y ? sq_y + STEP : sq_y - STEP; //step position using new direction
        end
    end

    //determine if the current pixel is inside the square
    wire inside_square = (x_i >= sq_x) && (x_i < sq_x + SQ_SIZE) && (y_i >= sq_y) && (y_i < sq_y + SQ_SIZE);

    //assign colour output             (square colour)      (backgound colour)
    assign colour_o = inside_square ? {4'hF, 4'h0, 4'hF} : {4'hA, 4'hD, 4'h0};

endmodule