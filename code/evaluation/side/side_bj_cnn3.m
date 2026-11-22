function S = side_bj_cnn3(bw_tree, out_dir)
%SIDE_BJ_CNN3  The CNN's contribution per jammer width and per JSR_tot, in goodput and in detection to
%   restored, from CORE_BW's saved test readings: a labelled side reading of the lines protocol 6.5 named
%   and the report did not compute (D106, defects).
%   S = side_bj_cnn3(bw_tree, out_dir)
%   bw_tree  CORE_BW's tree, opened read-only: results/core_bw/test_readings.mat (RES, EPs, X),
%            results/core_bw/recoverable.txt, results/core_bw/core_bw_kpis.mat (KP), params.mat
%   out_dir  a new folder; side_bj_cnn3.txt and .mat are written there
%   The report's mask and pairing (experiment_core_bw.m per_lines, bj_lines): hop rule X.RULES{1}, set
%   primary, the recoverable scenarios of that rule on the fixed-total cells (not the equal in-band
%   slices, not Liu's occupied reading). Pairs rule_core3 - blind_core and rule_core - blind_core (hybrid,
%   secondary). Per B_J and per (B_J, JSR_tot): the PER difference (seed 6), the PER reduction of one
%   against the other (seed 7), the goodput difference in bit/s at the nominal payload (seed 8) and
%   detection to restored on the episodes both rows recover (seed 9), each with its 95% bootstrap over
%   flight geometries (boot_cluster.m, X.B draws), beside the share never restored of each row.
%   First the report's numbers it leans on are reproduced exactly (KP.primary's pairs pooled, narrowband
%   and wideband; KP.by_bj's PER differences), or nothing is written.
f = struct('test', fullfile(bw_tree, 'results', 'core_bw', 'test_readings.mat'), ...
    'rec', fullfile(bw_tree, 'results', 'core_bw', 'recoverable.txt'), ...
    'kpis', fullfile(bw_tree, 'results', 'core_bw', 'core_bw_kpis.mat'), 'params', fullfile(bw_tree, 'params.mat'));
for n = fieldnames(f)'
    if ~isfile(f.(n{1})), error('side_bj:input', 'side_bj_cnn3: %s not found', f.(n{1})); end
end
W = load(f.test, 'RES', 'EPs', 'X'); RES = W.RES; EP = W.EPs; X = W.X;
K = load(f.kpis, 'KP'); KP = K.KP;
p0 = load(f.params).params; pay = p0.bits_per_frame / p0.cycle_s;
REC = read_recoverable(f.rec);
q1 = X.RULES{1};
mask = recoverable_mask(REC, q1, EP) & ~EP.slice & ~EP.occ;
St = RES(strcmp({RES.rule}, q1) & strcmp({RES.set}, 'primary'));
Rn = pol(St, 'none'); m0 = mask(Rn.ep); e = Rn.ep;
c3 = any(strcmp({St.policy}, 'rule_core3'));
pairs = {'rule_core', 'blind_core', 'cnn', ''};
if c3, pairs = {'rule_core3', 'blind_core', 'cnn', ''; 'rule_core', 'blind_core', 'cnn_hybrid', ' (hybrid, secondary)'}; end
% Reproduction of the report's numbers
types = {'pooled', true(1, EP.n); 'narrowband', EP.narrow; 'wideband', ~EP.narrow};
bad = {};
for c = 1:size(pairs, 1)
    for t = 1:size(types, 1)
        V = pair_cell(pol(St, pairs{c, 1}), pol(St, pairs{c, 2}), m0 & types{t, 2}(e), EP, e, X.B, pay);
        Kc = KP.primary.(pairs{c, 3}).(types{t, 1});
        if ~(isequaln(V.per, Kc.per) && isequaln(V.gput, Kc.gput) && isequaln(V.trec, Kc.trec) && V.n_both == Kc.n_both)
            bad{end+1} = sprintf('%s %s', pairs{c, 3}, types{t, 1}); %#ok<AGROW>
        end
    end
end
BJ = unique(EP.bj(~EP.slice & ~EP.occ));
fb = 'cnn'; if c3, fb = 'cnn3'; end
for i = 1:numel(BJ)
    j = find([KP.by_bj.bj] == BJ(i), 1);
    V = pair_cell(pol(St, pairs{1, 1}), pol(St, pairs{1, 2}), m0 & EP.bj(e) == BJ(i), EP, e, X.B, pay);
    if isempty(j) || ~isequaln(V.per, KP.by_bj(j).(fb)), bad{end+1} = sprintf('by_bj %s', bj_name(BJ(i))); end %#ok<AGROW>
end
notes = {['protocol 6.5 (docs/core_bw_protocol.md): CNN contribution rule_core3 - blind_core in PER, goodput and ' ...
    't_rec_det, paired 95% intervals, pooled, per type and per B_J; the per-B_J goodput and t_rec_det were not computed ' ...
    '(D106, defects)'], sprintf('hop rule %s, set primary, recoverable scenarios of %s on the fixed-total cells; payload %g bit/s', ...
    q1, q1, pay), sprintf('other inputs: %s (SHA-256 %s), %s (SHA-256 %s)', f.rec, side_sha256(f.rec), f.kpis, side_sha256(f.kpis))};
