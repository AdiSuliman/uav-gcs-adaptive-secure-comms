function g = power_step_db(p)
%POWER_STEP_DB  Gain of the power_control action [dB]: the radio's next power step
%   (p.cm_power_db), never above the licence-exempt e.i.r.p. cap (p.gcs_eirp_cap_dbm)
%   over the nominal e.i.r.p. of the GCS (p.gcs_pt_dbm + p.gcs_ant_dbi).
g = 6;
if isfield(p, 'cm_power_db'), g = p.cm_power_db; end
if all(isfield(p, {'gcs_eirp_cap_dbm', 'gcs_pt_dbm', 'gcs_ant_dbi'}))
    g = max(0, min(g, p.gcs_eirp_cap_dbm - p.gcs_pt_dbm - p.gcs_ant_dbi));
end
end
