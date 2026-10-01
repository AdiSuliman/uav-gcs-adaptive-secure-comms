%% OVERHEAD_PASS - The link while the UAV flies over the GCS
% When the UAV passes over the GCS, the GCS lies near the axis of the UAV's vertical
% omni antennas: a half-wave dipole has a null there, and on a drone the measured
% gain directly below is about 30 dB under its horizon gain (24 dB above; Badi et
% al., 2019). The pass is also the shortest distance of the flight. This script
% follows a straight pass at a given altitude and finds, along it, the received
% power of our signal relative to the cruise point of the same flight (distance R0):
% free-space change 20 log10(R0 / r) plus the change of antenna gain between the
% elevation of the GCS there and at the cruise point. An interferer away from the GCS
% keeps its level, so the jammer-to-signal ratio rises by the same amount our signal
% falls. Every antenna loses alike: to the detector and the policy the pass is path loss.
% The pattern is the half-wave dipole's, floored at the measured null.
% Output: results/overhead_pass.txt

H_M   = [16 50 100 300];               % [m] UAV altitudes (16 m: the lowest in the measurements, Khawaja et al.)
R0_KM = [0.5 1 2 5];                   % [km] cruise distance of the flight
NULL_DB = -30;                         % [dB] measured gain directly below a drone's dipole (Badi et al.)
dip = @(th) 10*log10(max((cos(pi/2 * sind(th)) ./ max(cosd(th), 1e-9)).^2, 10^(NULL_DB/10)));  % th: elevation [deg]

rep = {'=== OVERHEAD PASS: our signal relative to the cruise point of the flight ===', ...
    sprintf('Dipole pattern floored at %g dB directly below (Badi et al.); free space; the jammer keeps its level.', NULL_DB), ''};
hd = arrayfun(@(r) sprintf('R0 %g km', r), R0_KM, 'UniformOutput', false);
rep{end+1} = sprintf('%-10s %s', 'altitude', sprintf('%14s', hd{:}));
worst = -inf(numel(H_M), numel(R0_KM));
for i = 1:numel(H_M)
    h = H_M(i);
    d = linspace(0, 2000, 4001);                 % horizontal distance to the GCS [m]
    r = hypot(d, h); th = atand(h ./ max(d, eps));
    rel = @(R0) 20*log10(R0 ./ r) + dip(th) - dip(asind(min(h / R0, 1)));   % against the cruise point's own elevation
    row = cell(1, numel(R0_KM));
    for j = 1:numel(R0_KM)
        R0 = R0_KM(j) * 1e3;
        x = rel(R0);
        x = x(r <= R0);                              % the part of the pass inside the cruise distance
        worst(i, j) = -min(x);                       % largest drop below the cruise point [dB]
        row{j} = sprintf('%+.1f dB', min(x));
    end
    rep{end+1} = sprintf('%-10s %s', sprintf('%g m', h), sprintf('%14s', row{:})); %#ok<SAGROW>
end
rep{end+1} = '';
rep{end+1} = sprintf(['Largest drop of our signal below its cruise level during the pass: %.1f dB (the jammer-to-' ...
    'signal ratio rises by the same); a negative value means the pass never falls below the cruise level.'], max(worst(:)));
if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/overhead_pass.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('%s\n', rep{:});
