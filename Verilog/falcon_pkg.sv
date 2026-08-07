// falcon_pkg.sv
// Global parameter definitions for the Falcon verification architecture.

package falcon_pkg;
    // Core parameters for Falcon-512 and Falcon-1024
    localparam [13:0] Q = 12289;          // Prime modulus
    localparam [13:0] HALFQ = 6144;
    localparam int WIDTH = 14;         // Bit-width for coefficients ($2^13 < 12289 < 2^14$)
    localparam [9:0] MESSAGE_LEN = 56;   // message length(bytes)..............Can be changed 
    localparam [9:0] NONCE_LEN = 40;     // nonce length(bytes) 

    localparam [10:0] N_I = 512;            // Degree (Security Level: I)
    localparam int LOGN_I = 9;           // log2(N_I)
    localparam [10:0] SIG_LEN_I = 666;      // signature length (bytes)
    localparam [10:0] PK_LEN_I = 897;       // pk length (bytes)

    localparam [10:0] N_V = 1024;            // Degree (Security Level: V)
    localparam int LOGN_V = 10;           // log2(N_V)
    localparam [10:0] SIG_LEN_V = 1280;      // signature length (bytes)
    localparam [10:0] PK_LEN_V = 1793;       // pk length (bytes)

    
    // Valid acceptance bounds for L2 norm squared ($\lfloor\beta^2\rfloor$)
    localparam logic [31:0] BETA_SQ_I = 32'd34034726;
    localparam logic [31:0] BETA_SQ_V = 32'd70265242;
    
    typedef enum logic [2:0] {
        IDLE,
        HASH_STAGE,
        DECODE_PARSE,
        NTT_S2,
        NTT_H,
        PWM_STAGE,
        INTT_STAGE,
        NORM_CHECK
    } state_t;
endpackage
