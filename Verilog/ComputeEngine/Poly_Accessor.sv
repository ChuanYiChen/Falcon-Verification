import falcon_pkg::*;

module Poly_Accessor #(
     parameter [10:0] N = 512
) (
    input  logic clk,
    input  logic rst_n,
    input  logic [3:0]  state,
    //0: IDLE   1: HashToPoint   2: Decompress
    
    //htp ports
    input  logic [WIDTH-1:0] htp_coef,
    input  logic  htp_coef_valid,
    output logic  htp_coef_ready,

    //decompress ports
    input  logic [WIDTH-1:0] decompress_coef,
    input  logic  decompress_coef_valid,
    output logic  decompress_coef_ready,
    
    //PolyRAM ports
    output  logic [1:0] en, //{cen, wen}
    output  logic [63:0] w_coef,
    input   logic [63:0] r_coef,
    output  logic [16:0] poly_addr,

    output  logic        done
);

    logic [10:0] i_counter;
    //management of polynomial
    localparam [6:0] htp_addr = 0;
    localparam [6:0] decompress_addr = 1;

    assign htp_coef_ready = (state == 4'd1) && htp_coef_valid; 
    assign decompress_coef_ready = (state == 4'd2) && decompress_coef_valid; 

    //For i_counter
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            i_counter <= 'b0;
        end
        else if (i_counter == N) begin
            i_counter <= 'b0;
        end
        else begin
            case (state)
                4'd1: begin
                    if (htp_coef_valid && htp_coef_ready) begin
                        i_counter <= i_counter + 10'd1;
                    end
                end 
                4'd2: begin
                    if (decompress_coef_valid && decompress_coef_ready) begin
                        i_counter <= i_counter + 10'd1;
                    end
                end
                default: i_counter <= i_counter; 
            endcase
        end
    end

    //For w_coef
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_coef <= 64'b0;
        end
        else begin
            case (state)
                4'd1: begin
                    w_coef <= {50'b0, htp_coef};
                end 
                4'd2: begin
                    w_coef <= {50'b0, decompress_coef};
                end 
                default: w_coef <= w_coef;
            endcase
        end
    end

    //For poly_addr
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            poly_addr <= 17'b0;
        end
        else begin
            case (state)
                4'd1: begin
                    poly_addr <= {htp_addr, i_counter[9:0]};   //htp polynomial is stored in PolyRAM0 
                end 
                4'd2: begin
                    poly_addr <= {decompress_addr, i_counter[9:0]};  //decompress polynomial is stored in PolyRAM1 
                end 
                default: poly_addr <= poly_addr;
            endcase
        end
    end

    //For wen and cen   en = {cen, wen}
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            en <= 'b0;
        end
        else begin
            case (state)
                4'd1: begin
                    en <= {htp_coef_valid , 1'b1};
                end 
                4'd2: begin
                    en <= {decompress_coef_valid , 1'b1};
                end 
                default: en <= en;
            endcase
        end
    end

    assign done = (state == 4'd1 && htp_coef_valid && htp_coef_ready && i_counter == N) || 
                  (state == 4'd2 && decompress_coef_valid && decompress_coef_ready && i_counter == N);
endmodule
