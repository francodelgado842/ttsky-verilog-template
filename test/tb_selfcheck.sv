`timescale 1ns/1ps
// Standalone testbench: no Python or cocotb needed. Run from test/.
module tb_selfcheck;
 reg clk=0,rst_n=0,ena=1;
 reg [7:0] ui_in=0,uio_in=0;
 wire [7:0] uo_out,uio_out,uio_oe;
 always #10 clk=~clk;
 tt_um_example dut(.clk(clk),.rst_n(rst_n),.ena(ena),.ui_in(ui_in),.uo_out(uo_out),.uio_in(uio_in),.uio_out(uio_out),.uio_oe(uio_oe));
 reg [11:0] rest [0:7999];
 reg [11:0] closure [0:7999];
 integer i,segment,sample_value,center_value,magnitude,total,expected,state;
 integer active_rest,active_closure,windows;
 reg [15:0] received;
 task reset_chip;
 begin
  @(negedge clk);rst_n=0;uio_in=0;ui_in=0;
  repeat(2) @(negedge clk);
  rst_n=1;@(negedge clk);
  if(uio_oe!==8'hE0 || uio_out!==0)$fatal(1,"Reset/OE mismatch");
 end
 endtask
 task write_byte(input [7:0] data,input command);
 reg old_ack;
 begin
  @(negedge clk);ui_in=data;uio_in=command?8'd2:8'd0;old_ack=uio_out[7];
  @(negedge clk);uio_in[0]=1;
  @(negedge clk);
  if(uio_out[7]!==~old_ack)$fatal(1,"ACK mismatch");
  uio_in=0;
 end
 endtask
 task write_word(input [7:0] address,input [11:0] value);
 begin write_byte(address,1);write_byte(value[7:0],0);write_byte({4'b0,value[11:8]},0);end
 endtask
 task read_word(input [1:0] view,output [15:0] value);
 begin
  @(negedge clk);uio_in={4'b0,view,2'b0};#1;value[7:0]=uo_out;
  @(negedge clk);uio_in[4]=1;#1;value[15:8]=uo_out;
  @(negedge clk);uio_in=0;
 end
 endtask
 initial begin
  if($test$plusargs("dump"))begin $dumpfile("mav_waveforms.vcd");$dumpvars(0,tb_selfcheck);end
  $readmemh("reposo_ch0.hex",rest);$readmemh("cierre_ch0.hex",closure);
  active_rest=0;active_closure=0;windows=0;
  for(segment=0;segment<2;segment=segment+1)begin
   reset_chip();total=0;state=0;
   for(i=0;i<8000;i=i+1)begin
    sample_value=segment==0?rest[i]:closure[i];
    if(^sample_value===1'bx)$fatal(1,"Missing sample fixture");
    center_value=sample_value-1995;
    magnitude=center_value<0?-center_value:center_value;
    total=total+magnitude;
    write_word(0,sample_value[11:0]);
    if(i%64==63)begin
     expected=total/64;total=0;
     if(expected>16)state=1;else if(expected<10)state=0;
     write_byte(4,1);read_word(2,received);
     if(received!==expected[15:0])$fatal(1,"MAV mismatch sample %0d expected %0d got %0d",i,expected,received);
     read_word(0,received);if(received!==center_value[15:0])$fatal(1,"Centered mismatch");
     read_word(1,received);if(received!==magnitude[15:0])$fatal(1,"Rectifier mismatch");
     if(uio_out[5]!==state[0])$fatal(1,"Activity mismatch");
     windows=windows+1;
     if(segment==0)active_rest=active_rest+state;else active_closure=active_closure+state;
    end
   end
  end
  $display("PASS: %0d real windows, rest active=%0d/125, closure active=%0d/125",windows,active_rest,active_closure);
  $finish;
 end
 initial begin #100000000;$fatal(1,"Simulation timeout");end
endmodule
