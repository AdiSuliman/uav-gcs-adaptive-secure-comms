function [rep, T3, T3s, Lm, okS] = surv3_report(X)
%SURV3_REPORT  The text of experiment_survivability_options.m under surv_v2
%   (docs/surv_p3_protocol.md section 10).
%   X: cases, VAR, EBNO, jobs, rec (each variant against its own clean link), rec_sys
%      (against the system's, VAR(2)), clean (the clean links of VAR(1:2)), clean_sh (the
%      clean links of VAR(1:2) on the shadowing flights, the shadowing combinations'
%      references; {} without them), nCombo (the
%      first nCombo cases are the combined threats), N_GEOM, RUN_FRAMES, RATIO, RELAY_DEG,
%      RELAY_LOSS_DB, floor (the reference BER floor), SH (the shadowing flights'
%      selection, surv3_shadow_flights.m; [] without them)
%   T3, T3s  cases x variants x Eb/N0: recoverable geometries [%] against the own and the
%            system's clean link
%   Lm       2 x Eb/N0: the clean link of VAR(k) is link-limited, RATIO x its packet loss +
%            1/RUN_FRAMES >= 1 (the packet bound passes 100% for every configuration, BER
%            alone decides); rows 3-4 the same on the shadowing flights (clean_sh)
%   okS      the Eb/N0 where no clean link is link-limited (the like-for-like comparison)
% Columns: VAR(1) against its own and against the system's link, then VAR(2:end) against
% their own (the relay's own is the system's).
nC = numel(X.cases); nV = numel(X.VAR); nS = numel(X.EBNO);
T3 = nan(nC, nV, nS); T3s = T3;
for i = 1:nC
    for k = 1:nV
        j = find(X.jobs(:, 1) == i & X.jobs(:, 2) == k);
        T3(i, k, :) = 100 * mean(X.rec{j}, 2);
        T3s(i, k, :) = 100 * mean(X.rec_sys{j}, 2);
    end
end
CL = [X.clean, X.clean_sh];
Lm = false(numel(CL), nS);
for k = 1:numel(CL), Lm(k, :) = X.RATIO * CL{k}.fer + 1 / X.RUN_FRAMES >= 1; end
okS = ~any(Lm, 1);
TC = cat(2, T3(:, 1, :), T3s(:, 1, :), T3(:, 2:end, :));
ref = [X.VAR.ref];
LC = Lm([ref(1), 2, ref(2:end)], :);
names = [{X.VAR(1).name, sprintf('%d ant/%d ref', X.VAR(1).n_rx, X.VAR(2).n_rx)}, {X.VAR(2:end).name}];
nK = numel(names);
ic = 1:X.nCombo; is = X.nCombo + 1:nC;
mk = {' ', 'L'};
fl = strrep(sprintf('%.0e', X.floor), 'e-0', 'e-');
rep = {sprintf('=== SURVIVABILITY OPTIONS: %s, %s, RELAY PATH ===', upper(X.VAR(1).name), upper(X.VAR(2).name)), ...
    sprintf(['Generated: %s | %d random geometries per (threat, Eb/N0), %d frames each, every configuration | ' ...
    'recoverable = BER and packet loss within %gx of the clean link | relay: signal from %g deg off the GCS ' ...
    'direction, %g dB extra path loss'], datestr(now), X.N_GEOM, X.RUN_FRAMES, X.RATIO, X.RELAY_DEG, X.RELAY_LOSS_DB), ...
    sprintf(['Protocol surv_v2 (docs/surv_p3_protocol.md section 10): ''%s'' = %s judged against the %s clean ' ...
    'link, every other column against its own (the relay against the system''s direct link) | L = link-limited: ' ...
    '%gx the reference''s packet loss + 1/%d >= 1, the packet bound passes 100%% and BER alone decides | single ' ...
    'threats at the sources'' most severe level'], names{2}, X.VAR(1).name, X.VAR(2).name, X.RATIO, X.RUN_FRAMES)};
if ~isempty(X.SH)
    rep{end+1} = sprintf(['Airframe-shadowing combinations: flights of their own (surv3_shadow_flights.m), each ' ...
        'hiding an antenna at %g dB with %s antennas from a roll-in just before the first frame (rolls %.1f-%.1f deg, ' ...
        '%.1f-%.1f km/h): %d kept of %d candidates; judged against the clean link of the same flights'], X.SH.level, ...
        strjoin(compose('%d', X.SH.n_rx), ' and '), X.SH.band, X.SH.v_kmh, sum(X.SH.kept), sum(X.SH.tried));
end
rep = [rep, {'', 'All Eb/N0:'}, share_rows(TC, X.cases, true(1, nS), names, ic, is), {''}];
if any(okS)
    rep = [rep, {sprintf('Like for like, the Eb/N0 where no clean link is link-limited (%s dB):', ...
        strjoin(compose('%g', X.EBNO(okS)), ', '))}, share_rows(TC, X.cases, okS, names, ic, is)];
else
    rep{end+1} = 'Like for like: none, every Eb/N0 is link-limited for some clean link';
end
rep{end+1} = '';
rep{end+1} = sprintf('Per Eb/N0, combined threats pooled [%%] (%s; L: its reference is link-limited):', strjoin(names, ' / '));
for s = 1:nS
    rep{end+1} = sprintf('  %2g dB  %s', X.EBNO(s), strjoin(arrayfun(@(c) sprintf('%6.1f%s', mean(TC(ic, c, s)), ...
        mk{1 + LC(c, s)}), 1:nK, 'UniformOutput', false), ' / ')); %#ok<AGROW>
end
for k = 1:numel(CL)
    b = CL{k}.ber; nm = X.VAR(1 + mod(k - 1, 2)).name;
    if k > 2, nm = [nm ', shadowing flights']; end
    rep{end+1} = sprintf('Clean BER, %s: %s', nm, strjoin(arrayfun(@(x) ber_text(x, X.floor, fl), b, ...
        'UniformOutput', false), ' ')); %#ok<AGROW>
    rep{end+1} = sprintf('Clean packet loss, %s: %s', nm, strjoin(arrayfun(@(f, l) sprintf('%.3f%s', f, ...
        mk{1 + l}), CL{k}.fer, Lm(k, :), 'UniformOutput', false), ' ')); %#ok<AGROW>
end
rep{end+1} = sprintf('(<%s: below the reference floor; the rule judges against %s)', fl, fl);
end

function L = share_rows(TC, cases, m, names, ic, is)
% Recoverable geometries per case over the Eb/N0 m, and the means of the two groups.
L = {sprintf('%-34s%s', 'recoverable geometries [%]', sprintf('%14s', names{:}))};
for i = 1:numel(cases)
    name = cases(i).threat;
    if ~isnan(cases(i).level), name = sprintf('%s (most severe, %g)', name, cases(i).level); end
    L{end+1} = sprintf('%-34s%s', name, sprintf('%13.1f%%', mean(TC(i, :, m), 3))); %#ok<AGROW>
end
L{end+1} = sprintf('%-34s%s', 'combined threats, mean', sprintf('%13.1f%%', mean(mean(TC(ic, :, m), 3), 1)));
L{end+1} = sprintf('%-34s%s', 'single threats (most severe), mean', sprintf('%13.1f%%', mean(mean(TC(is, :, m), 3), 1)));
end

function t = ber_text(b, floor_ber, fl)
% A clean BER, or "<floor" below the reference floor.
if b < floor_ber, t = ['<' fl]; else, t = sprintf('%.1e', b); end
end
