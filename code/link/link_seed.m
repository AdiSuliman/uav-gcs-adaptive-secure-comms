function d = link_seed(modelName, seed, fd, geo)
%LINK_SEED  Seed every random source of the threat link and set its Doppler and flight draws.
%   link_seed(modelName, seed)               seed only
%   link_seed(modelName, seed, fd)           seed and maximum Doppler shift [Hz]
%   d = link_seed(modelName, seed, fd, geo)  also the GCS at the distance of geo.ebno [dB],
%                                            with geo.alt_m, geo.k_sig_db, geo.aoa1_deg and
%                                            geo.rho replacing the seed's altitude, K, first
%                                            interferer direction and correlation when finite
%   The 'Seed' block gets the flight's first stream seed, seed_base(seed): the channel
%   seeds its stream there and the threat 7 above it; the AWGN block gets 1 above, the bit
%   source 2 above (seed_stream.m). Channel and threat blocks read 'Seed' and 'Doppler' at
%   the start of each run. The flight's draws (flight_draws.m, under the draw switches and
%   ranges the model was built with: UserData of its Constant blocks, build_threat_model.m)
%   go to the blocks whose draw is on: interferer directions to 'AoA', K-factors of our
%   signal and of the interferers to 'Kfac', heading rate to 'Yaw', receive correlation to
%   'Corr'. 'GCS' gets the amplitude of our signal: the tracker's pointing loss and the UAV
%   antenna's gain toward the GCS (0 dB without geo.ebno). No rebuild is needed.
%   d: the flight's draws (flight_draws.m).
b0 = seed_base(seed);
set_param([modelName '/Seed'], 'Value', sprintf('%d', b0));
if nargin >= 3 && ~isempty(fd)
    set_param([modelName '/Doppler'], 'Value', sprintf('%.6f', fd));
else
    fd = str2double(get_param([modelName '/Doppler'], 'Value'));
end
if nargin < 4 || isempty(geo), geo = struct(); end
p = block_params(modelName);
d = flight_draws(seed, fd, p, geo);
if getf(p, 'int_aoa_random', false)
    set_param([modelName '/AoA'], 'Value', mat2str(d.aoa, 8));
end
if getf(p, 'k_random', false) || isfinite(getf(geo, 'k_sig_db', NaN))
    set_param([modelName '/Kfac'], 'Value', mat2str([d.k_sig d.k_int], 8));
end
if getf(p, 'yaw_random', false)
    set_param([modelName '/Yaw'], 'Value', sprintf('%.8f', d.yaw));
end
if getf(p, 'corr_random', false)
    set_param([modelName '/Corr'], 'Value', sprintf('%.6f', d.rho));
end
if getSimulinkBlockHandle([modelName '/GCS']) ~= -1
    set_param([modelName '/GCS'], 'Value', sprintf('%.8f', d.gcs_amp));
end
blks = {[modelName '/AWGN'], [modelName '/BitSource']};
for b = 1:numel(blks)
    dp = fieldnames(get_param(blks{b}, 'DialogParameters'));
    for j = 1:numel(dp)
        if strcmpi(dp{j}, 'RandomStream')
            try, set_param(blks{b}, dp{j}, 'mt19937ar with seed'); catch, end
        end
        if strcmpi(dp{j}, 'SeedSource')
            try, set_param(blks{b}, dp{j}, 'Parameter'); catch, end
        end
    end
    for j = 1:numel(dp)
        if strcmpi(dp{j}, 'seed')
            set_param(blks{b}, dp{j}, sprintf('%d', b0 + b));
        end
    end
end
set_param(modelName, 'Dirty', 'off');   % parameter changes only; nothing to save
end

function p = block_params(modelName)
% Draw switches, ranges and fixed values of the model (UserData of its Constant blocks) in one struct.
p = struct();
for b = {'AoA', 'Kfac', 'Yaw', 'Corr', 'GCS'}
    blk = [modelName '/' b{1}];
    if getSimulinkBlockHandle(blk) == -1, continue; end
    u = get_param(blk, 'UserData');
    if ~isstruct(u), continue; end
    f = fieldnames(u);
    for i = 1:numel(f), p.(f{i}) = u.(f{i}); end
end
end

function v = getf(s, name, default)
if isfield(s, name) && ~isempty(s.(name)), v = s.(name); else, v = default; end
end
