function R = emitter_reading(va, te, classes, N, inr)
%EMITTER_READING  Antenna fault against airframe shadowing per condition: an emitter of
%   opportunity in the band during the receiver's idle time. Beside KPI 1, never in it, and
%   never the default link: the reading holds only where such an emitter is on the air.
%   R = emitter_reading(va, te, classes, N, inr)
%   va, te   validation and test splits (prepare_data.m: Y, run, pos, gain_ant, feats_raw,
%            idle_amb: emitter_idle.m), classes the class names, N the fusion's window
%            [cycles], inr the conditions' INR [dB] (p.amb_inr_db)
%   R        per condition (and the reference without an emitter): fault and shadowing
%            recall on the test frames labelled fault or shadowing [%], their 95% bootstrap
%            intervals over sub-runs and the sub-runs
%   Why it separates: a faulty connector attenuates everything its antenna receives, the
%   emitter too (build_threat_model.m); the airframe hides an antenna from the GCS's
%   direction only, so the emitter reaches the shadowed antenna like the others. Per window
%   of N cycles, the antenna weakest on our signal (its local mean, temporal_evidence.m) is
%   read on the emitter's busy idle bins: its offset from the other antennas' median there,
%   and that offset less its offset on our signal (0 for a fault, the depth for shadowing).
%   A two-class logistic regression (fuse_classes.m's fit) on the branch cues of
%   window_cues.m with and without these, fitted on the validation frames, read on the test
%   frames. The thermal floor alone carries no such cue: a matched attenuator at 290 K keeps
%   it, and against an antenna temperature below 290 K it rises by at most about 1 dB
%   (noise figure 5 dB), inside the +-2 dB calibration error.
cls = cellstr(string(classes));
iF = find(strcmp(cls, 'antenna_fault')); iS = find(strcmp(cls, 'airframe_shadowing'));
R = struct('inr', inr, 'name', {{}}, 'fault', [], 'shadow', [], 'n_fault', 0, 'n_shadow', 0);
if isempty(iF) || isempty(iS) || ~isfield(va, 'idle_amb') || ~isfield(te, 'idle_amb'), return; end
[Xv, yv] = cues(va, iF, iS, N, numel(inr)); [Xt, yt, rt] = cues(te, iF, iS, N, numel(inr));
if isempty(yv) || isempty(yt) || numel(unique(yv)) < 2, return; end
nB = numel(window_cues('names')) - 21;                 % the branch and step columns come first
nb = size(Xv, 2) - 5 * numel(inr);
sets = [{'no emitter (branch cues alone)'}, arrayfun(@(x) sprintf('emitter of opportunity at INR %g dB', x), inr, ...
    'UniformOutput', false)];
for u = 0:numel(inr)
    cols = 1:nb; if u > 0, cols = [cols, nb + 5 * (u - 1) + (1:5)]; end
    FM = fuse_classes('fit', Xv(:, cols), yv, 2, 1e-3);
    [~, k] = fuse_classes('apply', FM, Xt(:, cols));
    [mf, lf, hf] = boot(k(yt == 1) == 1, rt(yt == 1)); [ms, ls, hs] = boot(k(yt == 2) == 2, rt(yt == 2));
    R.name{end+1} = sets{u + 1};
    R.fault(end+1, :) = 100 * [mf lf hf]; R.shadow(end+1, :) = 100 * [ms ls hs];
end
R.n_fault = numel(unique(rt(yt == 1))); R.n_shadow = numel(unique(rt(yt == 2)));
R.n_branch_cols = nB;
fprintf('Antenna fault vs airframe shadowing per condition (beside KPI 1; an emitter of opportunity in the idle time):\n');
for i = 1:numel(R.name)
    fprintf('  %-44s fault %5.1f%% [%5.1f %5.1f], shadowing %5.1f%% [%5.1f %5.1f] (%d / %d sub-runs)\n', R.name{i}, ...
        R.fault(i, 1), R.fault(i, 2), R.fault(i, 3), R.shadow(i, 1), R.shadow(i, 2), R.shadow(i, 3), R.n_fault, R.n_shadow);
end
end

function [X, y, run] = cues(S, iF, iS, N, nU)
% Branch cues (window_cues.m, the first 21 columns) and per condition the emitter cues of
% every frame labelled fault or shadowing whose sub-run carries the emitter's records.
yy = double(S.Y(:)); keep = (yy == iF | yy == iS) & ~all(isnan(S.idle_amb), 2);
X = zeros(0, 21 + 5 * nU); y = zeros(0, 1); run = zeros(0, 1);
if ~any(keep), return; end
jf = cellfun(@feature_index, link_features('names'));
runs = unique(S.run(keep));
for r = runs(:)'
    ix = find(S.run == r); [~, o] = sort(S.pos(ix)); ix = ix(o);
    for j = 1:numel(ix)
        if ~keep(ix(j)), continue; end
        w = ix(max(1, j - N + 1):j);
        Gw = permute(double(S.gain_ant(w, :)), [3 2 1]); Fw = permute(double(S.feats_raw(w, jf)), [3 2 1]);
        b = window_cues(Gw, Fw, []);
        a = zeros(1, 5 * nU);
        gm = 10 * log10(mean(10 .^ (double(S.gain_ant(w, :)) / 10), 1)); nr = numel(gm);
        [~, ag] = min(gm); oth = setdiff(1:nr, ag); gofs = gm(ag) - median(gm(oth));
        for u = 1:nU
            Am = double(S.idle_amb(w, 5 * (u - 1) + (1:5)));
            nbz = Am(:, 5); nbz(isnan(nbz)) = 0;
            pa = Am(:, 1:nr);
            okk = nbz > 0 & all(~isnan(pa), 2);
            if any(okk)
                pw = 10 * log10(sum(10 .^ (pa(okk, :) / 10) .* nbz(okk), 1) / sum(nbz(okk)));
                eofs = pw(ag) - median(pw(oth));
                a(5 * (u - 1) + (1:5)) = [eofs, eofs - gofs, min(pw) - median(pw), max(pw) - min(pw), log10(1 + sum(nbz))];
            end
        end
        X(end+1, :) = [b(1:21), a]; %#ok<AGROW>
        y(end+1, 1) = 1 + (double(S.Y(ix(j))) == iS); %#ok<AGROW>
        run(end+1, 1) = r; %#ok<AGROW>
    end
end
X(~isfinite(X)) = 0;
end

function [m, lo, hi] = boot(ok, run)
% Mean of ok with a 95% bootstrap interval over sub-runs (the frames of one share its channel).
ok = double(ok(:)); m = mean(ok); lo = NaN; hi = NaN;
if isempty(ok), m = NaN; return; end
[~, ~, g] = unique(run(:)); s = accumarray(g, ok); c = accumarray(g, 1); n = numel(s);
rs = RandStream('mt19937ar', 'Seed', 7); b = zeros(1000, 1);
for i = 1:1000, k = randi(rs, n, n, 1); b(i) = sum(s(k)) / sum(c(k)); end
b = sort(b); lo = b(25); hi = b(976);
end
