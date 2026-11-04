function M = surv_nb_entries(maps, p)
%SURV_NB_ENTRIES  The survivability map's entries under surv_v2 (docs/surv_p3_protocol.md):
%   every noise_burst entry becomes two, each with a fixed pattern (pset, set on the job's
%   params by pool_job.m; jam_timing_random stays off): Xu et al.'s random jammer at the most
%   severe duty of their measured range, burst_duty = p.burst_duty_range(end) (0.775), and
%   Marti et al.'s sparse jammer J4, burst_duty = p.burst_j4(1) (0.2, one-symbol slots below
%   p.burst_duty_range(1), build_threat_model.m). Every other entry is kept, with an empty pset.
if p.burst_j4(1) >= p.burst_duty_range(1)
    error('surv_nb_entries:j4', 'J4''s duty must lie below the random jammer''s range');
end
C = {};
for k = 1:numel(maps)
    e = maps(k); e.pset = struct();
    if ~strcmp(e.base, 'noise_burst'), C{end+1} = e; continue; end %#ok<AGROW>
    r = e; r.pset = struct('burst_duty', p.burst_duty_range(end)); r.name = nb_name(e, sprintf('random %g', r.pset.burst_duty));
    j = e; j.pset = struct('burst_duty', p.burst_j4(1)); j.name = nb_name(e, sprintf('J4 %g', j.pset.burst_duty));
    C = [C, {r, j}]; %#ok<AGROW>
end
M = [C{:}];
end

function n = nb_name(e, tag)
if isnan(e.aoa), n = sprintf('%s %s', e.base, tag); else, n = sprintf('%s %s @ %g deg', e.base, tag, e.aoa); end
end
