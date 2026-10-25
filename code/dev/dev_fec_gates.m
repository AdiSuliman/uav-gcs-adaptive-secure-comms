function G = dev_fec_gates(lost, rlost, npk, names, level, config, ebno, Q)
%DEV_FEC_GATES  The adoption checks of dev set C on the chosen variant's packet losses
%   (dev_fec_burst.m select step 4, docs/noise_burst_protocol.md section 4.2).
%   G = dev_fec_gates(lost, rlost, npk, names, level, config, ebno, Q): per point the
%   variant's lost packets, the D78 decoder's, the point's packets, its name, level,
%   configuration and Eb/N0; Q the frames of a codeword.
%   G.lim    the clean link's packet loss at 9 dB under no_action x 2, floored at one packet
%   G.j4     J4 at 4 dB under no_action loses at most G.lim (R0(1) about 0.87 in-band there)
%   G.j4_10  J4 at 10 dB under no_action loses more than Q/2 packets fewer than D78 (one loss
%            event of the coded link): at about 4 dB in-band after four-antenna MRC, R0(1) is
%            at the edge of the K = 7 code, so its loss is reported, not held to the clean link
%   G.dec775 the random jammer at duty 0.775 under no_action decodes (loss <= G.lim) at 10 dB
%            or more, where capacity is below the rate
noact = strcmp(config, 'no_action');
i9 = find(strcmp(names, 'clean_no_action') & ebno == 9, 1);
G.lim = 2 * max(lost(i9) / npk(i9), 1 / npk(i9));
i4 = find(noact & startsWith(names, 'nb_j4_') & level == 4);
i10 = find(noact & startsWith(names, 'nb_j4_') & level == 10);
i775 = find(noact & startsWith(names, 'nb_r775_') & level >= 10);
G.j4 = ~isempty(i4) && all(lost(i4) ./ npk(i4) <= G.lim);
G.j4_10 = ~isempty(i10) && all(rlost(i10) - lost(i10) > Q / 2);
G.dec775 = any(lost(i775) ./ npk(i775) <= G.lim);
end
