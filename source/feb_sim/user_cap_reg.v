`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    14:06:08 02/24/2011 
// Design Name: 
// Module Name:    user_cap_reg 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
//   Parallel in serial out (piso) shift register with parameterized width.
//   Capable of two functions: 1) Serial shift only (TDI in and TDO out -- no capture)
//                             2) Paralell capture of the input PI then serial shift out (LSB first)
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module user_cap_reg(TCK, DRCK_EN, FSH, FCAP, SEL, TDI, SHIFT, CAPTURE, RST, PI, TDO);

parameter width = 8;
  
    input TCK;
    input DRCK_EN;
    input FSH;
    input FCAP;
    input SEL;
    input TDI;
    input SHIFT;
    input CAPTURE;
    input RST;
    input [width-1:0] PI;
    output TDO;

  reg[width-1:0] q;
  wire ce;
  
  assign TDO     = ce & q[0];
  assign ce      = SEL & DRCK_EN & (FSH & SHIFT | (FCAP & (CAPTURE | SHIFT)));
  
  always @(posedge TCK or posedge RST) begin
  if(RST)
	   q <= {width{1'b0}};           // default
    else
	   if(ce && CAPTURE)
	     q <= PI; // Capture Status
		else if (ce && SHIFT)
	     q <= {TDI,q[width-1:1]}; // Shift right
		else
		  q <= q;                  // Hold
  end
  
endmodule
