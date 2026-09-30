%% EXPORT_REPORT_NUMBERS - Result numbers of the final reading in one JSON file
% Collects the numbers the written reports quote (KPI summary, detector
% metrics and main confusions, unknown-threat scores, policy evaluation,
% latency, unseen Eb/N0, unseen combined threats) so no number is copied by
% hand. Large arrays are left out. Run from the repository root after the KPI stage.
% Output: results/report_numbers.json

N = struct('generated', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
N.kpi = take('results/kpi_summary.mat', 'KPI');

M = take('results/eval_detector_metrics.mat', 'metrics');
if ~isempty(M)
    cm = M.conf_mat; rn = 100 * cm ./ max(sum(cm, 2), 1);
    rn(logical(eye(size(rn)))) = 0;
    [v, ix] = sort(rn(:), 'descend'); k = min(8, nnz(v > 0));
    [ti, pj] = ind2sub(size(rn), ix(1:k));
    cls = cellstr(string(M.classes(:)));
    M.top_confusions = struct('true', reshape(cls(ti), 1, []), 'predicted', reshape(cls(pj), 1, []), ...
        'pct_of_true', num2cell(reshape(round(v(1:k), 2), 1, [])));
end
N.detector = M;

if isfile('results/ood_detection.mat')
    O = load('results/ood_detection.mat', 'R', 'NEST', 'SC', 'sel', 'K_NEW');
    N.ood = O;
end
N.policy = take('results/policy_evaluation.mat', 'KP');
N.policy_top = take('results/policy_evaluation.mat', 'top_cfg');     % most frequent final configuration per threat
N.latency = take('results/latency.mat', 'LAT');
if isfile('results/unseen_snr.mat')
    N.unseen_snr = load('results/unseen_snr.mat', 'EBNO_ALL', 'EBNO_SEEN', 'acc', 'f1', 'gap', 'summary');
end
N.combo = take('results/combo_generalization.mat', 'res');

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
