function T = dev_fec_table(out, thr)
%DEV_FEC_TABLE  The coded-packet table of the decisions record: packet loss of the
%   two-frame hard-decision packet and of the four-frame packet with soft values and
%   pilot-error erasures (with its variants: two frames soft, no erasures, sync or pilot
%   erasures, hard decisions) on the same received frames of dev set B
%   (dev_fec_flights.m), with the lost frames (BER > 0.2) and what the erasure flag
%   catches. thr: p.erase_pilot_mse (default init_params').
if nargin < 1, out = []; end
p0 = dev_setup('fec_ana', out, false);
if nargin < 2 || isempty(thr), thr = p0.erase_pilot_mse; end
if isempty(out), out = fullfile(tempdir, 'uav_gcs_dev'); end
B = load(fullfile(out, 'dev_B.mat')).R;
p = B.p;
pts = setdiff(fieldnames(B), {'p'});
names = {'old_2f_hard', 'new_4f_soft_pilot', 'soft_2f', 'soft_4f_noflag', 'soft_4f_syncpilot', 'hard_4f_pilot'};
nv = numel(names);
T = table();
for i = 1:numel(pts)
    S = B.(pts{i}); nfl = size(S.ber, 1); nf = size(S.ber, 2);
    L = zeros(1, nv); N = zeros(1, nv); Lu = 0; fr = zeros(1, 4);
    for r = 1:nfl
        tx = S.tx{r}; rx = S.rx{r}; iq = double(S.iq{r});
        rel = bit_reliability(double(S.z{r}), p);
        ep = S.pe(r, :) > thr; es = ep | S.sf(r, :) > 0.5; n0 = false(1, nf);
        lst = S.ber(r, :) > 0.2;
        fr = fr + [sum(lst), sum(ep & lst), sum(ep & ~lst), sum(~lst)];
        q2 = p; q2.fec_frames = 2; q4 = p; q4.fec_frames = 4;
        F = cell(1, nv);
        [~, F{1}] = dev_fec_packets_2f(tx, rx, iq, p, nf);
        [~, F{2}] = fec_packets(tx, rx, iq, q4, nf, ep, rel);
        [~, F{3}] = fec_packets(tx, rx, iq, q2, nf, n0, rel);
        [~, F{4}] = fec_packets(tx, rx, iq, q4, nf, n0, rel);
        [~, F{5}] = fec_packets(tx, rx, iq, q4, nf, es, rel);
        [~, F{6}] = fec_packets(tx, rx, iq, q4, nf, ep);
        for v = 1:nv
            k = F{v}(2:2:end); L(v) = L(v) + sum(k == 1); N(v) = N(v) + sum(~isnan(k));
        end
        Lu = Lu + sum(any(reshape(tx ~= rx, [], nf), 1));
    end
    row = table(string(pts{i}), Lu / (nfl * nf), fr(1), fr(2), fr(3), fr(4), N(2), ...
        'VariableNames', {'point', 'uncoded_fer', 'lost', 'lost_flagged', 'good_flagged', 'good', 'n_pk'});
    for v = 1:nv
        row.(names{v}) = 100 * L(v) / N(v);
    end
    T = [T; row]; %#ok<AGROW>
end
format short g
disp(T);
end
