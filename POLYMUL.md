I/O Ports for PolyMul.sv
    input  logic                  clk,              //clock
    input  logic                  rst_n,            //negedge reset
    input  logic                  start,            //start to do polynomial multiplication
    input  logic                  prod_out_ready,   //play as the role of o_ready
    input  logic [N*WIDTH-1:0]    a_in,             //first polynomial input (N coefficients each WIDTH bits)
    input  logic [N*WIDTH-1:0]    b_in,             //second polynomial input (N coefficients each WIDTH bits)
    output logic                  in_ready,         //play a the role of i_ready
    output logic [N*WIDTH-1:0]    prod_out,         //polynomial output (N coefficients each WIDTH bits)
    output logic                  done              //polynomial multiplication finish

    To interact with the module:
    a_in and b_in have correct input value                                          ---> 
    start signal rises, fall when in_ready high                                     --->
    wait for the done signal rises (four clocks)                                    --->
    fetch the prod_out value and prod_out_ready rises then fall in one clock        --->
    next computation

    What the module do:
    wait for start signal rises                                                     --->
    consume a_in, b_in (in_ready high)                                              --->
    computation (need four clocks)                                                  --->
    prod_out has correct output value and done signal rises                         --->
    wait for prod_out_ready then in_ready rises for next input data


