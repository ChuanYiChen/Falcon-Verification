import falcon_pkg::*;

module CheckNorm (
    input  logic               clk,
    input  logic               rst_n,

    input  logic               i_valid,
    input  logic               o_ready,
    input  logic [WIDTH-1:0]   s1_din,      // Unsigned [0, 12288]
    input  logic [WIDTH-1:0]   s2_din,      // Unsigned [0, 12288]
    input  logic               Sec_LV,      //0: Level I, 1: Level V
    
    // Downstream Status Interface
    output logic               o_valid,
    output logic               i_ready,
    output logic               pass          // High if norm <= selected BETA_SQ
);
    logic i_en, o_en;
    assign i_en = i_valid && i_ready;
    assign o_en = o_valid && o_ready;
    
    logic [10:0] N; 
    logic [31:0] MAX_BOUND;
    assign N = (Sec_LV) ? N_V : N_I;
    assign MAX_BOUND = (Sec_LV) ? BETA_SQ_V : BETA_SQ_I;
    localparam [1:0] ST_IDLE               = 0;
    localparam [1:0] ST_ACCUMULATE         = 1;
    localparam [1:0] ST_VALIDATE           = 2;
    logic [1:0] state;

    // Tracking and Pipeline Counters
    logic [10:0]              counter;    // Elements consumed
    logic [40:0]              square_sum; // Large width to ensure no overflow
    // Centering Transformation Wires: Map [0, 12288] -> [-6144, 6144]
    logic signed [WIDTH:0]    s1_signed; 
    logic signed [WIDTH:0]    s2_signed;
    
    // Squaring Registers 
    logic signed [27:0]       s1_squared;
    logic signed [27:0]       s2_squared;

    assign s1_signed = (s1_din > (Q >> 1)) ? ($signed({1'b0, s1_din}) - $signed({1'b0, Q})) : $signed({1'b0, s1_din});
    assign s2_signed = (s2_din > (Q >> 1)) ? ($signed({1'b0, s2_din}) - $signed({1'b0, Q})) : $signed({1'b0, s2_din});
    
    assign s1_squared = s1_signed * s1_signed;
    assign s2_squared = s2_signed * s2_signed;

    //For FSM
    always_ff @(posedge clk or negedge rst_n ) begin 
        if (~rst_n) begin
            state <= ST_IDLE;
        end
        else if (state == ST_IDLE) begin
            state <= ST_ACCUMULATE;
        end
        else if (state == ST_ACCUMULATE && i_en && counter == N-1) begin
            state <= ST_VALIDATE;
        end
        else if (state == ST_VALIDATE && o_en) 
            state <= ST_IDLE;
        else begin
            state <= state;
        end       
    end

    //For counter
    always_ff @( posedge clk or negedge rst_n ) begin
        if (~rst_n) begin
            counter <= 'b0;
        end
        else if (state == ST_ACCUMULATE && i_en && counter < N) begin
            counter <= counter + 1;
        end
        else if (state == ST_VALIDATE && o_en) begin
            counter <= 'b0;
        end
        else begin
            counter <= counter;
        end    
    end

    //For o_valid
    assign o_valid = (state == ST_VALIDATE);

    //For i_ready
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            i_ready <= 'b1;
        end
        else if (state == ST_ACCUMULATE) begin
            if (counter == N) begin
                i_ready <= 'b0;
            end
        end
        else begin
            i_ready <= i_ready;
        end
        
    end
    
    //For square_sum
    always_ff @( posedge clk or negedge rst_n ) begin
        if (~rst_n) begin
            square_sum <= 'b0;
        end
        else if (o_en) begin
            square_sum <= 'b0;
        end
        else if (i_en) begin
            square_sum <= square_sum + {13'b0, s1_squared} + {13'b0, s2_squared};
        end
    end
    assign pass = (square_sum <= {9'b0,MAX_BOUND});
endmodule
