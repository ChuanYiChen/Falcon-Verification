I/O Potrs for CheckNorm.sv:
    input  logic               clk,         //clock
    input  logic               rst_n,       //negedge reset

    input  logic               i_valid,     //input is valid
    input  logic               o_ready,     //output is successfully received
    input  logic [WIDTH-1:0]   s1_din,      //coefficient of s1, unsigned WIDTH bits with value in [0, 12288]
    input  logic [WIDTH-1:0]   s2_din,      //coefficient of s2, unsigned WIDTH bits with value in [0, 12288]
    input  logic               Sec_LV,      //0: Level I, 1: Level V
    
    // Downstream Status Interface 
    output logic               o_valid,      //output is valid
    output logic               i_ready,      //module successfully receive input 
    output logic               pass          // High if the verification pass

    To interact with the module:
    s1_din, s2_din have correct input values, Sev_LV set                                  ---> 
    i_valid signal rises, fall when i_ready high                                          --->
    repeat input new s1_din, s2_din and i_valid signal rises until all coefficients input --->
    wait for the o_valid signal rises (one clocks)                                        --->
    fetch the pass value and o_ready rises then fall in one clock

    What the module does:
    wait for i_valid signal rises                                                                                    --->
    consume s1_din, s2_din, compute accumulated l2-norm, i_ready rises to acccumulate next coefficeint               --->
    check whether the l2-norm is small enough to assign pass value                                                   --->
    pass has correct output value and o_valid signal rises
