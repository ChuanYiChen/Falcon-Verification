I/O Ports for Addq.sv:
    input  logic clk,                           //clock
    input  logic rst_n,                         //negedge reset

    input  logic i_valid,                       //input is valid
    input  logic o_ready,                       //output is successfully received
    output logic i_ready,                       //module successfully receive input 
    output logic o_valid,                       //output is valid

    input  logic [WIDTH-1:0] din1,              //input one coefficient of first polynomial, WIDTH bits
    input  logic [WIDTH-1:0] din2,              //input one coefficient of second polynomial, WIDTH bits
    output logic signed [WIDTH-1:0] dout,       //output one coefficient of result polynomial, WIDTH bits, dout = din1+(-)din2

    input  logic sub                            // 0:Add, 1:Sub

    To interact with the module:
    din1 and din2 have correct input values and sub assigned                         ---> 
    i_valid signal rises, fall when i_ready high                                     --->
    wait for the o_valid signal rises (one clocks)                                   --->
    fetch the dout value and o_ready rises then fall in one clock                    --->
    compute next coefficient

    What the module does:
    wait for i_valid signal rises                                                    --->
    consume din1, din2, sub (i_ready high)                                           --->
    modulus add/sub computation (need one clocks)                                    --->
    dout has correct output value and o_valid signal rises                           --->
    wait for o_ready then i_ready rises for next input data