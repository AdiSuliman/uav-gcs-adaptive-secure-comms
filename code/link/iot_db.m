function v = iot_db(rssi_db, sinr_db, nv)
%IOT_DB  Interference over thermal [dB] on one antenna.
%   Residual (interference + noise) power = RSSI / (1 + SINR), divided by the
%   receiver's thermal noise power per sample nv, its calibration constant (kTB x noise
%   figure; thermal_nv.m). ~0 dB on a clean link, > 0 dB when an external signal raises
%   the floor (cf. 3GPP IoT).
pe = 10.^(rssi_db/10) ./ (1 + 10.^(sinr_db/10));
v = 10*log10(pe ./ nv);
end
