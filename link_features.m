function [raw, names] = link_features(M, k, tw, frame_dur)
%LINK_FEATURES  Scalar detector features of frame k, one definition for training,
%   evaluation, the closed loop and the GUI (D42).
%   M          per-frame history of one run or episode, vector fields:
%              sinr, ber, rssi, plr, env_corr, iot (as returned by extract_closed_loop_frames)
%   k          current frame index in M
%   tw         temporal window [frames], causal, clipped to the start of M
%   frame_dur  frame duration [s]
%   raw        1 x 9: [sinr, ber, rssi, plr, var_rssi, dber_dt, burst_ratio, env_corr, iot]
%              missing values (e.g. BER of an incomplete frame) are set to 0
names = {'sinr', 'ber', 'rssi', 'plr', 'var_rssi', 'dber_dt', 'burst_ratio', 'env_corr', 'iot'};
w0 = max(1, k - tw + 1);
var_rssi = var(M.rssi(w0:k), 0);
burst    = mean(M.plr(w0:k), 'omitnan');
if k > 1 && ~isnan(M.ber(k)) && ~isnan(M.ber(k-1))
    dber = (M.ber(k) - M.ber(k-1)) / frame_dur;
else
    dber = 0;
end
raw = [M.sinr(k), M.ber(k), M.rssi(k), M.plr(k), var_rssi, dber, burst, M.env_corr(k), M.iot(k)];
raw(~isfinite(raw)) = 0;
end
