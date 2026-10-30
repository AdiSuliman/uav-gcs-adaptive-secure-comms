function [G, PP, CV, rep] = unk_guard(PP, CV, mode, thr, ebno_thr, T, split, cnt)
%UNK_GUARD  D111 guard (e), first at C1d (choose_drop_threshold.m, before D103's choice of the
%   degradation test and before D112): with FM.unk in PP.fuse, on C1d's clean validation
%   episodes (clean_wide_specs.m, the independent clean geometries of CV), at the reference
%   monitor (C.confirm, the drop alarm of form mode at threshold thr), with unk_mode 'all' and
%   retention 0.95 and 0.99, the whole monitor's clean false-change share under U must be at most
%   s0's + 1.0 point at both retentions. A false change is a clean episode whose monitor confirms
%   an alarm at no_action (monitor_trace.m, monitor_confirm.m): up to its first change every
%   policy flies that episode, so the share bounds every policy's. s0's monitor is the same
%   without FM.unk at unk_threshold(PP.maha_val, retention).
%   When it fails, FM.unk is removed from data/fusion.mat (unk_write.m 'remove'), the pools are
%   re-keyed (rekey_pools.m) and PP and CV reloaded before the choice of the degradation test,
%   C0 stands, and the reason is written to results/unk_guard.txt.
%   cnt (optional, tests): n episodes and f, @(P) those with a confirmed alarm under P
%   G: retain, k_u, k_s0, n, share_u, share_s0, pass, removed; rep: report lines
RT = [0.95 0.99]; MARGIN = 0.010;
cf = decision_config().confirm;
PPm = PP; PPm.alarm_mode = mode; PPm.unk_mode = 'all';
if nargin < 8 || isempty(cnt)
    [spc, n] = clean_wide_specs(PPm, CV, ebno_thr, T);
    count = @(P) n_confirmed(P, CV, spc, n, split, mode, thr, cf);
else
    n = cnt.n; count = cnt.f;
end
G = struct('retain', RT, 'k_u', zeros(1, 2), 'k_s0', zeros(1, 2), 'n', n, 'share_u', zeros(1, 2), ...
    'share_s0', zeros(1, 2), 'pass', false, 'removed', false);
for i = 1:numel(RT)
    Pu = PPm; Pu.unk_retain = RT(i); Pu.maha_thr = unk_threshold(Pu, RT(i));
    Ps = PPm; Ps.fuse = rmfield(Ps.fuse, 'unk'); Ps.unk_retain = RT(i); Ps.maha_thr = unk_threshold(PP.maha_val, RT(i));
    G.k_u(i) = count(Pu); G.k_s0(i) = count(Ps);
end
G.share_u = G.k_u / max(n, 1); G.share_s0 = G.k_s0 / max(n, 1);
G.pass = all(G.share_u <= G.share_s0 + MARGIN);
rep = {'', sprintf(['D111 guard (e): the whole monitor''s clean false-change share at no_action (%s, confirmed %d/%d, ' ...
    'unk_mode all) on %d clean validation episodes, U against s0 (at most + %.1f point):'], mode, cf, n, 100 * MARGIN)};
for i = 1:numel(RT)
    rep{end+1} = sprintf('  retention %.2f: U %d/%d (%.2f%%), s0 %d/%d (%.2f%%)', RT(i), G.k_u(i), n, 100 * G.share_u(i), ...
        G.k_s0(i), n, 100 * G.share_s0(i)); %#ok<AGROW>
end
if G.pass
    rep{end+1} = 'Guard (e) passed: FM.unk stays deployed.';
    return
end
why = sprintf(['guard (e) failed at C1d: clean false-change share under U %s against s0 %s at retention 0.95 / 0.99 ' ...
    '(more than + %.1f point)'], strjoin(compose('%.2f%%', 100 * G.share_u), ' / '), ...
    strjoin(compose('%.2f%%', 100 * G.share_s0), ' / '), 100 * MARGIN);
unk_write('remove', why, 'data/fusion.mat');
rekey_pools();
L = load('data/policy_pools.mat', 'PP'); PP = L.PP; clear L
if ~isempty(CV), Cv = load('data/clean_val_pools.mat', 'CT'); CV = Cv.CT; end
assert(~unk_stat('on', PP), 'unk_guard:rekey', 'the pools still carry FM.unk after the re-key');
G.removed = true;
rep{end+1} = ['Guard (e) FAILED: FM.unk removed (data/fusion_unk_removed.mat), the pools re-keyed, C0 stands: ' why];
fid = fopen('results/unk_guard.txt', 'w'); fprintf(fid, '%s\n', rep{2:end}); fclose(fid);
end

function k = n_confirmed(P, CV, spc, n, split, mode, thr, cf)
% Clean episodes whose monitor at no_action confirms an alarm (choose_drop_threshold.m section 5).
[Pw, Kw] = clean_world(P, CV);
Tc = monitor_trace(Pw, Kw, spc, split, 41000);
Tc.other = Tc.other(1:n, :); Tc.eg = Tc.eg(1:n, :); Tc.sw = Tc.sw(1:n, :);
k = sum(any(monitor_confirm(Tc, mode, thr, cf, []), 2));
end