L = side_header('CNN contribution per jammer width and JSR, goodput and detection to restored (CORE_BW)', f.test, notes);
if ~isempty(bad)
    L{end+1} = sprintf('NOT REPRODUCED (%s): nothing is read', strjoin(bad, ', '));
    fprintf('%s\n', L{:});
    error('side_bj:reproduce', 'side_bj_cnn3: the report''s numbers are not reproduced: %s', strjoin(bad, ', '));
end
L{end+1} = sprintf(['reproduced exactly first: the report''s pairs pooled, narrowband and wideband (PER, goodput, ' ...
    'detection to restored) and its per-B_J PER differences of %s'], pairs{1, 1});
rows = struct('pair', {}, 'bj', {}, 'tot', {}, 'n', {}, 'per', {}, 'per_red', {}, 'gput', {}, 'trec', {}, 'n_both', {}, 'never', {});
for c = 1:size(pairs, 1)
    Rr = pol(St, pairs{c, 1}); Rb = pol(St, pairs{c, 2});
    L{end+1} = ''; %#ok<AGROW>
    L{end+1} = sprintf('--- %s - %s%s, per B_J and per JSR_tot ---', pairs{c, 1}, pairs{c, 2}, pairs{c, 4}); %#ok<AGROW>
    for i = 1:numel(BJ)
        mb = m0 & EP.bj(e) == BJ(i);
        for tot = [NaN, unique(EP.tot(e(mb)))]
            m = mb; if ~isnan(tot), m = m & EP.tot(e) == tot; end
            V = pair_cell(Rr, Rb, m, EP, e, X.B, pay);
            rows(end+1) = struct('pair', sprintf('%s - %s', pairs{c, 1}, pairs{c, 2}), 'bj', BJ(i), 'tot', tot, 'n', nnz(m), ...
                'per', V.per, 'per_red', V.per_red, 'gput', V.gput, 'trec', V.trec, 'n_both', V.n_both, 'never', V.never); %#ok<AGROW>
            L{end+1} = sprintf(['  B_J %5s %-14s n=%5d: goodput %+.0f [%+.0f, %+.0f] bit/s | detection->restored %+.2f ' ...
                '[%+.2f, %+.2f] cycles on the %d episodes both recover in (never %.0f%% vs %.0f%%) | PER %+.4f [%+.4f, %+.4f] ' ...
                '(reduction %5.1f%% [%5.1f, %5.1f])'], bj_name(BJ(i)), ternary(isnan(tot), 'every JSR_tot', ...
                sprintf('JSR_tot %g dB', tot)), nnz(m), V.gput, V.trec, V.n_both, 100 * V.never, V.per, 100 * V.per_red); %#ok<AGROW>
        end
    end
end
S = struct('input', f.test, 'sha256', side_sha256(f.test), 'rule', q1, 'payload_bps', pay, 'rows', {rows});
out = side_out_dir(out_dir, struct2cell(f)');
side_write(out, 'side_bj_cnn3', L, S);
fprintf('%s\n', L{:});
end

function V = pair_cell(Rr, Rb, m, EP, e, B, pay)
% The report's CNN-contribution reading of one pair on the episodes m (experiment_core_bw.m per_lines).
cl = EP.geom(e(m));
[dp, dlo, dhi] = boot_cluster(Rr.per_post(m) - Rb.per_post(m), ones(1, nnz(m)), cl, B, 6);
[rr, rlo, rhi] = per_reduction(Rr.per_post(m), Rb.per_post(m), cl, B, 7);
[dg, glo, ghi] = boot_cluster(pay * (Rr.dlv_post(m) - Rb.dlv_post(m)), ones(1, nnz(m)), cl, B, 8);
f = m & isfinite(Rr.t_rec_det) & isfinite(Rb.t_rec_det);
[dt, tlo, thi] = boot_cluster(Rr.t_rec_det(f) - Rb.t_rec_det(f), ones(1, nnz(f)), EP.geom(e(f)), B, 9);
V = struct('per', [dp dlo dhi], 'per_red', [rr rlo rhi], 'gput', [dg glo ghi], 'trec', [dt tlo thi], 'n_both', nnz(f), ...
    'never', [mean(~isfinite(Rr.t_rec_det(m))), mean(~isfinite(Rb.t_rec_det(m)))]);
end

function REC = read_recoverable(f)
% The frozen list (experiment_core_bw.m read_recoverable): rule, scenario and Eb/N0 indices, recoverable.
t = strtrim(splitlines(fileread(f)));
t = t(~cellfun(@isempty, t) & ~startsWith(t, '#'));
c = cellfun(@(x) strsplit(x, ' '), t, 'UniformOutput', false);
REC = struct('rule', {cellfun(@(x) x{1}, c, 'UniformOutput', false)'}, 'k', cellfun(@(x) str2double(x{2}), c)', ...
    's', cellfun(@(x) str2double(x{3}), c)', 'ok', cellfun(@(x) str2double(x{end}), c)' > 0);
end

function m = recoverable_mask(REC, rule, EP)
j = find(strcmp(REC.rule, rule) & REC.ok);
m = false(1, EP.n);
for i = j, m = m | (EP.k == REC.k(i) & EP.s == REC.s(i)); end
end

function R = pol(S, name)
R = S(strcmp({S.policy}, name)).R;
end

function s = bj_name(bj)
if bj == 0, s = 'CW'; else, s = sprintf('%g', bj); end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
