function [fl, why] = console_flights(p, ebno, v_kmh, seed0, n)
%CONSOLE_FLIGHTS  Rolling-in flights of an operator-console scenario that holds airframe
%   shadowing (demo_gui.m), selected as the evaluated pools select theirs
%   (build_policy_pools.m): candidate seed0 + j, j = 1, 2, ..., is kept when the UAV, at the
%   operator's speed, rolls into its turn so that the airframe enters the line of sight
%   just before frame C.event_frame of a run of C.event_run frames and the hidden antenna's
%   loss counts (at least p.shadow_evt_db) by frame C.event_count (hides_antenna.m, at the
%   Eb/N0's distance; decision_config.m). The clean link of the same flight before that
%   frame is the scenario's lead-in.
%   [fl, why] = console_flights(p, ebno, v_kmh, seed0, n)
%   p       the scenario's params (console_scenario.m), ebno [dB], v_kmh UAV speed [km/h]
%   seed0   candidates start above it (flight seeds stay below 2^26, seed_base.m)
%   n       flights wanted
%   fl      seed (1 x n), geo (link_seed.m: the GCS at the Eb/N0's distance, the event's
%           frame, the run's frames), nf (frames of a run), k (the event's frame), stop
%           (the sim stop time of nf frames); [] when no flight at this speed hides an
%           antenna at the level, with the reason in why
J_MAX = 5000;                                      % candidates tried before giving up
C = decision_config();
fl = []; why = '';
band = shadow_roll_band(p.shadow_db, p);
if band(1) > band(2)
    why = sprintf('no roll of the envelope carries %g dB of airframe shadowing', p.shadow_db);
    return
end
vmin = shadow_speed_floor(band, p);
if v_kmh < vmin
    why = sprintf(['airframe shadowing at %g dB needs a turn banked %.1f deg or more, which no flight ' ...
        'below %.1f km/h reaches'], p.shadow_db, band(1) - p.shadow_el_deg, vmin);
    return
end
sel = struct('ebno', ebno, 'alt_m', NaN, 'k_sig_db', NaN, 'event_frame', C.event_frame, 'frames', C.event_count);
seed = zeros(1, 0);
for j = 1:J_MAX
    if hides_antenna(seed0 + j, v_kmh, p, sel), seed(end + 1) = seed0 + j; end %#ok<AGROW>
    if numel(seed) == n, break; end
end
if numel(seed) < n
    why = sprintf('none of %d flights at %.1f km/h lets the airframe hide an antenna at %g dB', J_MAX, v_kmh, p.shadow_db);
    return
end
fl = struct('seed', seed, 'geo', struct('ebno', ebno, 'alt_m', NaN, 'k_sig_db', NaN, 'event_frame', C.event_frame, ...
    'frames', C.event_run), 'nf', C.event_run, 'k', C.event_frame, 'stop', num2str((C.event_run - 1) * p.frame_duration));
end
