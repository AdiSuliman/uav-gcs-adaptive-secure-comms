function link_seed(modelName, seed, fd)
%LINK_SEED  Seed every random source of the threat link and set its Doppler (D41).
%   link_seed(modelName, seed)      seed only
%   link_seed(modelName, seed, fd)  seed and maximum Doppler shift [Hz]
%   Channel and threat blocks read 'Seed' and 'Doppler' at the start of each run;
%   the AWGN block gets seed+1, the bit source seed+2. With random interferer
%   directions (UserData of the 'AoA' block, set by build_threat_model.m) the
%   'AoA' block gets the directions of this seed (interferer_aoa.m). No rebuild
%   is needed.
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
