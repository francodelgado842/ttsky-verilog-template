`timescale 1ns/1ps
module tb;
 reg clk=0, rst_n=0, ena=1;
 reg [7:0] ui_in=0,uio_in=0;
 wire [7:0] uo_out,uio_out,uio_oe;
 tt_um_example user_project(.clk(clk),.rst_n(rst_n),.ena(ena),.ui_in(ui_in),.uo_out(uo_out),.uio_in(uio_in),.uio_out(uio_out),.uio_oe(uio_oe));
endmodule
