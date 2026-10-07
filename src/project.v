`default_nettype none
// One-channel 12-bit MAV64. Default settings demonstrate one recorded session;
// recalibrate before using another session/sensor. All user inputs synchronous.
module tt_um_example (
    input wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input wire ena,
    input wire clk,
    input wire rst_n
);
    localparam [11:0] DEFAULT_OFFSET = 12'd1995;
    localparam [11:0] DEFAULT_LOW = 12'd10;
    localparam [11:0] DEFAULT_HIGH = 12'd16;
    reg [11:0] offset, threshold_low, threshold_high;
    reg [17:0] accumulator;
    reg [5:0] count;
    reg signed [12:0] centered;
    reg [11:0] magnitude, mav;
    reg activity, valid, error_flag, result_toggle, ack_toggle;
    reg write_prev;
    reg pending, high_byte;
    reg [1:0] address;
    reg [7:0] byte_low;
    reg [15:0] snap_centered;
    reg [11:0] snap_magnitude, snap_mav;
    reg [2:0] snap_status;
    reg [15:0] selected;
    wire write_event = uio_in[0] & ~write_prev;
    wire [11:0] value = {ui_in[3:0], byte_low};
    wire signed [12:0] difference = $signed({1'b0,value}) - $signed({1'b0,offset});
    wire [12:0] abs_wide = difference[12] ? (~difference + 13'd1) : difference;
    wire [11:0] abs_value = abs_wide[11:0];
    wire [17:0] sum_next = accumulator + {6'b0,abs_value};
    wire [11:0] mav_next = sum_next[17:6];

    always @* begin
        case(uio_in[3:2])
            2'b00: selected = snap_centered;
            2'b01: selected = {4'b0,snap_magnitude};
            2'b10: selected = {4'b0,snap_mav};
            default: selected = {13'b0,snap_status};
        endcase
    end
    assign uo_out = uio_in[4] ? selected[15:8] : selected[7:0];
    assign uio_out = {ack_toggle,result_toggle,activity,5'b0};
    assign uio_oe = 8'hE0;

    always @(posedge clk) begin
        if (!rst_n) begin
            offset <= DEFAULT_OFFSET;
            threshold_low <= DEFAULT_LOW;
            threshold_high <= DEFAULT_HIGH;
            accumulator <= 0; count <= 0;
            centered <= 0; magnitude <= 0; mav <= 0;
            activity <= 0; valid <= 0; error_flag <= 0;
            result_toggle <= 0; ack_toggle <= 0; write_prev <= 0;
            pending <= 0; high_byte <= 0; address <= 0; byte_low <= 0;
            snap_centered <= 0; snap_magnitude <= 0; snap_mav <= 0; snap_status <= 0;
        end else begin
            // Track strobe even while disabled: no delayed capture of held WRITE.
            write_prev <= uio_in[0];
            if (ena && write_event) begin
                ack_toggle <= ~ack_toggle;
                if (uio_in[1]) begin
                    pending <= 0; high_byte <= 0;
                    case(ui_in)
                        8'd0,8'd1,8'd2,8'd3: begin
                            address <= ui_in[1:0]; pending <= 1;
                        end
                        8'd4: begin
                            snap_centered <= {{3{centered[12]}},centered};
                            snap_magnitude <= magnitude;
                            snap_mav <= mav;
                            snap_status <= {error_flag,valid,activity};
                        end
                        8'd5: error_flag <= 0;
                        default: error_flag <= 1;
                    endcase
                end else if (!pending) begin
                    error_flag <= 1;
                end else if (!high_byte) begin
                    byte_low <= ui_in; high_byte <= 1;
                end else begin
                    pending <= 0; high_byte <= 0;
                    if (ui_in[7:4] != 0) begin
                        error_flag <= 1;
                    end else begin
                        case(address)
                            2'd0: begin
                                centered <= difference;
                                magnitude <= abs_value;
                                if (count == 6'd63) begin
                                    mav <= mav_next; valid <= 1;
                                    result_toggle <= ~result_toggle;
                                    accumulator <= 0; count <= 0;
                                    if (mav_next > threshold_high) activity <= 1;
                                    else if (mav_next < threshold_low) activity <= 0;
                                end else begin
                                    accumulator <= sum_next; count <= count + 6'd1;
                                end
                            end
                            2'd1: begin
                                offset <= value;
                                accumulator <= 0; count <= 0; activity <= 0; valid <= 0;
                            end
                            2'd2: begin
                                if (value < threshold_high) begin
                                    threshold_low <= value;
                                    accumulator <= 0; count <= 0; activity <= 0; valid <= 0;
                                end else error_flag <= 1;
                            end
                            2'd3: begin
                                if (value > threshold_low) begin
                                    threshold_high <= value;
                                    accumulator <= 0; count <= 0; activity <= 0; valid <= 0;
                                end else error_flag <= 1;
                            end
                        endcase
                    end
                end
            end
        end
    end
    wire _unused = &{uio_in[7:5],abs_wide[12],1'b0};
endmodule
`default_nettype wire
