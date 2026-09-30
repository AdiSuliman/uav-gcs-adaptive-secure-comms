function [raw, names] = link_features(M, k, tw, ~)
%LINK_FEATURES  Scalar detector features of frame k: one definition for training,
%   evaluation, the closed loop and the GUI.
%   M    per-frame receiver measurements of one run or episode
%        (extract_closed_loop_frames.m): sinr, ber_est, snr_post, rssi, crc_fail,
%        env_corr, iot, coh, mmse_gain, align, branch_dip, branch_gap
%   k    current frame index in M
%   tw   temporal window [frames], causal, clipped to the start of M
%   raw  1 x 15 in the order of names; missing values are set to 0
%   names = link_features('names') returns the feature names only.
%
%   sinr       antenna-1 SINR [dB]            log_ber    log10 of the estimated BER
%   rssi       antenna-1 power [dB]            crc_fail   CRC check of this frame failed
%   var_rssi   RSSI variance over the window   dlog_ber   change of log_ber from the last frame
%   plr        packet loss rate over the window (CRC failures)
%   env_corr   residual vs own envelope        iot        interference over thermal [dB]
%   snr_post   post-combining SNR [dB]         coh        spatial coherence of the interference
%   mmse_gain  predicted MMSE gain [dB]        align      interference vs GCS direction
%   branch_dip deepest within-frame drop of one antenna's channel gain [dB]
%   branch_gap gap between the antennas' mean channel gains over the frame [dB]
names = {'sinr', 'log_ber', 'rssi', 'crc_fail', 'var_rssi', 'dlog_ber', 'plr', 'env_corr', 'iot', ...
         'snr_post', 'coh', 'mmse_gain', 'align', 'branch_dip', 'branch_gap'};
if ischar(M) && strcmp(M, 'names'), raw = names; return; end
w0 = max(1, k - tw + 1);
lb = @(i) log10(max(M.ber_est(i), 1e-6));
if k > 1, dlb = lb(k) - lb(k-1); else, dlb = 0; end
raw = [M.sinr(k), lb(k), M.rssi(k), M.crc_fail(k), var(M.rssi(w0:k), 0), dlb, ...
       mean(M.crc_fail(w0:k), 'omitnan'), M.env_corr(k), M.iot(k), M.snr_post(k), M.coh(k), ...
       M.mmse_gain(k), M.align(k), M.branch_dip(k), M.branch_gap(k)];
raw(~isfinite(raw)) = 0;
end
