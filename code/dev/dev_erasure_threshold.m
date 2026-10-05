function thr = dev_erasure_threshold(out)
%DEV_ERASURE_THRESHOLD  p.erase_pilot_mse: the smallest threshold on a 0.05 grid that
%   flags at most 1% of the frames with BER <= 0.2 of dev set A (dev_fec_flights.m);
%   prints what it and the sync flag catch of the lost frames (BER > 0.2).
if nargin < 1, out = []; end
dev_setup('fec_ana', out, false);
if isempty(out), out = fullfile(tempdir, 'uav_gcs_dev'); end
A = load(fullfile(out, 'dev_A.mat')).R;
pts = setdiff(fieldnames(A), {'p'});
pe = []; ber = []; sf = [];
for i = 1:numel(pts)
    S = A.(pts{i}); pe = [pe; S.pe(:)]; ber = [ber; S.ber(:)]; sf = [sf; S.sf(:)]; %#ok<AGROW>
end
good = ber <= 0.2; lost = ber > 0.2;
grid = 0.05:0.05:3;
thr = grid(find(arrayfun(@(t) mean(pe(good) > t), grid) <= 0.01, 1));
fprintf('dev A: %d frames, %d with BER <= 0.2, %d lost\n', numel(ber), sum(good), sum(lost));
fprintf('erase_pilot_mse %.2f: flags %.2f%% of the good frames (%d), %d of %d lost\n', thr, 100*mean(pe(good) > thr), ...
    sum(pe(good) > thr), sum(pe(lost) > thr), sum(lost));
fprintf('sync flag: %.2f%% of the good frames (%d), %d of %d lost\n', 100*mean(sf(good) > 0.5), sum(sf(good) > 0.5), ...
    sum(sf(lost) > 0.5), sum(lost));
for i = 1:numel(pts)
    S = A.(pts{i}); g = S.ber(:) <= 0.2;
    fprintf('  %-16s good frames flagged: pilot error %d/%d, sync %d/%d\n', pts{i}, sum(S.pe(g) > thr), sum(g), ...
        sum(S.sf(g) > 0.5), sum(g));
end
end
