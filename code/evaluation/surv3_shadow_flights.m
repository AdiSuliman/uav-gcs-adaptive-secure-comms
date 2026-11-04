function [g, SH] = surv3_shadow_flights(p, ebno, n, vrange, nrx, nf)
%SURV3_SHADOW_FLIGHTS  Flights of the airframe-shadowing combinations of
%   experiment_survivability_options.m under surv_v2, selected as the pools select theirs
%   (build_policy_pools.m, pool_geometries.m with a selection): per Eb/N0 index s the
%   candidates j = 1, 2, ... of their own seed range (surv3_shadow_seed.m), each tried once,
%   the speed uniform from the level's speed floor (shadow_speed_floor.m) to vrange(2);
%   flight r takes the first candidate whose roll-in lets the airframe hide an antenna at the
%   level p.shadow_db, the event counting within the run, with every antenna count in nrx
%   (hides_antenna.m, the GCS at the Eb/N0's distance), so every receiver compared meets it.
%   The UAV rolls in so that the airframe enters the line of sight just before the run's
%   first frame (event frame 1, flight_draws.m): all nf frames lie after the onset, as the
%   threat is on from the first frame in the other cases.
%   p       params of the experiment, the variants' GCS direction set
%   ebno    Eb/N0 grid [dB]; n flights per Eb/N0, run ids surv3_run_id(1:n)
%   vrange  UAV speed range [km/h]
%   g       1 x numel(ebno) cell of pool_cell.m geometries: seed, speed, run, alt, ksig,
%           aoa1, rho (NaN: the flight's own), frames (nf) and event (1)
%   SH      band (rolls [deg]), v_kmh (speeds flown), level [dB], n_rx, tried (candidates
%           per Eb/N0), kept
ps = p; ps.active_threat = 'airframe_shadowing';
band = shadow_roll_band(ps.shadow_db, ps);
vr = [max(vrange(1), shadow_speed_floor(band, ps)), vrange(2)];
if ~(vr(1) < vr(2))
    error('surv3_shadow_flights:speed', 'airframe shadowing of %g dB occurs at no speed of %g-%g km/h', ...
        ps.shadow_db, vrange(1), vrange(2));
end
nS = numel(ebno); g = cell(1, nS); tried = zeros(1, nS);
for s = 1:nS
    gd = struct('ebno', ebno(s), 'event_frame', 1, 'frames', nf);
    sel = struct('seed', @(j, v) surv3_shadow_seed(s, j, v), 'j0', 0, 'jmax', 99999, ...
        'keep', @(sd, v, varargin) hides_all(sd, v, ps, nrx, gd));
    [gs, info] = pool_geometries(s, 13, 1:n, vr, ps, [], 1, sel);
    gs.frames = nf * ones(1, n); gs.event = ones(1, n);
    g{s} = gs; tried(s) = sum(info.tries);
end
SH = struct('band', band, 'v_kmh', vr, 'level', ps.shadow_db, 'n_rx', nrx, 'tried', tried, 'kept', n * ones(1, nS));
end

function h = hides_all(seed, v, p, nrx, geo)
% The flight hides an antenna with every antenna count in nrx.
h = true;
for k = nrx(:)'
    p.n_rx = k;
    if ~hides_antenna(seed, v, p, geo), h = false; return; end
end
end
