function T = dev_monitor_window(out, set)
%DEV_MONITOR_WINDOW  The coded link's degradation rule and the slack of restored_plr on
%   the steady coded link of a dev set (dev_fec_flights.m, default B), decoded as the link
%   does (four frames, soft values, pilot-error erasures). Per point: the packet loss, the
%   share of cycles whose window of W frames holds at least m lost packets (CRC results
%   on the second frame of every pair, every cyclic window of every flight) for the rule
%   of 6 frames / 3 lost and the candidates, the same over the flights losing 30-60% of
%   their packets; and the flights (10 packets each) that pass restored_plr against a
%   clean reference of 0 (the jammed points, 12-15 dB) or the same flight uncoded (the
%   clean points) with a slack of one packet, two packets, or one loss event
%   (packet_share.m).
if nargin < 1, out = []; end
if nargin < 2 || isempty(set), set = 'B'; end
p0 = dev_setup('fec_ana', out, false);
if isempty(out), out = fullfile(tempdir, 'uav_gcs_dev'); end
B = load(fullfile(out, ['dev_' set '.mat'])).R;
p = B.p; p.fec_frames = 4;
pts = setdiff(fieldnames(B), {'p'});
WM = [6 3; 8 3; 10 3; 10 4; 12 3];
T = table();
for i = 1:numel(pts)
    S = B.(pts{i}); nfl = size(S.ber, 1); nf = size(S.ber, 2);
    fire = zeros(nfl, size(WM, 1)); plr = zeros(nfl, 1); pass = zeros(nfl, 3);
    for r = 1:nfl
        rel = bit_reliability(double(S.z{r}), p);
        [~, fer, crc] = fec_packets(S.tx{r}, S.rx{r}, double(S.iq{r}), p, nf, S.pe(r, :) > p0.erase_pilot_mse, rel);
        k = crc(2:2:end); plr(r) = mean(k);
        for w = 1:size(WM, 1)
            for t = 1:nf
                c = crc(mod(t - WM(w, 1):t - 1, nf) + 1);
                fire(r, w) = fire(r, w) + (sum(c == 1) >= WM(w, 2)) / nf;
            end
        end
        pr = 0;
        if startsWith(pts{i}, 'c_'), pr = mean(any(reshape(S.tx{r} ~= S.rx{r}, [], nf), 1)); end
        pl = mean(fer); np = nf / 2;
        pass(r, :) = [pl <= 2 * pr + [1 2] / np, pl <= 2 * pr + packet_share('fec_interleave', fer, 4)];
    end
    row = table(string(pts{i}), 100 * mean(plr), 'VariableNames', {'point', 'plr'});
    for w = 1:size(WM, 1)
        row.(sprintf('fire_%dof%d', WM(w, 2), WM(w, 1))) = 100 * mean(fire(:, w));
    end
    m = plr >= 0.3 & plr <= 0.6;
    row.n_30_60 = sum(m);
    row.fire30_60_3of6 = 100 * mean(fire(m, 1)); row.fire30_60_3of10 = 100 * mean(fire(m, 3));
    row.pass_1pk = sum(pass(:, 1)); row.pass_2pk = sum(pass(:, 2)); row.pass_event = sum(pass(:, 3));
    T = [T; row]; %#ok<AGROW>
end
format short g
disp(T);
end
