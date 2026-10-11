// Gradient test pattern: red ramps with x, blue ramps with y, green is off.
// x and y are only meaningful inside the visible area (0..H_RES-1, 0..V_RES-1).
//   r = x * 255 / H_RES,  b = y * 255 / V_RES  (truncating division)
module pattern #(
    parameter H_RES = 640,
    parameter V_RES = 480
) (
    input  [12:0] x,
    input  [12:0] y,
    output [7:0]  r,
    output [7:0]  g,
    output [7:0]  b
);

// The fractions 255/H_RES and 255/V_RES are reduced at elaboration time, which
// gives the same truncated result. For the common resolutions the reduced
// divisor is a power of two (640: 51/128, 480: 17/32, 768: 85/256), so no
// divider is synthesized. The function only runs at elaboration, so it is
// excluded from simulation coverage.
/* verilator coverage_off */
function automatic integer gcd(input integer a, input integer b);
    integer t;
    for (integer i = 0; i < 32 && b != 0; i = i + 1) begin
        t = b;
        b = a % b;
        a = t;
    end
    gcd = a;
endfunction
/* verilator coverage_on */

localparam integer GX = gcd(255, H_RES);
localparam integer GY = gcd(255, V_RES);

assign r = 8'((32'(x) * (255 / GX)) / (H_RES / GX));
assign g = 8'h00;
assign b = 8'((32'(y) * (255 / GY)) / (V_RES / GY));

endmodule
