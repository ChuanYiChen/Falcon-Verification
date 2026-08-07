import falcon_pkg::*;

module NTT #(parameter int N = 512)(
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  start,
    input  logic                  inverse,      // 0 = NTT, 1 = INTT
    input  logic [N*WIDTH-1:0]    poly_in,
    output logic [N*WIDTH-1:0]    poly_out,
    output logic                  done
);

    localparam int ROOT = 5;          // primitive root for q=12289
    localparam int LOGN = $clog2(N);

    logic [31:0] a [0:N-1];

    function automatic integer mod_add(input integer x, input integer b);
        integer r;
        r = x + b;
        if (r >= {18'b0,Q}) r = r - {18'b0,Q};
        return r;
    endfunction

    function automatic integer mod_sub(input integer x, input integer b);
        integer r;
        r = x - b;
        if (r < 0) r = r + {18'b0,Q};
        return r;
    endfunction

    function automatic integer mod_mul(input integer x, input integer b);
        return (x * b) % {18'b0,Q};
    endfunction

    function automatic integer pow_mod(input integer base, input integer exp);
        integer r;
        r = 1;
        for (int e = 0; e < exp; e++) begin
            r = mod_mul(r, base);
        end
        return r;
    endfunction

    function automatic integer bit_reverse(input integer x, input integer bits);
        integer y;
        y = 0;
        for (int i = 0; i < bits; i++) begin
            y = (y << 1) | ((x >> i) & 1);
        end
        return y;
    endfunction

    task automatic run_transform;
        integer i, j, len, half;
        integer w, wlen, u, v;
        integer inv_n;
    begin
        // Load input coefficients
        for (i = 0; i < N; i++) begin
            a[i] <= {18'b0, poly_in[i*WIDTH +: WIDTH]};
        end

        // Bit-reversal permutation
        for (i = 0; i < N; i++) begin
            j = bit_reverse(i, LOGN);
            if (i < j) begin
                integer tmp;
                a[i] <= a[j];
                a[j] <= a[i];
            end
        end

        // Butterfly stages
        len = 2;
        while (len <= N) begin
            half = len / 2;

            if (inverse) begin
                wlen = pow_mod(ROOT, {18'b0,Q} - 1 - (({18'b0,Q} - 1) / len));
            end else begin
                wlen = pow_mod(ROOT, ({18'b0,Q} - 1) / len);
            end

            for (i = 0; i < N; i = i + len) begin
                w = 1;
                for (j = 0; j < half; j++) begin
                    u = a[i + j];
                    v = mod_mul(a[i + j + half], w);

                    a[i + j] <= mod_add(u, v);
                    a[i + j + half] <= mod_sub(u, v);

                    w = mod_mul(w, wlen);
                end
            end

            len = len << 1;
        end

        // INTT scaling by N^{-1} mod Q
        if (inverse) begin
            inv_n = pow_mod(N, {18'b0,Q} - 2);
            for (i = 0; i < N; i++) begin
                a[i] <= mod_mul(a[i], inv_n);
            end
        end

        // Pack result back to output
        for (i = 0; i < N; i++) begin
            integer reduced;
            reduced = a[i] % {18'b0,Q};
            poly_out[i*WIDTH +: WIDTH] <= reduced[WIDTH-1:0];
        end
    end
    endtask

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done <= 1'b0;
            poly_out <= '0;
        end else if (start) begin
            done <= 1'b0;
            run_transform();
            done <= 1'b1;
        end
    end

endmodule
