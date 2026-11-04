function report = surv_report(G, ber_ref, fer_clean, SNR_points, title_str, act_set, ACT_CODE, Z)
%SURV_REPORT  The text of one survivability map under surv_v2 (map_survivability_boundary.m):
%   G from surv_grid.m, the clean link's reference BER (floored) and packet loss per Eb/N0,
%   the map's title and configurations, ACT_CODE the configurations' letters, Z as surv_grid.m
%   with NR (flights per cell) and floor (the reference floor). Cells by surv_cell_label.m.
nS = numel(SNR_points);
res_u = 1 / (Z.NR * Z.frames * Z.bits); res_c = 1 / (Z.NR * floor(Z.frames / 2) * Z.bits);
report = {};
report{end+1} = sprintf('=== SURVIVABILITY BOUNDARY MAP — %s ===', title_str);
report{end+1} = sprintf('Generated: %s', datestr(now));
report{end+1} = sprintf('Configurations included: %d (policy_actions.m, apply_countermeasure.m)', numel(act_set));
report{end+1} = sprintf(['Protocol surv_v2 (docs/surv_p3_protocol.md): %d flights of %d frames per cell, the same flights ' ...
    'at every level and Eb/N0 of an entry'], Z.NR, Z.frames);
report{end+1} = '';
report{end+1} = ['A state is classified by the best configuration relative to the clean link at the same Eb/N0 ' ...
    '(means over the flights):'];
report{end+1} = sprintf(['  RECOVERABLE (R) : BER and packet loss within %gx | MARGINAL (M) : BER within %gx | ' ...
    'NON-RECOVERABLE (X) : worse'], Z.ok, Z.marg);
report{end+1} = sprintf(['  LINK-LIMITED (L): recoverable where the clean link itself loses %g or more of its packets: ' ...
    'the packet-loss bound passes 1, so BER alone decides'], Z.lim);
report{end+1} = ['Letters after the status = configuration achieving it: C channel_switch, F freq_diversity, ' ...
    'S spatial_diversity, R rate_reduce, P power_control, E fec_interleave.'];
report{end+1} = sprintf(['  N: no_action already passes (not degraded) | none: every configuration at BER >= %g ' ...
    '(saturated) | ?: not committed (the status at the low and at the high end of the 95%% intervals over ' ...
    'the flights differ)'], Z.sat);
report{end+1} = '';
report{end+1} = sprintf(['Clean-link reference BER and packet loss per Eb/N0 (measured; floor %g = the decision ' ...
    'layer''s reference floor; cell resolution %.1e uncoded / %.1e coded):'], Z.floor, res_u, res_c);
for s = 1:nS
    m = ''; if fer_clean(s) >= Z.lim, m = '  (link-limited)'; end
    report{end+1} = sprintf('  %2g dB : %.4e, packet loss %.3f%s', SNR_points(s), ber_ref(s), fer_clean(s), m); %#ok<AGROW>
end
report{end+1} = '';
report{end+1} = '--- Boundary map, per threat (rows = severity level, cols = Eb/N0) ---';
for t = 1:numel(G)
    g = G(t);
    report{end+1} = sprintf('%s:', g.threat); %#ok<AGROW>
    hdr = sprintf('  %-10s', 'level\SNR');
    for s = 1:nS, hdr = [hdr sprintf('%8s', sprintf('%gdB', SNR_points(s)))]; end %#ok<AGROW>
    report{end+1} = hdr; %#ok<AGROW>
    for li = 1:numel(g.levels)
        line = sprintf('  %-10g', g.levels(li));
        for s = 1:nS
            code = '';
            if g.status(li, s) > 0, code = ACT_CODE(g.best_action{li, s}); end
            c = surv_cell_label(g.status(li, s), code, g.no_action_ok(li, s), g.link_limited(li, s), ...
                g.saturated(li, s), g.committed(li, s));
            line = [line sprintf('%8s', c)]; %#ok<AGROW>
        end
        report{end+1} = line; %#ok<AGROW>
    end
    k = counts(g);
    report{end+1} = sprintf(['  -> recoverable %d/%d (%.0f%%) | link-limited %d | marginal %d | non-recoverable %d | ' ...
        'not degraded (N) %d | committed %d/%d'], k.r, k.n, 100 * k.r / max(k.n, 1), k.l, k.m, k.x, k.nok, k.com, k.n); %#ok<AGROW>
    report{end+1} = ''; %#ok<AGROW>
end
k = counts(G);
report{end+1} = '=== OVERALL ===';
report{end+1} = sprintf('Total states mapped: %d', k.n);
report{end+1} = sprintf('  Recoverable     : %d (%.1f%%)', k.r, 100 * k.r / max(k.n, 1));
report{end+1} = sprintf('  Link-limited    : %d (%.1f%%)', k.l, 100 * k.l / max(k.n, 1));
report{end+1} = sprintf('  Marginal        : %d (%.1f%%)', k.m, 100 * k.m / max(k.n, 1));
report{end+1} = sprintf('  Non-recoverable : %d (%.1f%%)', k.x, 100 * k.x / max(k.n, 1));
report{end+1} = sprintf('  Recoverable or link-limited (the status rule''s R): %d (%.1f%%)', k.r + k.l, 100 * (k.r + k.l) / max(k.n, 1));
report{end+1} = sprintf('  Not degraded (N): %d | committed: %d of %d', k.nok, k.com, k.n);
end

function k = counts(G)
% Cell counts over the entries G: R without L, L, M, X, N, committed, mapped.
st = []; lm = []; nk = []; cm = [];
for t = 1:numel(G)
    st = [st; G(t).status(:)]; lm = [lm; G(t).link_limited(:)]; %#ok<AGROW>
    nk = [nk; G(t).no_action_ok(:)]; cm = [cm; G(t).committed(:)]; %#ok<AGROW>
end
in = st > 0;
k = struct('r', sum(st == 1 & ~lm), 'l', sum(st == 1 & lm), 'm', sum(st == 2), 'x', sum(st == 3), ...
    'nok', sum(nk & in), 'com', sum(cm & in), 'n', sum(in));
end
