function d = link_distance_km(ebno, p)
%LINK_DISTANCE_KM  GCS-UAV distance at which the link has a given Eb/N0 [km].
%   d = link_distance_km(ebno, p): free space (Friis) at p.carrier_freq from the GCS
%   radio p.gcs_pt_dbm on its p.gcs_ant_dbi antenna to the UAV's p.lb_uav_dbi antenna,
%   with the received power Eb/N0 needs, ebno - 174 + p.lb_nf_db + 10 log10(p.lb_rate_bps)
%   dBm, and p.lb_margin_db to spare. Slant distance; ebno may be an array.
pr = ebno - 174 + p.lb_nf_db + 10*log10(p.lb_rate_bps);                    % received power needed [dBm]
d = 10.^((p.gcs_pt_dbm + p.gcs_ant_dbi + p.lb_uav_dbi - p.lb_margin_db - pr ...
    - 20*log10(p.carrier_freq/1e6) - 32.44) / 20);
end
