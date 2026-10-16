function [req, dl] = shadow_equiv_roll(beta, el, r, pitch, el_s)
%SHADOW_EQUIV_ROLL  How deep the airframe lies in the GCS's line of sight, and Sun et al.'s
%   equivalent roll of that burial [deg].
%   [req, dl] = shadow_equiv_roll(beta, el, r, pitch, el_s)
%   beta, el  GCS direction (gcs_aoa.m, as it turns with the heading) and its elevation
%             below the UAV's horizon [deg]; beta, el and r scalars or vectors of one size
%   r         roll toward the GCS [deg] (its magnitude); pitch [deg]
%   el_s      elevation of Sun et al.'s events [deg] (p.shadow_el_deg)
%   dl        burial: the angle of the GCS above the belly antennas' horizon in the body
%             frame, asind(-cz) of uav_attitude_db.m with the roll toward the GCS [deg]
%             (negative: the belly sees the GCS)
%   req       the roll at which an aircraft in level flight at elevation el_s buries its
%             line of sight as deep with the GCS abeam: dl + el_s
%   Sun et al. fit an event's loss against its largest roll, their events at 1.4-2.9 deg
%   elevation (Part IV, Sec. II, Table II): in their turns the ground station passed the
%   beam, where the roll less the elevation is how deep the airframe lay in the line of
%   sight at its deepest. A flight at another elevation is paired with the fit by that
%   burial.
%#codegen
ux = cosd(el) .* sind(beta); uy = cosd(el) .* cosd(beta); uz = sind(el);
dl = asind(min(max(abs(uy) .* sind(r) - (sind(pitch) .* ux + cosd(pitch) .* uz) .* cosd(r), -1), 1));
req = dl + el_s;
end
