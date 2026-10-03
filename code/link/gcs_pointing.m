function [g, loss_db] = gcs_pointing(seed, p)
%GCS_POINTING  Amplitude of our signal after the GCS tracker's pointing error, one seeded sub-run.
%   [g, loss_db] = gcs_pointing(seed, p): azimuth and elevation errors half-normal with the
%   measured means p.gcs_err_deg (Nugroho & Dectaviansyah), held for the sub-run; loss of the
%   p.gcs_ant_dbi antenna at that off-axis angle from the ITU-R F.1336 main lobe,
%   12 (phi / phi3)^2, phi3 = sqrt(27000 10^(-G0/10)) deg, up to its p.gcs_floor_db edge.
%   Without a tracked antenna (p.gcs_tracked false) g = 1.
if ~p.gcs_tracked
    g = 1; loss_db = 0;
    return;
end
rs = seed_stream(seed, 'gcs');
sig = p.gcs_err_deg * sqrt(pi / 2);                  % half-normal scale from its mean
e = abs(randn(rs, 1, 2)) .* sig;
phi3 = sqrt(27000 * 10^(-p.gcs_ant_dbi / 10));
loss_db = min(12 * sum(e.^2) / phi3^2, p.gcs_floor_db);
g = 10^(-loss_db / 20);
end
