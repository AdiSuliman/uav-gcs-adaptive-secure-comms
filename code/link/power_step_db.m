function g = power_step_db(p)
%POWER_STEP_DB  Gain of the power_control action [dB]: the GCS radio's power raised by
%   its largest step (p.gcs_step_db: 0.25 dB on an AD9361-class radio) that keeps the
%   e.i.r.p. under the licence-exempt cap (p.gcs_eirp_cap_dbm, from the nominal
%   p.gcs_pt_dbm + p.gcs_ant_dbi) and the radio under its largest output (p.gcs_pmax_dbm).
%   Params without the radio fields: its next step p.cm_power_db (6 dB), under the cap.
g = 6;
if isfield(p, 'cm_power_db'), g = p.cm_power_db; end
if all(isfield(p, {'gcs_pmax_dbm', 'gcs_pt_dbm'})), g = p.gcs_pmax_dbm - p.gcs_pt_dbm; end
if all(isfield(p, {'gcs_eirp_cap_dbm', 'gcs_pt_dbm', 'gcs_ant_dbi'}))
    g = min(g, p.gcs_eirp_cap_dbm - p.gcs_pt_dbm - p.gcs_ant_dbi);
end
if isfield(p, 'gcs_step_db') && p.gcs_step_db > 0
    g = floor(g / p.gcs_step_db + 1e-9) * p.gcs_step_db;
end
g = max(0, g);
end
