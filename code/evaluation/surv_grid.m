function G = surv_grid(ber_all, fer_all, slack_all, ber_run, fer_run, maps, ACTIONS, act_set, ber_ref, fer_clean, Z)
%SURV_GRID  One survivability map under surv_v2 (map_survivability_boundary.m,
%   docs/surv_p3_protocol.md): the one-flight map's status rule on the means over the flights
%   of a cell, with its marks and a committed verdict per cell.
%   ber_all, fer_all, slack_all  {entry}(level, configuration, Eb/N0): the means over the
%            flights of BER, packet loss and slack (one loss event of a flight, packet_share.m)
%   ber_run, fer_run  {entry}(level, configuration, Eb/N0, flight): each flight's own values
%   maps     the entries (levels, threat, base, aoa); ACTIONS the configurations, act_set the
%            map's own; ber_ref, fer_clean the clean link per Eb/N0 (its BER floored)
%   Z        ok, marg: the status ratios (2, 5); sat: the saturated BER (0.45); lim: the clean
%            packet loss from which a cell is link-limited (0.5); frames: per flight; bits: per
%            frame (a packet of the coded link spans two frames); B: bootstrap resamples
%   Status (1 R, 2 M, 3 X), as the one-flight map: R when some configuration of act_set has
%   BER <= ok x ber_ref and packet loss <= ok x fer_clean + its slack; otherwise M when the
%   best BER is within marg x ber_ref, else X. G(t) has the one-flight map's fields (threat,
%   base, aoa, levels, ber_best, ratio, status, ber_attacked, best_action) and per cell:
%     link_limited  R where fer_clean >= lim: the packet-loss bound passes 1, BER alone decides
%     no_action_ok  no_action alone passes the R test (not degraded)
%     saturated     X with every configuration at BER >= sat
%     status_lo, status_hi  the status with every configuration at the low, and at the high,
%                   end of its intervals; committed when they agree
%     ber_lo, ber_hi, fer_lo, fer_hi  the intervals of the cell's configuration
%   Interval: 95% percentile bootstrap over the flights (boot_cluster.m, fixed seed), widened
%   to hold the mean; with no error (no lost packet) in any flight the upper bound is at least
%   the Clopper-Pearson bound of no event in all the flights' bits (packets).
nS = numel(ber_ref);
cols = find(ismember(ACTIONS, act_set));
ina = find(strcmp(ACTIONS, 'no_action'), 1);
coded = contains(ACTIONS, 'fec_interleave');
units = Z.frames * ones(1, numel(ACTIONS)); units(coded) = floor(Z.frames / 2);   % frames, or packets of the coded link
G = struct('threat', {}, 'base', {}, 'aoa', {}, 'levels', {}, 'ber_best', {}, 'ratio', {}, 'status', {}, ...
    'ber_attacked', {}, 'best_action', {}, 'link_limited', {}, 'no_action_ok', {}, 'saturated', {}, ...
    'status_lo', {}, 'status_hi', {}, 'committed', {}, 'ber_lo', {}, 'ber_hi', {}, 'fer_lo', {}, 'fer_hi', {});
for t = 1:numel(maps)
    B = ber_all{t}; Fe = fer_all{t}; Sl = slack_all{t}; Br = ber_run{t}; Fr = fer_run{t};
    nr = size(Br, 4);
    levels = maps(t).levels; nL = numel(levels);
    Z0 = nan(nL, nS); F0 = false(nL, nS);
    ber_best = Z0; ratio = Z0; status = zeros(nL, nS); slo = status; shi = status;
    blo = Z0; bhi = Z0; flo = Z0; fhi = Z0; lim = F0; nok = F0; sat = F0;
    best_action = cell(nL, nS);
    ber_attacked = squeeze(B(:, 1, :));
    if nL == 1, ber_attacked = ber_attacked(:)'; end
    for li = 1:nL
        for s = 1:nS
            ref = ber_ref(s); fc = fer_clean(s); sv = Sl(li, cols, s);
            [status(li, s), kc, ber_best(li, s)] = rule(B(li, cols, s), Fe(li, cols, s), sv, ref, fc, Z, cols);
            best_action{li, s} = ACTIONS{kc};
            ratio(li, s) = ber_best(li, s) / ref;
            n = numel(cols); bl = zeros(1, n); bh = bl; fl = bl; fh = bl;
            for k = 1:n
                a = cols(k);
                [bl(k), bh(k)] = ival(squeeze(Br(li, a, s, :)), B(li, a, s), nr * units(a) * Z.bits, Z.B);
                [fl(k), fh(k)] = ival(squeeze(Fr(li, a, s, :)), Fe(li, a, s), nr * units(a), Z.B);
            end
            slo(li, s) = rule(bl, fl, sv, ref, fc, Z, cols);
            shi(li, s) = rule(bh, fh, sv, ref, fc, Z, cols);
            kb = cols == kc;
            blo(li, s) = bl(kb); bhi(li, s) = bh(kb); flo(li, s) = fl(kb); fhi(li, s) = fh(kb);
            lim(li, s) = status(li, s) == 1 && fc >= Z.lim;
            nok(li, s) = B(li, ina, s) <= Z.ok * ref && Fe(li, ina, s) <= Z.ok * fc + Sl(li, ina, s);
            sat(li, s) = status(li, s) == 3 && ber_best(li, s) >= Z.sat;
        end
    end
    G(end+1) = struct('threat', maps(t).name, 'base', maps(t).base, 'aoa', maps(t).aoa, 'levels', levels, ...
        'ber_best', ber_best, 'ratio', ratio, 'status', status, 'ber_attacked', ber_attacked, ...
        'best_action', {best_action}, 'link_limited', lim, 'no_action_ok', nok, 'saturated', sat, ...
        'status_lo', slo, 'status_hi', shi, 'committed', slo == shi, 'ber_lo', blo, 'ber_hi', bhi, ...
        'fer_lo', flo, 'fer_hi', fhi); %#ok<AGROW>
end
end

function [st, kc, bb] = rule(Bv, Fv, Sv, ref, fc, Z, cols)
% The one-flight map's status rule (build_map in map_survivability_boundary.m).
okc = Bv <= Z.ok * ref & Fv <= Z.ok * fc + Sv;
if any(okc)
    c = find(okc); [bb, k] = min(Bv(c)); kc = cols(c(k)); st = 1;
else
    [bb, k] = min(Bv); kc = cols(k);
    if bb / ref <= Z.marg, st = 2; else, st = 3; end
end
end

function [lo, hi] = ival(x, m, n, B)
% 95% interval of a mean over the flights x, holding the mean m; at no event in n units the
% upper bound reaches the Clopper-Pearson bound.
x = x(:);
[~, lo, hi] = boot_cluster(x, ones(size(x)), (1:numel(x))', B, 74);
if isnan(lo), lo = m; hi = m; end
lo = min(lo, m); hi = max(hi, m);
if all(x == 0), hi = max(hi, 1 - 0.025 ^ (1 / n)); end
end
