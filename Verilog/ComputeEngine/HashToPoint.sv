import falcon_pkg::*;

module HashToPoint (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic [63:0] message,       //r||m is input in 64-bits chunks    
    input  logic        message_valid,  //i_valid
    input  logic        message_last,        //Whether it is last chunk of messsage
    input  logic [2:0]  message_last_bytes,  //How many of last data are valid 
    input  logic        Sec_LV,         //0: Level I, 1: Level V

    input  logic        coef_ready,    //o_ready
    output logic        message_ready,  //i_ready
    output logic [WIDTH-1:0] coef,     //output coefficients
    output logic        coef_valid,     //o_valid
    output logic        done
);

    localparam [15:0] KQ     = 16'd61445;

    localparam [1:0] ST_IDLE   = 2'd0;   //IDLE State
    localparam [1:0] ST_ABSORB = 2'd1;   //SHAKE256 Absorb data
    localparam [1:0] ST_SQUEEZE = 2'd2;  //SHAKE256 output hashed value
    localparam [1:0] ST_DONE   = 2'd3;   //Module done

    logic [1:0] state;

    logic [63:0] shake_dout;
    logic        shake_dout_valid;
    logic        shake_dout_ready;
    logic        shake_start;
    logic        shake_absorb;
    logic        shake_ready;
    logic [63:0] shake_din;
    logic        shake_din_last;
    logic [2:0]  shake_din_last_bytes;

    logic [63:0] word_q;
    logic        word_valid;
    logic [1:0]  pair_pos;
    logic [10:0] idx;

    logic [15:0] sample;
    logic [15:0] sample_mod;    //sample mod Q

    logic [10:0] N;
    assign N = (Sec_LV) ? N_V : N_I;
    assign done = (state == ST_DONE);

    always @(*) begin
        case (pair_pos)
            2'd0: sample = {word_q[7:0],   word_q[15:8]};
            2'd1: sample = {word_q[23:16], word_q[31:24]};
            2'd2: sample = {word_q[39:32], word_q[47:40]};
            default: sample = {word_q[55:48], word_q[63:56]};
        endcase

        sample_mod = sample;
        if ((2*{2'b0,Q} > sample_mod) && (sample_mod >= {2'b0,Q})) sample_mod = sample_mod - {2'b0,Q};
        else if ((3*{2'b0,Q} > sample_mod) && (sample_mod >= 2*{2'b0,Q})) sample_mod = sample_mod - 2*{2'b0,Q};
        else if ((4*{2'b0,Q} > sample_mod) && (sample_mod >= 3*{2'b0,Q})) sample_mod = sample_mod - 3*{2'b0,Q};
        else if (sample_mod >= 4*{2'b0,Q}) sample_mod = sample_mod - 4*{2'b0,Q};
        //The sample_mod must be less than 5*Q
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
        end
        else if (state == ST_IDLE && start) begin
            state <= ST_ABSORB;
        end
        else if (state == ST_ABSORB && message_valid && message_last) begin
            state <= ST_SQUEEZE; 
        end
        else if (state == ST_SQUEEZE && idx >= N) begin
            state <= ST_DONE;
        end
        else if (state == ST_DONE) begin
            state <= ST_IDLE;
        end
        else begin
            state <= state;
        end
    end

    //For the Shake256
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shake_start     <= 1'b0;
            shake_absorb    <= 1'b0;
            shake_din       <= 64'd0;
            shake_din_last  <= 1'b0;
            shake_din_last_bytes <= 3'd0;
            shake_dout_ready <= 1'b0;
        end 
        else begin
            if (start) begin
                shake_start     <= 1'b1;
                shake_absorb     <= 1'b0;
                shake_din       <= 64'd0;
                shake_din_last  <= 1'b0;
                shake_din_last_bytes <= 3'd0;
            end 
            else begin
                case (state)
                    ST_ABSORB: begin
                        if (message_valid) begin
                            shake_absorb       <= 1'b1;
                            shake_din          <= message;
                            shake_din_last     <= message_last;
                            shake_din_last_bytes <= message_last_bytes;
                            shake_dout_ready <= shake_dout_valid;
                        end
                    end

                    ST_SQUEEZE: begin
                        shake_absorb       <= 1'b0;
                        shake_dout_ready <= shake_dout_valid;
                    end

                    ST_DONE: begin
                        shake_dout_ready <= 1'b1;
                    end
                    default: begin
                        shake_start     <= shake_start;
                        shake_absorb     <= shake_absorb;
                        shake_din       <= shake_din;
                        shake_din_last  <= shake_din_last;
                        shake_din_last_bytes <= shake_din_last_bytes;

                    end
                endcase
            end
        end
    end

    //For message_ready
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
             message_ready            <= 1'b1;  
        end
        else begin
            if (start) begin
                message_ready <= 1'b1;
            end
            else begin
                case (state)
                    ST_IDLE: begin
                        message_ready <= 1'b1;
                    end
                    ST_ABSORB: begin
                        message_ready <= 1'b1;
                    end
                    ST_SQUEEZE: begin
                        message_ready <= 1'b0;                        
                    end
                    ST_DONE: begin
                        message_ready <= 1'b1;
                    end
                    default: message_ready <= message_ready;
                endcase
            end
        end
    end       

    //For SHAKE256 squeeze
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            coef            <= 14'd0;
            coef_valid      <= 1'b0;
            word_q          <= 64'd0;
            word_valid      <= 1'b0;
            pair_pos        <= 2'd0;
        end else begin
            if (start) begin 
                coef            <= 14'd0;
                coef_valid      <= 1'b0;
                word_q          <= 64'd0;
                word_valid      <= 1'b0;
                pair_pos        <= 2'd0;
            end else begin
                case (state)
                    ST_SQUEEZE: begin
                        if (idx < N) begin
                            if (shake_dout_valid) begin
                                word_q     <= shake_dout;
                                word_valid <= 1'b1;
                                pair_pos   <= 2'd0;
                            end
                            if (word_valid && coef_ready) begin
                                if (sample < KQ) begin
                                    coef        <= sample_mod[13:0];
                                    coef_valid  <= 1'b1;
                                    idx         <= idx + 1'b1;
                                end

                                if (pair_pos == 2'd3) begin
                                    word_valid <= 1'b0;
                                end else begin
                                    pair_pos <= pair_pos + 1'b1;
                                end
                            end
                        end
                    end
                    default: begin
                        coef            <= coef;
                        coef_valid      <= coef_valid;
                        word_q          <= word_q;
                        word_valid      <= word_valid;
                        pair_pos        <= pair_pos;
                    end
                endcase
            end
        end
    end

    Shake256 u_shake256 (
        .clk(clk),
        .rst_n(rst_n),
        .start(shake_start),
        .ready(shake_ready),
        .absorb(shake_absorb),
        .din(shake_din),
        .din_last(shake_din_last),
        .din_last_bytes(shake_din_last_bytes),
        .dout_ready(shake_dout_ready),
        .dout_valid(shake_dout_valid),
        .dout(shake_dout)
    );

endmodule
