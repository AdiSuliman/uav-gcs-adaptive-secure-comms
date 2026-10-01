function link_seed(modelName, seed, fd)
%LINK_SEED  Seed every random source of the threat link and set its Doppler.
%   link_seed(modelName, seed)      seed only
%   link_seed(modelName, seed, fd)  seed and maximum Doppler shift [Hz]
%   Channel and threat blocks read 'Seed' and 'Doppler' at the start of each run;
%   the AWGN block gets seed+1, the bit source seed+2. With random interferer
%   directions (UserData of the 'AoA' block, set by build_threat_model.m) the
%   'AoA' block gets the directions of this seed (interferer_aoa.m), and with
%   random K-factors the 'Kfac' block gets this seed's K of our signal and of the
%   interferers (channel_k.m), and with random manoeuvres the 'Yaw' block gets this
%   seed's heading rate for the flight's speed (heading_rate.m); with a random receive
%   correlation the 'Corr' block gets this seed's (rx_correlation.m). No rebuild is needed.
set_param([modelName '/Seed'], 'Value', sprintf('%d', round(seed)));
if nargin >= 3
    set_param([modelName '/Doppler'], 'Value', sprintf('%.6f', fd));
end
ud = [];
if getSimulinkBlockHandle([modelName '/AoA']) ~= -1, ud = get_param([modelName '/AoA'], 'UserData'); end
if isstruct(ud) && isfield(ud, 'aoa_random') && ud.aoa_random
    th = interferer_aoa(seed, ud.aoa_range, numel(ud.aoa_fixed));
    set_param([modelName '/AoA'], 'Value', mat2str(th, 8));
end
uy = [];
if getSimulinkBlockHandle([modelName '/Yaw']) ~= -1, uy = get_param([modelName '/Yaw'], 'UserData'); end
if isstruct(uy) && isfield(uy, 'yaw_random') && uy.yaw_random
    fdv = str2double(get_param([modelName '/Doppler'], 'Value'));
    set_param([modelName '/Yaw'], 'Value', sprintf('%.8f', heading_rate(seed, fdv, uy)));
end
uc = [];
if getSimulinkBlockHandle([modelName '/Corr']) ~= -1, uc = get_param([modelName '/Corr'], 'UserData'); end
if isstruct(uc) && isfield(uc, 'corr_random') && uc.corr_random
    set_param([modelName '/Corr'], 'Value', sprintf('%.6f', rx_correlation(seed, uc.corr_range)));
end
uk = [];
if getSimulinkBlockHandle([modelName '/Kfac']) ~= -1, uk = get_param([modelName '/Kfac'], 'UserData'); end
if isstruct(uk) && isfield(uk, 'k_random') && uk.k_random
    set_param([modelName '/Kfac'], 'Value', mat2str(channel_k(seed, uk.k_range), 8));
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
            set_param(blks{b}, dp{j}, sprintf('%d', round(seed) + b));
        end
    end
end
set_param(modelName, 'Dirty', 'off');   % parameter changes only; nothing to save
end
