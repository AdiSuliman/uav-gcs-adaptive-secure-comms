function v = iot_db(rssi_db, sinr_db, snr_sample_db, sps)
%IOT_DB  Interference over thermal [dB] on antenna 1 (D43).
%   Residual (interference + noise) power = RSSI / (1 + SINR), divided by the
%   receiver's thermal noise power. The thermal floor is a receiver calibration
%   constant (kTB x noise figure); in the normalized simulation it is the AWGN
%   noise power per sample, (1/sps) / 10^(snr_sample_db/10). ~0 dB on a clean
%   link, > 0 dB when an external signal raises the floor (cf. 3GPP IoT).
pe = 10.^(rssi_db/10) ./ (1 + 10.^(sinr_db/10));
n0 = (1/sps) ./ 10.^(snr_sample_db/10);
v = 10*log10(pe ./ n0);
end
