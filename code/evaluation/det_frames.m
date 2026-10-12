function [hit, on, hit_f, age] = det_frames(P, Pc, scen, ok_c, PP)
%DET_FRAMES  DET of every frame of a pool at no_action (edge_map.m): hit (frames x rows of
%   ok_c, the classes edge_map.m counts for the threat and for its branch level), the
%   monitor's class is one ok_c counts for the threat; on, the threat is on the air
%   (threat_active.m). The monitor's class (policy_monitor.m) is the fused class, and while
%   the latched cause of a lost branch holds (onset_shape.m: read from the shape of its
%   onset) that cause for a fused antenna_fault or airframe_shadowing; hit_f the same
%   reading by the fused class alone. A path-loss or antenna-fault cell, alone or in a
%   combination, has its full loss from its run's first frame, so every flight is read after
%   the same flight's clean link (Pc, the onset between them: the connector's step, the
%   loss's step), the fused class over the joined frames; a rolling-in shadowing flight
%   holds its own lead-in (build_policy_pools.m). With the monitor's 'class_drop' alarm the
%   class path_loss counts only with the drop, so the path-loss component is detected by the
%   drop alarm alone: the Eb/N0 estimate's 3-cycle median that many dB below the median of
%   the last 10 clean cycles (policy_monitor.m).
%   age: cycles of every frame since its run's first frame with the threat on the air (NaN
%   before it): the fusion window holds the onset while age < PP.fuse_N.
on = reshape(threat_active(scen, P.act), [], 1);
use_drop = isfield(PP, 'alarm_mode') && strcmp(PP.alarm_mode, 'class_drop');
parts = strsplit(scen, '+');
has_pl = any(strcmp(parts, 'path_loss'));
if use_drop && has_pl, ok_c(:, strcmp(cellstr(string(PP.classes)), 'path_loss')) = false; end
join = (has_pl || any(strcmp(parts, 'antenna_fault'))) && ~isempty(Pc) && ~isempty(Pc.ber);
C = decision_config();
[ur, ~, ir] = unique(P.run, 'stable');
J = struct('probs', [], 'gant', [], 'feat', [], 'run', [], 'part', []);
for r = 1:numel(ur)
    ip = find(ir == r); ic = zeros(0, 1);
    if join, ic = find(Pc.run == ur(r)); end
    J.probs = [J.probs; Pc_rows(Pc, 'probs', ic); P.probs(ip, :)]; J.gant = [J.gant; Pc_rows(Pc, 'gant', ic); P.gant(ip, :)];
    J.feat = [J.feat; Pc_rows(Pc, 'feat', ic); P.feat(ip, :)]; J.run = [J.run; repmat(ur(r), numel(ic) + numel(ip), 1)];
    J.part = [J.part; zeros(numel(ic), 1); ip(:)];
end
pc = double(J.probs);
if ~isempty(PP.fuse)
    S = struct('run', J.run, 'pos', run_pos(J.run), 'gain_ant', J.gant, 'feats_raw', J.feat, 'feat_names', {link_features('names')});
    pc = fuse_classes('apply', PP.fuse, fuse_classes('windows', S, pc, PP.fuse_N));
end
[~, k] = max(pc, [], 2);
kl = k;                                                  % with the latched cause of a lost branch
if ~isempty(J.gant)
    for r = 1:numel(ur)
        j = find(J.run == ur(r));
        [~, kl(j)] = max(onset_shape('sequence', J.gant(j, :), pc(j, :), PP.classes, C.heal), [], 2);
    end
end
dd = C.drop_db; if isfield(PP, 'drop_db') && ~isempty(PP.drop_db), dd = PP.drop_db; end
eb = @(F) double(F(:, feature_index('sinr')) + F(:, feature_index('iot'))) + 10*log10(PP.sps) - 10*log10(PP.bps);
e = eb(J.feat);
hit = false(numel(P.run), size(ok_c, 1)); hit_f = hit; age = nan(numel(P.run), 1);
for r = 1:numel(ur)
    j = find(J.run == ur(r)); jc = j(J.part(j) == 0); jp = j(J.part(j) > 0);
    hit(J.part(jp), :) = ok_c(:, kl(jp))';
    hit_f(J.part(jp), :) = ok_c(:, k(jp))';
    ip = J.part(jp); f0 = find(on(ip), 1);
    if ~isempty(f0), age(ip(f0:end)) = (0:numel(ip) - f0)'; end
    if ~use_drop || ~has_pl || isempty(jc), continue; end
    ref = median(e(jc(max(1, end - 9):end)));
    for q = jp(:)'
        dr = ref - median(e(max(j(1), q - 2):q)) >= dd;
        hit(J.part(q), :) = hit(J.part(q), :) | dr;
        hit_f(J.part(q), :) = hit_f(J.part(q), :) | dr;
    end
end
end

function X = Pc_rows(Pc, f, ic)
% Rows ic of field f of the clean link's pool (none without a join).
if isempty(ic), X = zeros(0, 0); else, X = Pc.(f)(ic, :); end
end

function pos = run_pos(run)
% Position of every frame in its run (the frames of a run are consecutive).
st = [true; diff(run(:)) ~= 0];
i0 = find(st);
pos = (1:numel(run))' - i0(cumsum(st)) + 1;
end
