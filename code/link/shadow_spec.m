function s = shadow_spec(p)
%SHADOW_SPEC  Airframe shadowing of a threat build, as the blocks and flight_draws.m use it.
%   s = shadow_spec(p): [depth lo hi hdg_min v_min k_db evt_db el_s]: the level p.shadow_db
%   [dB], the rolls it is flown at (shadow_roll_band.m), the heading criterion, the speed
%   floor, the hidden antenna's K-factor, the smallest loss of a counted event and Sun et
%   al.'s elevation (shadow_equiv_roll.m); zeros when p.active_threat has no airframe
%   shadowing.
s = zeros(1, 8);
if ~isfield(p, 'active_threat') || ~any(strcmp(strsplit(lower(p.active_threat), '+'), 'airframe_shadowing'))
    return
end
s = [p.shadow_db, shadow_roll_band(p.shadow_db, p), p.shadow_hdg_deg, p.shadow_v_min, p.shadow_k_db, ...
    p.shadow_evt_db, p.shadow_el_deg];
end
