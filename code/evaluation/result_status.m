function S = result_status()
%RESULT_STATUS  Whether the result files the KPIs and the exports read belong to the
%   current detector, decision layer and link model. Run from the repository root.
%   S: struct array, one entry per file: file, present, stale (it belongs to another
%   detector or deployed policy, or is older than an input it reads), why.
%     results/latency.mat           LAT.det_id and LAT.policy_stamp (measure_latency.m) are
%                                   the current detector's (detector_id.m of
%                                   data/trained_detector.mat with the fusion and the
%                                   unknown-threat threshold) and the current deployed
%                                   policy's (policy_stamp.m of data/trained_dqn.mat); newer
%                                   than data/trained_dqn.mat
%     results/policy_evaluation.mat KP.policy_stamp the current one; newer than
%                                   data/trained_dqn.mat
%     results/edge_map.mat          EM.det_id and EM.policy_stamp the current ones; newer
%                                   than results/policy_evaluation.mat
%     results/phy_validation.txt    run on the parameters of params.mat (params_id.m; its time
%                                   when the report carries no identity)
%     results/eval_detector_metrics.mat  newer than the detector's training
%   A file without its identity fields counts as stale.
cur_det = ''; cur_pol = ''; t_det = -inf;
if all(isfile({'data/trained_detector.mat', 'data/ood_thresholds.mat'}))
    D = load('data/trained_detector.mat', 'trained_at', 'ood');
    if isfield(D, 'trained_at'), t_det = D.trained_at; end
    try
        cur_det = detector_id(D.trained_at, D.ood, fusion_model());
    catch
    end
end
if isfile('data/trained_dqn.mat')
    Q = load('data/trained_dqn.mat', 'agent', 'confirm', 'alarm_mode', 'drop_db', 'deployed', 'rule_sel', 'det_id', 'maha_thr');
    cur_pol = policy_stamp(Q);
end
t = @(f) file_time(f);
S = struct('file', {}, 'present', {}, 'stale', {}, 'why', {});
f = 'results/latency.mat'; why = {};
if isfile(f)
    L = load(f, 'LAT'); L = L.LAT;
    why = [why, id_check(L, 'det_id', cur_det, 'another detector'), id_check(L, 'policy_stamp', cur_pol, 'another deployed policy')];
    if t(f) < t('data/trained_dqn.mat'), why{end+1} = 'older than data/trained_dqn.mat'; end
end
S(end+1) = entry(f, why);
f = 'results/policy_evaluation.mat'; why = {};
if isfile(f)
    P = load(f, 'KP'); P = P.KP;
    why = id_check(P, 'policy_stamp', cur_pol, 'another deployed policy');
    if t(f) < t('data/trained_dqn.mat'), why{end+1} = 'older than data/trained_dqn.mat'; end
end
S(end+1) = entry(f, why);
f = 'results/edge_map.mat'; why = {};
if isfile(f)
    E = load(f, 'EM'); E = E.EM;
    why = [id_check(E, 'det_id', cur_det, 'another detector'), id_check(E, 'policy_stamp', cur_pol, 'another deployed policy')];
    if t(f) < t('results/policy_evaluation.mat'), why{end+1} = 'older than results/policy_evaluation.mat'; end
end
S(end+1) = entry(f, why);
f = 'results/phy_validation.txt'; why = {};
if isfile(f)
    tk = regexp(fileread(f), 'params_id (\w+)', 'tokens', 'once');
    if isempty(tk) && t(f) < t('params.mat'), why = {'older than params.mat (the link model)'};
    elseif ~isempty(tk) && isfile('params.mat') && ~strcmp(tk{1}, params_id(load('params.mat').params))
        why = {'run on other link-model parameters'};
    end
end
S(end+1) = entry(f, why);
f = 'results/eval_detector_metrics.mat'; why = {};
if isfile(f) && t(f) < t_det, why = {'older than the detector''s training'}; end
S(end+1) = entry(f, why);
end

function why = id_check(X, field, cur, what)
% Reason the identity field of X is not the current one ({} when it is).
why = {};
if isempty(cur), return; end
if ~isfield(X, field) || isempty(X.(field)), why = {sprintf('no %s', field)};
elseif ~strcmp(X.(field), cur), why = {sprintf('%s of %s', field, what)};
end
end

function e = entry(f, why)
e = struct('file', f, 'present', isfile(f), 'stale', isfile(f) && ~isempty(why), 'why', strjoin(why, '; '));
end

function t = file_time(f)
if isfile(f), t = dir(f).datenum; else, t = -inf; end
end
