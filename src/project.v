/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_guidoism (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // All output pins must be assigned. If not used, assign to 0.
  assign uo_out  = ui_in + uio_in;  // Example: ou_out is the sum of ui_in and uio_in
  assign uio_out = 0;
  assign uio_oe  = 0;

  //module opccpu(inout[7:0] data, output[10:0] address, output rnw, input clk, input reset_b);

   // We have: 8 input
   //          8 output
   //          8 both
   //         24 total
   //
   // We need: 8 both (data)
   //         11 output (address)
   //          1 output (rnw)
   //         20 total
   // 
   // We have enough pins but not enough outputs so we will
   // reduce the number of address pins.
   wire [7:0]         data;
   wire [10:0]        address;
   wire               rnw;
   assign uio_out = rnw ? 0 : data;
   assign uio_in = rnw ? data : 0;
   //assign data = rnw ? uo_out : ui_in;
   //assign uio_oe = rnw;
   //assign uio_out = 0;  // temporarily set to 0 while I figure stuff out
   //assign address[7:0] = uo_out[7:0];
   //assign address[10:8] = 0;
   //assign uo_out = 0;  // temporarily set to 0 while I figure stuff out
   //assign data = 0;
   //assign address = 0;  // temporarily set to 0 while I figure stuff out
   ////////////////////////////////////////////////////////////////
   
   parameter FETCH0=0, FETCH1=1, RDMEM=2, RDMEM2=3, EXEC=4 ;
   parameter AND=5'bx0000,  LDA=5'bx0001, NOT=5'bx0010, ADD=5'bx0011;
   parameter LDAP=5'b01001, STA=5'b11000, STAP=5'b01000;
   parameter JPC=5'b11001,  JPZ=5'b11010, JP=5'b11011,  JSR=5'b11100;
   parameter RTS=5'b11101,  LXA=5'b11110;
   reg [10:0] OR_q, PC_q;
   reg [7:0]  ACC_q;
   reg [2:0]  FSM_q;
   reg [4:0]  IR_q;
   reg [2:0]  LINK_q; // bottom bit doubles up as carry flag
`define CARRY LINK_q[0]
   wire       writeback_w = ((FSM_q == EXEC) && (IR_q == STA || IR_q == STAP)) & rst_n ;
   assign rnw = ~writeback_w ;
   assign data = (writeback_w)?ACC_q:8'bz ;
   assign address = ( writeback_w || FSM_q == RDMEM || FSM_q==RDMEM2)? OR_q:PC_q;

   always @ (posedge clk or negedge rst_n )
     if (!rst_n)
       FSM_q <= FETCH0;
     else
       case(FSM_q)
         FETCH0 : FSM_q <= FETCH1;
         FETCH1 : FSM_q <= (IR_q[4])?EXEC:RDMEM ;
         RDMEM  : FSM_q <= (IR_q==LDAP)?RDMEM2:EXEC;
         RDMEM2 : FSM_q <= EXEC;
         EXEC   : FSM_q <= FETCH0;
       endcase

   always @ (posedge clk)
     begin
        IR_q <= (FSM_q == FETCH0)? data[7:3] : IR_q;
        // OR_q[10:8] is upper part nybble for address - needs to be zeroed for both pointer READ and WRITE operations once ptr val is read
        OR_q[10:8] <= (FSM_q == FETCH0)? data[2:0]: (FSM_q==RDMEM)?3'b0:OR_q[10:8];
        OR_q[7:0] <= data; //Lowest byte of OR is dont care in FETCH0 and at end of EXEC
        if ( FSM_q == EXEC )
          casex (IR_q)
            JSR    : {LINK_q,ACC_q} <= PC_q ;
            LXA    : {LINK_q,ACC_q} <= {ACC_q[2:0], 5'b0, LINK_q};
            AND    : {`CARRY, ACC_q}  <= {1'b0, ACC_q & OR_q[7:0]};
            NOT    : ACC_q <= ~OR_q[7:0];
            LDA    : ACC_q <= OR_q[7:0];
            LDAP   : ACC_q <= OR_q[7:0];
            ADD    : {`CARRY,ACC_q} <= ACC_q + `CARRY + OR_q[7:0];
            default: {`CARRY,ACC_q} <= {`CARRY,ACC_q};
          endcase
     end

   always @ (posedge clk or negedge rst_n )
     if (!rst_n) // On reset start execution at 0x100 to leave page zero clear for variables
       PC_q <= 11'h100;
     else
       if ( FSM_q == FETCH0 || FSM_q == FETCH1 )
         PC_q <= PC_q + 1;
       else
         case (IR_q)
           JP    : PC_q <= OR_q;
           JPC   : PC_q <= (`CARRY)?OR_q:PC_q;
           JPZ   : PC_q <= ~(|ACC_q)?OR_q:PC_q;
           JSR   : PC_q <= OR_q;
           RTS   : PC_q <= {LINK_q, ACC_q};
           default: PC_q <= PC_q;
         endcase
endmodule
