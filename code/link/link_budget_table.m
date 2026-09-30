%% LINK_BUDGET_TABLE - What the simulated Eb/N0 and severities mean physically
% The link model is link-level: range enters only through Eb/N0, the jammer's range
% through the JSR, and obstruction through the path loss. This table turns them
% into distances with the free-space (Friis) loss at 2.4 GHz for three stated
% hardware profiles; the simulated results hold for every profile, only the
% distance attached to each Eb/N0 changes. Air-ground measurement campaigns used
% transmit powers of 27-44 dBm (Khawaja et al.). Distances are shown up to the radio
% horizon (4/3 earth radius) of the UAV altitude and never beyond 50 km, the range of
% the close-range UAV class (Tlili et al.), the largest class the system is built for.
% Illustrative only: not an input of any stage.
% Output: results/link_budget.txt

f   = 2.4e9;
S   = load('params.mat'); ebno = S.params.EbNo_dB;
C   = decision_config();
Gr  = 2;      % UAV antenna gain [dBi] (omni dipole)
NF  = 5;      % UAV receiver noise figure [dB]
Lm  = 10;     % fading and implementation margin [dB]
Rb  = 2e6;    % bit rate [b/s] (QPSK, 1 Msym/s)
Pj  = 40;     % jammer power [dBm] (10 W)
Gj  = 3;      % jammer antenna gain [dBi]
hG  = 10;     % GCS antenna height [m]
DMAX = 50;    % range of the close-range UAV class [km] (Tlili et al.)
prof = struct('name', {'A small UAV radio', 'B tactical data link'}, ...
    'Pt', {20, 30}, 'Gt', {6, 12}, 'hU', {300, 1000});
horizon_km = @(h1, h2) 4.12 * (sqrt(h1) + sqrt(h2));                % 4/3 earth radius, heights in m
Pr = ebno - 174 + NF + 10*log10(Rb);                                 % received power needed [dBm]

rep = {'=== LINK BUDGET: Eb/N0 AND SEVERITIES AS DISTANCES (illustrative) ===', ...
    sprintf(['Common assumptions: 2.4 GHz free space; UAV %g dBi, NF %g dB; margin %g dB; %g Mb/s; ' ...
    'jammer %g dBm, %g dBi; GCS antenna %g m'], Gr, NF, Lm, Rb/1e6, Pj, Gj, hG), ''};
rep{end+1} = sprintf('%-42s %s', 'Eb/N0 per UAV antenna', sprintf('%9g dB', ebno));
for k = 1:numel(prof)
    P = prof(k);
    d = 10.^((P.Pt + P.Gt + Gr - Lm - Pr - 20*log10(f/1e6) - 32.44) / 20);   % km
    hz = horizon_km(P.hU, hG);
    cells_km = arrayfun(@(x) km_txt(x, min(hz, DMAX)), d, 'UniformOutput', false);
    rep{end+1} = sprintf('%-42s %s', sprintf('%s (%g dBm, %g dBi)', P.name, P.Pt, P.Gt), ...
        sprintf('%11s', cells_km{:})); %#ok<SAGROW>
    rep{end+1} = sprintf('%-42s radio horizon at %g m altitude: %.0f km', '', P.hU, hz); %#ok<SAGROW>
end
rep{end+1} = sprintf('(* the free-space range exceeds the radio horizon or %g km, the close-range class)', DMAX);
rep{end+1} = '';
rep{end+1} = 'In-band interferer (JSR at the UAV) -> jammer distance relative to the UAV-GCS distance, profile A:';
jsr = C.sev.jamming.levels;
dj = 10.^(-(jsr - (Pj + Gj - prof(1).Pt - prof(1).Gt)) / 20);
for i = 1:numel(jsr)
    rep{end+1} = sprintf('  JSR %2g dB  ->  jammer at %.2f x the GCS distance (%.1f km when the GCS is 10 km away)', ...
        jsr(i), dj(i), 10 * dj(i)); %#ok<SAGROW>
end
rep{end+1} = '';
pl = C.sev.path_loss.levels;
rep{end+1} = sprintf('Path loss %s dB = the signal of a UAV %s times farther, or an obstruction of that loss.', ...
    strjoin(arrayfun(@(x) sprintf('%g', x), pl, 'UniformOutput', false), ' / '), ...
    strjoin(arrayfun(@(x) sprintf('%.1f', 10^(x/20)), pl, 'UniformOutput', false), ' / '));
sp = C.sev.spoofing.levels;
rep{end+1} = sprintf('Spoofer %s dB over our signal = a counterfeit transmitter %s times the GCS power at equal distance.', ...
    strjoin(arrayfun(@(x) sprintf('%g', x), sp, 'UniformOutput', false), ' / '), ...
    strjoin(arrayfun(@(x) sprintf('%.2g', 10^(x/10)), sp, 'UniformOutput', false), ' / '));
fid = fopen('results/link_budget.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('%s\n', rep{:});

function s = km_txt(d, hz)
if d > hz, s = sprintf('>%.0f*', hz); else, s = sprintf('%.1f', d); end
end
