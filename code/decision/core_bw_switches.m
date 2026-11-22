function out = core_bw_switches(src, B, seed)
%CORE_BW_SWITCHES  Configuration changes per episode in the CORE_BW test reading (proposal
%   mitigation 15). Descriptive: no verdict, no threshold, no effect on KPI 8.
%   out = core_bw_switches(src, B, seed)
%   src   path of results/core_bw/test_readings.mat, or a struct with the field RES
%         (fields rule, set, policy, R; R.switches, R.false_sw, R.geom, R.ep)
%   B     bootstrap resamples (2000); seed  fixed seed (91)
%   out.rows   per hop rule, set and policy: mean changes and false changes per episode
%              (whole episode) with a 95% cluster-bootstrap interval, n episodes
%   out.diffs  per hop rule and set: rule_core3 minus rule_core and rule_core3 minus
%              blind_core, paired by episode index R.ep, same metrics
%   Clusters are the flight geometries (R.geom, boot_cluster.m). A pair of policies on
%   different episode sets, or with different geometries per episode, is refused.
if nargin < 2 || isempty(B), B = 2000; end
if nargin < 3 || isempty(seed), seed = 91; end
if ischar(src) || isstring(src)
    L = load(char(src), 'RES');
    RES = L.RES;
else
    RES = src.RES;
end
metrics = {'switches', 'false_sw'};
pairs = {'rule_core3', 'rule_core'; 'rule_core3', 'blind_core'};
rules = unique({RES.rule}, 'stable');
out = struct('rows', struct('rule', {}, 'set', {}, 'policy', {}, 'metric', {}, 'mean', {}, 'lo', {}, 'hi', {}, 'n', {}), ...
    'diffs', struct('rule', {}, 'set', {}, 'a', {}, 'b', {}, 'metric', {}, 'mean', {}, 'lo', {}, 'hi', {}, 'n', {}));
fprintf('Configuration changes per episode, whole episode, 95%% cluster bootstrap (B = %d)\n', B);
for ir = 1:numel(rules)
    sets = unique({RES(strcmp({RES.rule}, rules{ir})).set}, 'stable');
    for is = 1:numel(sets)
        S = RES(strcmp({RES.rule}, rules{ir}) & strcmp({RES.set}, sets{is}));
        for k = 1:numel(S)
            R = S(k).R;
            if isempty(R.ep), continue; end
            for im = 1:numel(metrics)
                v = double(R.(metrics{im})(:)');
                [m, lo, hi] = boot_cluster(v, ones(size(v)), R.geom(:)', B, seed);
                out.rows(end+1) = struct('rule', rules{ir}, 'set', sets{is}, 'policy', S(k).policy, ...
                    'metric', metrics{im}, 'mean', m, 'lo', lo, 'hi', hi, 'n', numel(v)); %#ok<AGROW>
                fprintf('  %-8s %-9s %-17s %-9s %6.3f [%6.3f, %6.3f]  n=%d   (descriptive, mitigation 15, no verdict)\n', ...
                    rules{ir}, sets{is}, S(k).policy, metrics{im}, m, lo, hi, numel(v));
            end
        end
        for ip = 1:size(pairs, 1)
            ia = find(strcmp({S.policy}, pairs{ip, 1}), 1);
            ib = find(strcmp({S.policy}, pairs{ip, 2}), 1);
            if isempty(ia) || isempty(ib), continue; end
            Ra = S(ia).R; Rb = S(ib).R;
            if ~isequal(sort(Ra.ep(:)), sort(Rb.ep(:)))
                error('core_bw_switches:episodes', '%s/%s: %s and %s ran different episode sets', ...
                    rules{ir}, sets{is}, pairs{ip, 1}, pairs{ip, 2});
            end
            if isempty(Ra.ep), continue; end
            [~, oa] = sort(Ra.ep(:)); [~, ob] = sort(Rb.ep(:));
            ga = Ra.geom(:); ga = ga(oa); gb = Rb.geom(:); gb = gb(ob);
            if ~isequal(ga, gb)
                error('core_bw_switches:geometry', '%s/%s: %s and %s differ in the geometry of the same episode', ...
                    rules{ir}, sets{is}, pairs{ip, 1}, pairs{ip, 2});
            end
            for im = 1:numel(metrics)
                va = double(Ra.(metrics{im})(:)); va = va(oa);
                vb = double(Rb.(metrics{im})(:)); vb = vb(ob);
                d = (va - vb)';
                [m, lo, hi] = boot_cluster(d, ones(size(d)), ga', B, seed + 1);
                out.diffs(end+1) = struct('rule', rules{ir}, 'set', sets{is}, 'a', pairs{ip, 1}, 'b', pairs{ip, 2}, ...
                    'metric', metrics{im}, 'mean', m, 'lo', lo, 'hi', hi, 'n', numel(d)); %#ok<AGROW>
                fprintf('  %-8s %-9s %s minus %s %-9s %+7.3f [%+7.3f, %+7.3f]  n=%d   (descriptive, mitigation 15, no verdict)\n', ...
                    rules{ir}, sets{is}, pairs{ip, 1}, pairs{ip, 2}, metrics{im}, m, lo, hi, numel(d));
            end
        end
    end
end
end
