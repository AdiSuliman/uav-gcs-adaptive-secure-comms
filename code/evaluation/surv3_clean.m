function c = surv3_clean(Pc, n)
%SURV3_CLEAN  One clean link of experiment_survivability_options.m from its pools Pc
%   {Eb/N0} (no_action) under surv_v2: ber, fer per Eb/N0 over every geometry's frames (the
%   reference, as without surv_v2), and ber_geo, fer_geo per Eb/N0 x geometry (run ids
%   surv3_run_id(1:n)), kept for paired readings.
c = struct('ber', cellfun(@(Q) mean(Q.ber), Pc(:))', 'fer', cellfun(@(Q) mean(double(Q.fer)), Pc(:))');
nS = numel(Pc);
c.ber_geo = nan(nS, n); c.fer_geo = nan(nS, n);
for s = 1:nS
    for r = 1:n
        m = Pc{s}.run == surv3_run_id(r);
        c.ber_geo(s, r) = mean(Pc{s}.ber(m)); c.fer_geo(s, r) = mean(double(Pc{s}.fer(m)));
    end
end
end
