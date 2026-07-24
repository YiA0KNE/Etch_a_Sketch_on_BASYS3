////////////////////////////////////////////////////////////////////////////////
// ui_font_pkg.sv — Minimal 5x7 bitmap font for the pixel-generated UI.
//
// Glyphs cover hexadecimal digits (0-9, A-F) and the extra characters used by
// the tool panel. Import with:  import ui_font_pkg::*;
////////////////////////////////////////////////////////////////////////////////

package ui_font_pkg;

    // Returns 1 if pixel (row,col) of glyph `ch` is lit.
    // row: 0 (top) .. 6 (bottom), col: 0 (left) .. 4 (right)
    function automatic logic font_pixel(input byte ch, input int row, input int col);
        logic [4:0] bits;   // 5-bit row bitmap for the requested character
        bits = 5'b00000;
        unique case (ch)
            "0": case (row)
                    0: bits = 5'b01110; 1: bits = 5'b10001; 2: bits = 5'b10011;
                    3: bits = 5'b10101; 4: bits = 5'b11001; 5: bits = 5'b10001;
                    6: bits = 5'b01110; default: bits = 5'b00000;
                 endcase
            "1": case (row)
                    0: bits = 5'b00100; 1: bits = 5'b01100; 2: bits = 5'b00100;
                    3: bits = 5'b00100; 4: bits = 5'b00100; 5: bits = 5'b00100;
                    6: bits = 5'b01110; default: bits = 5'b00000;
                 endcase
            "2": case (row)
                    0: bits = 5'b01110; 1: bits = 5'b10001; 2: bits = 5'b00001;
                    3: bits = 5'b00010; 4: bits = 5'b00100; 5: bits = 5'b01000;
                    6: bits = 5'b11111; default: bits = 5'b00000;
                 endcase
            "3": case (row)
                    0: bits = 5'b11111; 1: bits = 5'b00010; 2: bits = 5'b00100;
                    3: bits = 5'b00010; 4: bits = 5'b00001; 5: bits = 5'b10001;
                    6: bits = 5'b01110; default: bits = 5'b00000;
                 endcase
            "4": case (row)
                    0: bits = 5'b00010; 1: bits = 5'b00110; 2: bits = 5'b01010;
                    3: bits = 5'b10010; 4: bits = 5'b11111; 5: bits = 5'b00010;
                    6: bits = 5'b00010; default: bits = 5'b00000;
                 endcase
            "5": case (row)
                    0: bits = 5'b11111; 1: bits = 5'b10000; 2: bits = 5'b11110;
                    3: bits = 5'b00001; 4: bits = 5'b00001; 5: bits = 5'b10001;
                    6: bits = 5'b01110; default: bits = 5'b00000;
                 endcase
            "6": case (row)
                    0: bits = 5'b00110; 1: bits = 5'b01000; 2: bits = 5'b10000;
                    3: bits = 5'b11110; 4: bits = 5'b10001; 5: bits = 5'b10001;
                    6: bits = 5'b01110; default: bits = 5'b00000;
                 endcase
            "7": case (row)
                    0: bits = 5'b11111; 1: bits = 5'b00001; 2: bits = 5'b00010;
                    3: bits = 5'b00100; 4: bits = 5'b01000; 5: bits = 5'b01000;
                    6: bits = 5'b01000; default: bits = 5'b00000;
                 endcase
            "8": case (row)
                    0: bits = 5'b01110; 1: bits = 5'b10001; 2: bits = 5'b10001;
                    3: bits = 5'b01110; 4: bits = 5'b10001; 5: bits = 5'b10001;
                    6: bits = 5'b01110; default: bits = 5'b00000;
                 endcase
            "9": case (row)
                    0: bits = 5'b01110; 1: bits = 5'b10001; 2: bits = 5'b10001;
                    3: bits = 5'b01111; 4: bits = 5'b00001; 5: bits = 5'b00010;
                    6: bits = 5'b01100; default: bits = 5'b00000;
                 endcase
            "A": case (row)
                    0: bits = 5'b01110; 1: bits = 5'b10001; 2: bits = 5'b10001;
                    3: bits = 5'b11111; 4: bits = 5'b10001; 5: bits = 5'b10001;
                    6: bits = 5'b10001; default: bits = 5'b00000;
                 endcase
            "B": case (row)
                    0: bits = 5'b11110; 1: bits = 5'b10001; 2: bits = 5'b10001;
                    3: bits = 5'b11110; 4: bits = 5'b10001; 5: bits = 5'b10001;
                    6: bits = 5'b11110; default: bits = 5'b00000;
                 endcase
            "C": case (row)
                    0: bits = 5'b01110; 1: bits = 5'b10001; 2: bits = 5'b10000;
                    3: bits = 5'b10000; 4: bits = 5'b10000; 5: bits = 5'b10001;
                    6: bits = 5'b01110; default: bits = 5'b00000;
                 endcase
            "D": case (row)
                    0: bits = 5'b11110; 1: bits = 5'b10001; 2: bits = 5'b10001;
                    3: bits = 5'b10001; 4: bits = 5'b10001; 5: bits = 5'b10001;
                    6: bits = 5'b11110; default: bits = 5'b00000;
                 endcase
            "E": case (row)
                    0: bits = 5'b11111; 1: bits = 5'b10000; 2: bits = 5'b10000;
                    3: bits = 5'b11110; 4: bits = 5'b10000; 5: bits = 5'b10000;
                    6: bits = 5'b11111; default: bits = 5'b00000;
                 endcase
            "F": case (row)
                    0: bits = 5'b11111; 1: bits = 5'b10000; 2: bits = 5'b10000;
                    3: bits = 5'b11110; 4: bits = 5'b10000; 5: bits = 5'b10000;
                    6: bits = 5'b10000; default: bits = 5'b00000;
                 endcase
            "G": case (row)
                    0: bits = 5'b01111; 1: bits = 5'b10000; 2: bits = 5'b10000;
                    3: bits = 5'b10011; 4: bits = 5'b10001; 5: bits = 5'b10001;
                    6: bits = 5'b01110; default: bits = 5'b00000;
                 endcase
            "H": case (row)
                    0: bits = 5'b10001; 1: bits = 5'b10001; 2: bits = 5'b10001;
                    3: bits = 5'b11111; 4: bits = 5'b10001; 5: bits = 5'b10001;
                    6: bits = 5'b10001; default: bits = 5'b00000;
                 endcase
            "h": case (row)
                    0: bits = 5'b01000; 1: bits = 5'b01000; 2: bits = 5'b01110;
                    3: bits = 5'b01001; 4: bits = 5'b01001; 5: bits = 5'b01001;
                    6: bits = 5'b01001; default: bits = 5'b00000;
                 endcase
            "I": case (row)
                    0: bits = 5'b01110; 1: bits = 5'b00100; 2: bits = 5'b00100;
                    3: bits = 5'b00100; 4: bits = 5'b00100; 5: bits = 5'b00100;
                    6: bits = 5'b01110; default: bits = 5'b00000;
                 endcase
            "K": case (row)
                    0: bits = 5'b10001; 1: bits = 5'b10010; 2: bits = 5'b10100;
                    3: bits = 5'b11000; 4: bits = 5'b10100; 5: bits = 5'b10010;
                    6: bits = 5'b10001; default: bits = 5'b00000;
                 endcase
            "L": case (row)
                    0: bits = 5'b10000; 1: bits = 5'b10000; 2: bits = 5'b10000;
                    3: bits = 5'b10000; 4: bits = 5'b10000; 5: bits = 5'b10000;
                    6: bits = 5'b11111; default: bits = 5'b00000;
                 endcase
            "N": case (row)
                    0: bits = 5'b10001; 1: bits = 5'b11001; 2: bits = 5'b10101;
                    3: bits = 5'b10011; 4: bits = 5'b10001; 5: bits = 5'b10001;
                    6: bits = 5'b10001; default: bits = 5'b00000;
                 endcase
            "O": case (row)
                    0: bits = 5'b01110; 1: bits = 5'b10001; 2: bits = 5'b10001;
                    3: bits = 5'b10001; 4: bits = 5'b10001; 5: bits = 5'b10001;
                    6: bits = 5'b01110; default: bits = 5'b00000;
                 endcase
            "P": case (row)
                    0: bits = 5'b11110; 1: bits = 5'b10001; 2: bits = 5'b10001;
                    3: bits = 5'b11110; 4: bits = 5'b10000; 5: bits = 5'b10000;
                    6: bits = 5'b10000; default: bits = 5'b00000;
                 endcase
            "R": case (row)
                    0: bits = 5'b11110; 1: bits = 5'b10001; 2: bits = 5'b10001;
                    3: bits = 5'b11110; 4: bits = 5'b10100; 5: bits = 5'b10010;
                    6: bits = 5'b10001; default: bits = 5'b00000;
                 endcase
            "S": case (row)
                    0: bits = 5'b01110; 1: bits = 5'b10001; 2: bits = 5'b10000;
                    3: bits = 5'b01110; 4: bits = 5'b00001; 5: bits = 5'b10001;
                    6: bits = 5'b01110; default: bits = 5'b00000;
                 endcase
            "T": case (row)
                    0: bits = 5'b11111; 1: bits = 5'b00100; 2: bits = 5'b00100;
                    3: bits = 5'b00100; 4: bits = 5'b00100; 5: bits = 5'b00100;
                    6: bits = 5'b00100; default: bits = 5'b00000;
                 endcase
            "U": case (row)
                    0: bits = 5'b10001; 1: bits = 5'b10001; 2: bits = 5'b10001;
                    3: bits = 5'b10001; 4: bits = 5'b10001; 5: bits = 5'b10001;
                    6: bits = 5'b01110; default: bits = 5'b00000;
                 endcase
            ":": case (row)
                    0: bits = 5'b00000; 1: bits = 5'b01100; 2: bits = 5'b01100;
                    3: bits = 5'b00000; 4: bits = 5'b01100; 5: bits = 5'b01100;
                    6: bits = 5'b00000; default: bits = 5'b00000;
                 endcase
            "<": case (row)
                    0: bits = 5'b00010; 1: bits = 5'b00100; 2: bits = 5'b01000;
                    3: bits = 5'b10000; 4: bits = 5'b01000; 5: bits = 5'b00100;
                    6: bits = 5'b00010; default: bits = 5'b00000;
                 endcase
            ">": case (row)
                    0: bits = 5'b01000; 1: bits = 5'b00100; 2: bits = 5'b00010;
                    3: bits = 5'b00001; 4: bits = 5'b00010; 5: bits = 5'b00100;
                    6: bits = 5'b01000; default: bits = 5'b00000;
                 endcase
            "/": case (row)
                    0: bits = 5'b00001; 1: bits = 5'b00010; 2: bits = 5'b00010;
                    3: bits = 5'b00100; 4: bits = 5'b01000; 5: bits = 5'b01000;
                    6: bits = 5'b10000; default: bits = 5'b00000;
                 endcase
            default: bits = 5'b00000;
        endcase
        font_pixel = bits[4-col];
    endfunction

    // Returns 1 if pixel (x,y) is inside the scaled glyph for character ch,
    // whose top-left corner is at (gx,gy).
    function automatic logic glyph_pixel(input byte ch, input int x, input int y,
                                          input int gx, input int gy, input int scale);
        int col;    // Scaled X mapped back to the 5-column glyph grid
        int row;    // Scaled Y mapped back to the 7-row glyph grid
        glyph_pixel = 1'b0;
        if (x >= gx && x < gx + 5*scale && y >= gy && y < gy + 7*scale) begin
            col = (x - gx) / scale;
            row = (y - gy) / scale;
            glyph_pixel = font_pixel(ch, row, col);
        end
    endfunction

endpackage