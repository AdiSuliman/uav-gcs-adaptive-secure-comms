function t = rx_taps(p)
%RX_TAPS  Taps of the real receiver for the delays the channel holds.
%   t = rx_taps(p): on the flat channel (p.tdl false) every count is 1 and the receiver is
%   the flat one; with the delay line it spans the line's delays.
%   t.lags    [before after]: symbol lags of the MRC over the antennas and the channel's
%             delays (baseline, rx_combiner 'mrc'): 2 before (a later path's receive-pulse
%             precursors, and a timing found on a later path) and the line's window
%             p.tdl_max_ns after (the measured delay range).
%   t.ne      symbol-spaced taps of the linear MMSE equalizer after that MRC, centred on
%             the symbol: the MRC output's symbol response spans +-t.lags(2).
%   t.nt      space-time taps per antenna of the MMSE combiner (rx_combiner 'mmse'), half
%             a symbol apart and centred: +-2 RMS delay spreads at the clip p.tdl_clip_ns.
%             Symbol spacing would alias the RRC's excess band, where a dispersive
%             interferer then fills every antenna dimension.
%   t.window  [symbols] MMSE window: at least twice the space-time degrees of freedom
%             (Reed, Mallett & Brennan), p.mmse_window on the flat channel.
%   t.mh      symbols on either side of a space-time snapshot's own whose pulses reach it:
%             its taps' span and two raised-cosine side lobes (0 on the flat channel).
%   t.ns      space-time taps per antenna of the synchronization statistic and of the
%             frame's sync coherence, half a symbol apart (+-1 symbol), every configuration.
%   t.nn      space-time taps per antenna over which the quiet slot gives the noise floor
%             (+-2 symbols): a jammer fills fewer than half of their dimensions.
t = struct('lags', [0 0], 'ne', 1, 'nt', 1, 'window', p.mmse_window, 'mh', 0, 'ns', 5, 'nn', 9);
if ~isfield(p, 'tdl') || ~p.tdl, return; end
T = 1e9 / p.symbol_rate;                                  % symbol period [ns]
t.lags = [2, ceil(p.tdl_max_ns / T)];
t.ne = 2 * t.lags(2) + 1;
t.nt = 2 * ceil(4 * p.tdl_clip_ns / T) + 1;
t.window = max(p.mmse_window, 2^nextpow2(2 * p.n_rx * t.nt));
t.mh = (t.nt - 1) / 4 + 2;
end
