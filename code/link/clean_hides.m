function H = clean_hides(cov, ebno, p0, level_db, event_frame, frames)
%CLEAN_HIDES  Which clean flights are in a geometry where the airframe would hide an antenna
%   (D121 item 15): hides_antenna.m on the flight's own draws with airframe shadowing switched on
%   in a copy of the params at level_db, no loss applied to the clean flight. Geometry only.
%   cov          per-flight draws of the clean pools (CT.cov, flight_cov.m): seed, speed, alt_m,
%                k_sig, aoa (x 3, the first interferer's direction) and rho, Eb/N0 x flights
%   ebno         the Eb/N0 [dB] of each row; p0 the params; level_db the shadowing level
%   event_frame, frames   as hides_antenna.m's geo (decision_config.m C.event_frame, C.event_count)
%   H            Eb/N0 x flights logical; false where the flight's draws are missing
H = false(size(cov.seed));
ps = p0; ps.active_threat = 'airframe_shadowing'; ps.shadow_db = level_db;
for s = 1:size(H, 1)
    for r = 1:size(H, 2)
        if ~isfinite(cov.seed(s, r)), continue; end
        H(s, r) = hides_antenna(cov.seed(s, r), cov.speed(s, r), ps, struct('ebno', ebno(s), 'alt_m', cov.alt_m(s, r), ...
            'k_sig_db', cov.k_sig(s, r), 'aoa1_deg', cov.aoa(s, r, 1), 'rho', cov.rho(s, r), ...
            'event_frame', event_frame, 'frames', frames));
    end
end
end
