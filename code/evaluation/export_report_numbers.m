%% EXPORT_REPORT_NUMBERS - Result numbers of the final reading in one JSON file
% Collects the numbers the written reports quote (KPI summary, detector
% metrics and main confusions with the readings beside KPI 1 (steady state, onset
% latency, branch level: metrics.steady, metrics.onset, metrics.branch, KP.onset), unknown-threat scores, policy evaluation,
% latency, unseen Eb/N0, unseen combined threats, the edge map's verdicts, the commitment
% at every signalling delay and its edges)
% so no number is copied by hand. Large arrays are left out. Run from the repository
% root after the KPI stage.
% A result of another detector or deployed policy, or older than its inputs
% (result_status.m), and a KPI summary older than a file it reads are flagged in
% N.stale and printed as a warning; the numbers stay, marked, for the reader to see.
% Output: results/report_numbers.json

N = struct('generated', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
RS = result_status();
st = RS([RS.stale]);
kin = {'results/eval_detector_metrics.mat', 'results/eval_detector_metrics_fresh2.mat', 'results/eval_detector_metrics_fresh3.mat', ...
    'results/ood_detection.mat', 'results/policy_evaluation.mat', ...
    'results/latency.mat', 'results/edge_map.mat', 'results/phy_validation.txt'};   % files the KPI summary reads
if isfile('results/kpi_summary.mat')
    old = kin(cellfun(@(f) isfile(f) && dir(f).datenum > dir('results/kpi_summary.mat').datenum, kin));
    if ~isempty(old)
        st(end+1) = struct('file', 'results/kpi_summary.mat', 'present', true, 'stale', true, ...
            'why', ['older than ' strjoin(old, ', ') ' (rerun KPI)']);
    end
end
N.stale = st;
for i = 1:numel(st), warning('export_report_numbers:stale', 'STALE %s: %s', st(i).file, st(i).why); end
N.kpi = take('results/kpi_summary.mat', 'KPI');

N.kpi1_set = kpi1_set();                                % the set KPI 1 is read on: fresh2 the third, fresh3 the fourth
for f = {'detector', 'results/eval_detector_metrics.mat'; 'detector_third', 'results/eval_detector_metrics_fresh2.mat'; ...
        'detector_fourth', 'results/eval_detector_metrics_fresh3.mat'}'
    M = take(f{2}, 'metrics');                          % the third (B3m) and fourth (B3r) test sets
    if ~isempty(M)
        cm = M.conf_mat; rn = 100 * cm ./ max(sum(cm, 2), 1);
        rn(logical(eye(size(rn)))) = 0;
        [v, ix] = sort(rn(:), 'descend'); k = min(8, nnz(v > 0));
        [ti, pj] = ind2sub(size(rn), ix(1:k));
        cls = cellstr(string(M.classes(:)));
        M.top_confusions = struct('true', reshape(cls(ti), 1, []), 'predicted', reshape(cls(pj), 1, []), ...
            'pct_of_true', num2cell(reshape(round(v(1:k), 2), 1, [])));
    end
    N.(f{1}) = M;
end

if isfile('results/ood_detection.mat')
    O = load('results/ood_detection.mat', 'R', 'NEST', 'SC', 'sel', 'K_NEW');
    N.ood = O;
end
N.ood_latency = take('results/ood_detection.mat', 'LC');            % detector cost of every unknown-threat candidate, KPI 7 budget
N.policy = take('results/policy_evaluation.mat', 'KP');
N.policy_top = take('results/policy_evaluation.mat', 'top_cfg');     % most frequent final configuration per threat
N.latency = take('results/latency.mat', 'LAT');
if isfile('results/unseen_snr.mat')
    N.unseen_snr = load('results/unseen_snr.mat', 'EBNO_ALL', 'EBNO_SEEN', 'acc', 'f1', 'gap', 'summary');
end
N.combo = take('results/combo_generalization.mat', 'res');
N.edge = take('results/edge_map.mat', 'EDGE_NUM');                 % verdict counts, commitment, edges, clean link, overhead pass

N = clean(N);
fid = fopen('results/report_numbers.json', 'w');
fprintf(fid, '%s', jsonencode(N, 'PrettyPrint', true)); fclose(fid);
fprintf('Saved results/report_numbers.json\n');

function v = take(f, name)
v = [];
if isfile(f), S = load(f, name); if isfield(S, name), v = S.(name); end, end
end

function x = clean(x)
% JSON-safe copy: categorical to text, arrays above 20,000 elements and
% unsupported types dropped
LIMIT = 20000;
if isstruct(x)
    for i = 1:numel(x)
        f = fieldnames(x);
        for j = 1:numel(f)
            x(i).(f{j}) = clean(x(i).(f{j}));
        end
    end
elseif iscell(x)
    for i = 1:numel(x), x{i} = clean(x{i}); end
elseif iscategorical(x)
    x = cellstr(x);
elseif (isnumeric(x) || islogical(x)) && numel(x) > LIMIT
    x = sprintf('[%s array left out]', mat2str(size(x)));
elseif ~(isnumeric(x) || islogical(x) || ischar(x) || isstring(x))
    x = sprintf('[%s left out]', class(x));
end
end
