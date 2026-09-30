function SC = v3d_scenarios(M)
%V3D_SCENARIOS  Scripted defense scenarios of the 3D view.
%   SC = v3d_scenarios(M)     M from v3d_engine('load')
%
%   Every scenario runs on the TEST pools. The flight geometry is chosen by a
%   rule fixed in advance, never by the outcome: among the test geometries of the
%   (threat, Eb/N0) cell, the one whose first interferer direction is nearest the
%   target angle. The threat starts at cycle 5 of 26; the comparison is rules +
%   escalation.
defs = {
%   id            title                                         threat                  Eb/N0 target follow unknown
    'null_works', 'Jammer far from the GCS direction',          'jamming',              6,    70,    false, false
    'null_fails', 'Jammer almost in line with the GCS',         'jamming',              6,    0,     false, false
    'follower',   'A jammer that follows every channel hop',    'jamming',              6,    0,     true,  false
    'unknown',    'A threat the detector is not allowed to name', 'reactive_jamming',   6,    60,    false, true
    'combined',   'Spoofer and noise bursts at the same time',  'spoofing+noise_burst', 6,    60,    false, false
    'path_loss',  'The signal fades: 10 dB of extra path loss', 'path_loss',            4,    NaN,   false, false
    'fault',      'One UAV antenna keeps dropping out',         'antenna_fault',        4,    NaN,   false, false
    };
SC = struct([]);
for i = 1:size(defs, 1)
    scn = M.avail(find(strcmp(M.PP.scen(M.avail), defs{i, 3}), 1));
    s = find(M.PP.ebno == defs{i, 4}, 1);
    r = 1; th = NaN;
    if ~isnan(defs{i, 5})
        P = M.PP.pools{scn, s, M.na, M.split};
        a = arrayfun(@(rr) P.aoa(find(P.run == M.PP.runs{M.split}(rr), 1), 1), 1:M.nR);
        [~, r] = min(abs(abs(a) - defs{i, 5}));
        th = a(r);
    end
    SC(i).id = defs{i, 1}; SC(i).title = defs{i, 2}; SC(i).threat = defs{i, 3};
    SC(i).s = s; SC(i).r = r; SC(i).th = th;
    SC(i).follow = defs{i, 6}; SC(i).unk = defs{i, 7};
    SC(i).onset = 5; SC(i).T = 26; SC(i).right = 'rule'; SC(i).seed = 100 + i;
end
end
