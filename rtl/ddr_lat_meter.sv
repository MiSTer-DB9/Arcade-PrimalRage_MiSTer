module ddr_lat_meter #(parameter WIN_BITS = 25)
(
	input             clk,
	input             reset,
	input             rd_acc,
	input             dout_ready,

	output reg [63:0] win_q,
	output reg [63:0] max_q
);

// cycles from the accept cycle to the first dout_ready; the arbiter keeps one
// read outstanding at a time, so the next ready after an accept is its first word
reg        waiting;
reg [15:0] cnt;
reg [31:0] n, sum;
reg [15:0] mx, mn, mx_all;
reg [WIN_BITS-1:0] tick;

wire        done = waiting & dout_ready;
wire [31:0] n1   = n + done;
wire [31:0] sum1 = sum + (done ? {16'd0, cnt} : 32'd0);
wire [15:0] mx1  = (done && cnt > mx) ? cnt : mx;
wire [15:0] mn1  = (done && cnt < mn) ? cnt : mn;

always @(posedge clk) begin
	if (reset) begin
		waiting <= 0;
		cnt     <= 0;
		n       <= 0;
		sum     <= 0;
		mx      <= 0;
		mn      <= 16'hffff;
		mx_all  <= 0;
		tick    <= 0;
		win_q   <= 0;
		max_q   <= 0;
	end else begin
		tick <= tick + 1'd1;
		if (rd_acc) begin
			waiting <= 1;
			cnt     <= 1;
		end else if (done) begin
			waiting <= 0;
		end else if (waiting && cnt != 16'hffff) begin
			cnt <= cnt + 1'd1;
		end
		if (done) begin
			if (cnt > mx_all) mx_all <= cnt;
		end
		if (&tick) begin
			win_q <= {sum1, n1};
			max_q <= {mx_all, mx1, (mx1 == 0) ? 16'd0 : mn1, 16'h1a7c};
			n     <= 0;
			sum   <= 0;
			mx    <= 0;
			mn    <= 16'hffff;
		end else begin
			n   <= n1;
			sum <= sum1;
			mx  <= mx1;
			mn  <= mn1;
		end
	end
end

endmodule

module rle_race_meter #(parameter WIN_BITS = 25)
(
	input             clk,
	input             clk_cpu,
	input             reset,
	input             draw_busy,
	input       [2:0] control,
	input             oram_wr,
	input             vblank_rise,

	output reg [63:0] win_q,
	output reg [63:0] max_q
);

// the oram_we decode is a full clk_cpu path, half a period is too short for it:
// toggle on clk_cpu, compare on clk. One pulse per write, also back to back
reg oram_tog = 0;
always @(posedge clk_cpu) if (oram_wr) oram_tog <= ~oram_tog;

reg        oram_tog_d;
reg  [2:0] control_r;
reg        pend, wrote;
reg [15:0] w_wr, s_draws;
reg  [7:0] w_mogo, w_pend, w_frame, w_vb;
reg  [7:0] s_mogo, s_frame, s_vb;
reg [23:0] dur, mx;
reg [WIN_BITS-1:0] tick;

wire wr_busy    = draw_busy & (oram_tog ^ oram_tog_d);
wire mogo_busy  = draw_busy & control[0] & ~control_r[0];
wire frame_busy = draw_busy & (control[2] ^ control_r[2]);
wire vb_busy    = draw_busy & vblank_rise;

wire [15:0] w_wr1    = w_wr    + (wr_busy & ~&w_wr);
wire  [7:0] w_mogo1  = w_mogo  + (mogo_busy & ~&w_mogo);
wire  [7:0] w_pend1  = w_pend  + (mogo_busy & pend & ~&w_pend);
wire  [7:0] w_frame1 = w_frame + (frame_busy & ~&w_frame);
wire  [7:0] w_vb1    = w_vb    + (vb_busy & ~&w_vb);

wire [15:0] s_draws1 = s_draws + (wr_busy & ~wrote & ~&s_draws);
wire  [7:0] s_mogo1  = s_mogo  + (mogo_busy & ~&s_mogo);
wire  [7:0] s_frame1 = s_frame + (frame_busy & ~&s_frame);
wire  [7:0] s_vb1    = s_vb    + (vb_busy & ~&s_vb);

wire [23:0] dur1 = dur + (~&dur);
wire [23:0] mx1  = (draw_busy && dur1 > mx) ? dur1 : mx;

always @(posedge clk) begin
	oram_tog_d <= oram_tog;
	if (reset) begin
		control_r <= 0;
		pend      <= 0;
		wrote     <= 0;
		w_wr      <= 0;
		w_mogo    <= 0;
		w_pend    <= 0;
		w_frame   <= 0;
		w_vb      <= 0;
		s_draws   <= 0;
		s_mogo    <= 0;
		s_frame   <= 0;
		s_vb      <= 0;
		dur       <= 0;
		mx        <= 0;
		tick      <= 0;
		win_q     <= 0;
		max_q     <= 0;
	end else begin
		control_r <= control;
		tick      <= tick + 1'd1;
		pend      <= draw_busy & (pend | mogo_busy);
		wrote     <= draw_busy & (wrote | wr_busy);
		dur       <= draw_busy ? dur1 : 24'd0;
		mx        <= mx1;
		s_draws   <= s_draws1;
		s_mogo    <= s_mogo1;
		s_frame   <= s_frame1;
		s_vb      <= s_vb1;
		if (&tick) begin
			win_q   <= {w_wr1, w_mogo1, w_pend1, w_frame1, w_vb1, 16'h1a7d};
			max_q   <= {mx1, s_draws1, s_mogo1, s_frame1, s_vb1};
			w_wr    <= 0;
			w_mogo  <= 0;
			w_pend  <= 0;
			w_frame <= 0;
			w_vb    <= 0;
		end else begin
			w_wr    <= w_wr1;
			w_mogo  <= w_mogo1;
			w_pend  <= w_pend1;
			w_frame <= w_frame1;
			w_vb    <= w_vb1;
		end
	end
end

endmodule
