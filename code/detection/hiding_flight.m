function [seed, v_kmh, j, tries] = hiding_flight(p, ebno, seed0, j, jmax)
%HIDING_FLIGHT  The next candidate flight of a detector block whose attitude hides an
%   antenna at the block's airframe-shadowing level (eval_unseen_snr.m,
%   eval_unseen_severity.m), as the dataset selects its shadowing flights
%   (run_dataset_sweep.m): a block whose flight hides none would be the clean link.
%   [seed, v_kmh, j, tries] = hiding_flight(p, ebno, seed0, j, jmax)
%   p      params of the block's build (active_threat, shadow_db, cap_frames: its frames)
%   ebno   the block's Eb/N0 [dB] (the GCS's distance and elevation)
%   seed0  candidate k has the seed seed0 + k, its speed uniform over the envelope from the
%          seed's own speed stream (seed_stream.m); j the last candidate tried before
%          (each is tried once, kept or skipped); at most jmax candidates
%   seed, v_kmh  the flight kept; j its candidate; tries: candidates tried for it
tries = 0;
while true
    j = j + 1; tries = tries + 1;
    if j > jmax, error('hiding_flight: no candidate up to %d hides an antenna at %g dB', jmax, p.shadow_db); end
    seed = seed0 + j;
    v_kmh = p.speed_kmh_min + rand(seed_stream(seed, 'speed')) * (p.speed_kmh_max - p.speed_kmh_min);
    if hides_antenna(seed, v_kmh, p, struct('ebno', ebno, 'alt_m', NaN, 'k_sig_db', NaN)), return; end
end
end
