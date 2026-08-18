import falcon_pkg::*;

module Poly_Accessor #(
     parameter [10:0] N = 512
) (
    input  logic clk,
    input  logic rst_n,
    input  logic [3:0]  state,
    //0: IDLE   1: HashToPoint   2: Decompress  3: PolyMul
    
    //htp ports
    input  logic [WIDTH-1:0] htp_coef,
    input  logic  htp_coef_valid,
    output logic  htp_coef_ready,

    //decompress ports
    input  logic [WIDTH-1:0] decompress_coef,
    input  logic  decompress_coef_valid,
    output logic  decompress_coef_ready,

    //PolyMul input ports  ........  Decompressed polynomial
    output  logic [WIDTH-1:0] pmi_coef,
    output  logic  pmi_coef_valid,
    input   logic  pmi_coef_ready,

    //PolyMul output ports
    input  logic [WIDTH-1:0] pmo_coef,
    input  logic  pmo_coef_valid,
    output logic  pmo_coef_ready,

    //PolySub input ports
    output logic [WIDTH-1:0] c_coef,
    output logic c_coef_valid,
    input  logic c_coef_ready,

    output logic [WIDTH-1:0] s_2h_coef,
    output logic s_2h_coef_valid,
    input  logic s_2h_coef_ready,

    //PolySub output ports
    input  logic [WIDTH-1:0] s1_coef,
    input  logic  s1_coef_valid,
    output logic  s1_coef_ready,

    //PolyRAM portsA
    output  logic [1:0] enA, //{cen, wen}
    output  logic [63:0] w_coefA,
    input   logic [63:0] r_coefA,
    output  logic [16:0] poly_addrA,

    //PolyRAM portsB
    output  logic [1:0] enB, //{cen, wen}
    output  logic [63:0] w_coefB,
    input   logic [63:0] r_coefB,
    output  logic [16:0] poly_addrB,

    //PolyRAM portsC
    output  logic [1:0] enC, //{cen, wen}
    output  logic [63:0] w_coefC,
    input   logic [63:0] r_coefC,
    output  logic [16:0] poly_addrC,

    output  logic        done
);

    logic [10:0] i_counter;
    //management of polynomial
    localparam [6:0] htp_addr = 0;
    localparam [6:0] decompress_addr = 1;
    localparam [6:0] s_2h_addr = 2;
    localparam [6:0] s1_addr = 3;

    assign htp_coef_ready = (state == 4'd1) && htp_coef_valid; 
    assign decompress_coef_ready = (state == 4'd2) && decompress_coef_valid; 
    assign pmi_coef_valid = (state == 4'd3) && pmi_coef_ready; 
    assign pmo_coef_ready = (state == 4'd4) && pmo_coef_valid;
    assign c_coef_valid = (state == 4'd5) && c_coef_ready; 
    assign s_2h_coef_valid = (state == 4'd5) && s_2h_coef_ready;
    assign s1_coef_ready = (state == 4'd5) && s1_coef_valid; 

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
                4'd3: begin
                    if (pmi_coef_valid && pmi_coef_ready) begin
                        i_counter <= i_counter + 10'd1;
                    end
                end
                4'd4: begin
                    if (pmo_coef_valid && pmo_coef_ready) begin
                        i_counter <= i_counter + 10'd1;
                    end
                end
                4'd5: begin
                    if (c_coef_valid && c_coef_ready && s_2h_coef_valid &&s_2h_coef_ready) begin
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
            w_coefA <= 64'b0;
            w_coefB <= 64'b0;
            w_coefC <= 64'b0;
        end
        else begin
            case (state)
                4'd1: begin
                    w_coefA <= {50'b0, htp_coef};
                    w_coefB <= 64'b0;
                    w_coefC <= 64'b0;
                end 
                4'd2: begin
                    w_coefA <= {50'b0, decompress_coef};
                    w_coefB <= 64'b0;
                    w_coefC <= 64'b0;
                end 
                4'd4: begin
                    w_coefA <= {50'b0, pmo_coef};
                    w_coefB <= 64'b0;
                    w_coefC <= 64'b0;
                end 
                4'd5: begin
                    w_coefA <= 64'b0;
                    w_coefB <= 64'b0;
                    w_coefC <= {50'b0, s1_coef};
                end 
                default: begin
                    w_coefA <= w_coefA;
                    w_coefB <= w_coefB;
                    w_coefC <= w_coefC;
                end
            endcase
        end
    end

    //For r_coef
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pmi_coef <= 14'b0;
            c_coef <= 14'b0;
            s_2h_coef <= 14'b0;
        end
        else begin
            case (state)
                4'd4: begin
                    pmi_coef <= r_coefA[13:0];
                end 
                4'd5: begin
                    c_coef <= r_coefA[13:0];
                    s_2h_coef <= r_coefB[13:0];
                end 
                default: begin
                    pmi_coef <= pmi_coef;
                    c_coef <= c_coef;
                    s_2h_coef <= s_2h_coef;
                end
            endcase
        end
    end

    //For poly_addr
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            poly_addrA <= 17'b0;
            poly_addrB <= 17'b0;
            poly_addrC <= 17'b0;
        end
        else begin
            case (state)
                4'd1: begin
                    poly_addrA <= {htp_addr, i_counter[9:0]};   //htp polynomial is stored in PolyRAM0 
                    poly_addrB <= 17'b0;
                    poly_addrC <= 17'b0;
                end 
                4'd2: begin
                    poly_addrA <= {decompress_addr, i_counter[9:0]};  //decompress polynomial is stored in PolyRAM1 
                    poly_addrB <= 17'b0;
                    poly_addrC <= 17'b0;
                end 
                4'd3: begin
                    poly_addrA <= {decompress_addr, i_counter[9:0]};  //decompress polynomial is stored in PolyRAM1 
                    poly_addrB <= 17'b0;
                    poly_addrC <= 17'b0;
                end 
                4'd4: begin
                    poly_addrA <= {s_2h_addr, i_counter[9:0]};  //s_2h polynomial is stored in PolyRAM2 
                    poly_addrB <= 17'b0;
                    poly_addrC <= 17'b0;
                end 
                4'd5: begin
                    poly_addrA <= {htp_addr, i_counter[9:0]};  //s_2h polynomial is stored in PolyRAM2 
                    poly_addrB <= {s_2h_addr, i_counter[9:0]};
                    poly_addrC <= {s1_addr, i_counter[9:0]} - 17'b1;
                end 
                default: begin
                    poly_addrA <= poly_addrA;
                    poly_addrB <= poly_addrB;
                    poly_addrC <= poly_addrC;
                end
            endcase
        end
    end

    //For wen and cen   en = {cen, wen}
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enA <= 'b0;
            enB <= 'b0;
            enC <= 'b0;
        end
        else begin
            case (state)
                4'd1: begin
                    enA <= {htp_coef_valid , 1'b1};
                    enB <= 'b0;
                    enC <= 'b0;
                end 
                4'd2: begin
                    enA <= {decompress_coef_valid , 1'b1};
                    enB <= 'b0;
                    enC <= 'b0;
                end 
                4'd3: begin     //read data
                    enA <= {pmi_coef_ready , 1'b0};
                    enB <= 'b0;
                    enC <= 'b0;
                end 
                4'd4: begin
                    enA <= {pmo_coef_valid , 1'b1};
                    enB <= 'b0;
                    enC <= 'b0;
                end 
                4'd5: begin
                    enA <= {c_coef_ready , 1'b0};
                    enB <= {s_2h_coef_ready , 1'b0};
                    enC <= {s1_coef_valid , 1'b1};
                end 
                default: begin 
                    enA <= enA;
                    enB <= enB;
                    enC <= enC;
                end
            endcase
        end
    end

    assign done = (state == 4'd1 && htp_coef_valid && htp_coef_ready && i_counter == N) || 
                  (state == 4'd2 && decompress_coef_valid && decompress_coef_ready && i_counter == N) ||
                  (state == 4'd3 && pmi_coef_valid && pmi_coef_ready && i_counter == N) ||
                  (state == 4'd4 && pmo_coef_valid && pmo_coef_ready && i_counter == N) ||
                  (state == 4'd5 && s1_coef_valid && s1_coef_ready && i_counter == N);
endmodule
