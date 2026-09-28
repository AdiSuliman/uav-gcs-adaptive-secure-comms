%% LINK_BUDGET_TABLE - What the simulated Eb/N0 and JSR mean in distance (D59)
% The link model is link-level: range enters only through Eb/N0 and the jammer's
% range through the JSR. This table turns both into distances with the free-space
% (Friis) path loss at 2.4 GHz and a stated set of typical small-UAV command-link
% assumptions, so the results can be read as "how far". Illustrative only: the
% numbers move with every assumption below and are not an input of any stage.
% Output: results/link_budget.txt

f   = 2.4e9;  c = 3e8;
Pt  = 20;     % GCS transmit power [dBm] (100 mW, typical command radio)
Gt  = 6;      % GCS antenna gain [dBi] (small directional)
Gr  = 2;      % UAV antenna gain [dBi] (omni dipole)
NF  = 5;      % UAV receiver noise figure [dB]
Lm  = 10;     % fading and implementation margin [dB]
Rb  = 2e6;    % bit rate [b/s] (QPSK, 1 Msym/s)
Pj  = 40;     % jammer power [dBm] (10 W)
Gj  = 3;      % jammer antenna gain [dBi]
fspl_km = @(d) 20*log10(d) + 20*log10(f/1e6) + 32.44;          % Friis, d in km
ebno = 0:2:10;
Pr = ebno - 174 + NF + 10*log10(Rb);                              % received power needed [dBm]
d_gcs = 10.^((Pt + Gt + Gr - Lm - Pr - 20*log10(f/1e6) - 32.44) / 20);   % km
jsr = [4 10 16];
dj_ratio = 10.^(-(jsr - (Pj + Gj - Pt - Gt)) / 20);              % jammer range / UAV-GCS range

rep = {'=== LINK BUDGET: Eb/N0 AND JSR AS DISTANCES (illustrative, D59) ===', ...
    sprintf(['Assumptions: 2.4 GHz free space; GCS %g dBm, %g dBi; UAV %g dBi, NF %g dB; margin %g dB; %g Mb/s; ' ...
    'jammer %g dBm, %g dBi'], Pt, Gt, Gr, NF, Lm, Rb/1e6, Pj, Gj), '', ...
    'Eb/N0 per UAV antenna -> UAV-GCS distance:'};
for i = 1:numel(ebno)
    rep{end+1} = sprintf('  %2g dB  ->  %5.1f km (received %.0f dBm)', ebno(i), d_gcs(i), Pr(i)); %#ok<SAGROW>
end
rep{end+1} = '';
rep{end+1} = 'JSR at the UAV -> jammer distance relative to the UAV-GCS distance (same UAV antenna):';
for i = 1:numel(jsr)
    rep{end+1} = sprintf('  JSR %2g dB  ->  jammer at %.2f x the GCS distance (e.g. %.1f km when the GCS is 10 km away)', ...
        jsr(i), dj_ratio(i), 10 * dj_ratio(i)); %#ok<SAGROW>
end
rep{end+1} = '';
rep{end+1} = 'path_loss 6 / 10 / 14 dB = the received signal of a UAV 2.0 / 3.2 / 5.0 times farther, or an obstruction of that loss.';
fid = fopen('results/link_budget.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('%s\n', rep{:});
