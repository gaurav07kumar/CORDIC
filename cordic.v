//CORDIC implementation for sine and cosine for Final Project 

//Claire Barnes
`timescale 1ns/1ps
module CORDIC(clk, rst, valid_in, angle, cosine, sine, valid_out);

  parameter width = 16;
  parameter N = 32;

  // Inputs
  input clk;
  input rst;
  input valid_in;
  input signed [N-1:0] angle;

  // Outputs
  output signed  [width-1:0] sine, cosine;
  output valid_out;

  wire signed [width-1:0] x_start,y_start; 

  assign x_start = 16'h4DB0; // 0.607252935 in Q1.15 format, pre-scaled by K factor to ensure output is in range
  assign y_start = 16'h0000; // start with y=0 for sine/cosine calculation

  // Generate table of atan values
  wire signed [N-1:0] atan_table [0:width-1];

  assign atan_table[00] = 32'h20000000; // 45.000 degrees -> atan(2^0)
  assign atan_table[01] = 32'h12E4051D; // 26.565 degrees -> atan(2^-1)
  assign atan_table[02] = 32'h09FB385B; 
  assign atan_table[03] = 32'h051111D4; 
  assign atan_table[04] = 32'h028B0D43;
  assign atan_table[05] = 32'h0145D7E1;
  assign atan_table[06] = 32'h00A2F61E;
  assign atan_table[07] = 32'h00517C55;
  assign atan_table[08] = 32'h0028BE53;
  assign atan_table[09] = 32'h00145F2E;
  assign atan_table[10] = 32'h000A2F98;
  assign atan_table[11] = 32'h000517CC;
  assign atan_table[12] = 32'h00028BE6;
  assign atan_table[13] = 32'h000145F3;
  assign atan_table[14] = 32'h0000A2F9;
  assign atan_table[15] = 32'h0000517C;



  reg signed [width:0] x [0:width-1];
  reg signed [width:0] y [0:width-1];
  reg signed    [N-1:0] z [0:width-1];

  reg [width-1:0] valid_pipe;

  // make sure rotation angle is in -pi/2 to pi/2 range
  wire [1:0] quadrant;
  assign quadrant = angle[N-1:N-2];

  always @(posedge clk)
  begin // make sure the rotation angle is in the -pi/2 to pi/2 range
    if(rst)
    begin
        x[0] <= 0;
        y[0] <= 0;
        z[0] <= 0;
    end
    else
    begin
        case(quadrant)
        // 1st and 4th quadrants - no changes needed
        2'b00,
        2'b11: // no changes needed for these quadrants
        begin
            x[0] <= x_start;
            y[0] <= y_start;
            z[0] <= angle;
        end
        // 2nd quadrant - rotate by -90 degrees
        2'b01:
        begin
            x[0] <= -y_start;
            y[0] <= x_start;
            // 90 degree = {{2'b01}, {30'b0}};
            // so set angle[31:30] from 01 to 00 and keep the rest of the bits the same to effectively subtract 90 degrees from the angle
            z[0] <= {2'b00,angle[29:0]}; // subtract pi/2 for angle in this quadrant
        end
        // 3rd quadrant - rotate by +90 degrees
        2'b10:
        begin
            x[0] <= y_start;
            y[0] <= -x_start;
            // 90 degree = {{2'b01}, {30'b0}};
            // so set angle[31:30] from 10 to 11 and keep the rest of the bits the same to effectively add 90 degrees from the angle
            z[0] <= {2'b11,angle[29:0]}; // add pi/2 to angles in this quadrant
        end
        // Catch X and Z states!
        default: begin
                x[0] <= 0;
                y[0] <= 0;
                z[0] <= 0;
            end
        endcase
    end
  end


  // run through iterations
  // CORDIC PIPELINE
  genvar i;

  generate
  for (i=0; i < (width-1); i=i+1)begin: stages
    wire z_sign;
    wire signed [width:0] x_shr, y_shr;

    assign x_shr = x[i] >>> i; // signed shift right: x * 2^-i
    assign y_shr = y[i] >>> i; // signed shift right: y * 2^-i

    assign z_sign = z[i][31]; //the sign of the current rotation angle

    always @(posedge clk)
    begin
        if(rst)
        begin
            x[i+1] <= 0;
            y[i+1] <= 0;
            z[i+1] <= 0;
        end
        else
        begin
            // add/subtract shifted data based on the sign of the current angle
            // z_sign = 1(means Z is negative), so we need to rotate in the reverse direction and adding the atan value to z(overshot)
            // z_sign = 0(means Z is positive), so we need to rotate in the forward direction and subtracting the atan value from z
            // add/subtract shifted data
            x[i+1] <= z_sign ? x[i] + y_shr : x[i] - y_shr;
            y[i+1] <= z_sign ? y[i] - x_shr : y[i] + x_shr;
            z[i+1] <= z_sign ? z[i] + atan_table[i] : z[i] - atan_table[i];
        end
    end
  end
  endgenerate

  // VALID PIPELINE
    always @(posedge clk)begin
        if(rst)
            valid_pipe <= 0;
        else
            valid_pipe <= {valid_pipe[width-2:0], valid_in}; // shift in the valid signal through the pipeline 
            // valid_pipe[0] gets valid_in, 
            // valid_pipe[width-1:1] gets valid_pipe[width-2:0], effectively shifting the valid signal down the pipeline each clock cycle until it reaches the end when the output is ready
    end

    assign valid_out = valid_pipe[width-1]; // output valid signal when the data is ready at the end of the pipeline

  // assign output
  assign cosine = x[width-1];
  assign sine = y[width-1];

endmodule


