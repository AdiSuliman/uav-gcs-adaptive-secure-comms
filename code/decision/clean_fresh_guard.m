function DEG = clean_fresh_guard(f, smoke)
%CLEAN_FRESH_GUARD  The fresh clean test set is built only after C1d adopted a degradation test
%   (docs/p1r_protocol.md): f (data/drop_threshold.mat) must hold C1d's DEG with a candidate
%   adopted (pick > 0) and no forced mark (deg_force.m). 'ratio' kept stops P1R after C1d, so the
%   set stays unbuilt. smoke true skips the check (the reduced chain check); DEG is then [].
DEG = [];
if smoke, return; end
if ~isfile(f), error('clean_fresh_guard:none', '%s absent: the fresh set is built after C1d''s adoption', f); end
w = whos('-file', f);
if ~any(strcmp({w.name}, 'DEG'))
    error('clean_fresh_guard:none', '%s holds no degradation test chosen at C1d (deg_select)', f);
end
L = load(f, 'DEG'); DEG = L.DEG;
if isfield(DEG, 'forced')
    error('clean_fresh_guard:forced', '%s holds a forced test (%s, smoke only), not an adoption', f, DEG.forced);
end
if ~isfield(DEG, 'pick')
    error('clean_fresh_guard:none', '%s: C1d did not choose (no clean validation flights)', f);
end
if DEG.pick == 0
    error('clean_fresh_guard:ratio', ['%s: no candidate admissible, ''ratio'' kept: P1R stops after C1d and the ' ...
        'fresh set stays unbuilt (docs/p1r_protocol.md)'], f);
end
end
