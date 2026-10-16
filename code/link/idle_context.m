function ctx = idle_context(mdl)
%IDLE_CONTEXT  The values the threat link's blocks held for the run just simulated, as
%   idle_rssi.m needs them: the seed base ('Seed'), the Doppler ('Doppler'), the Level gain
%   ('Level'), the interferer directions ('AoA'), the K-factors ('Kfac'), the heading rate
%   ('Yaw'), the receive correlation ('Corr'), the attitude ('Att'), the gated jammers'
%   timing ('Gate'), the delay line's amplitudes ('Tdl'), the in-band cap's reference
%   ('Cap') and the calibration errors ('Cal'): link_seed.m and set_link_snr.m set them, so
%   they are exactly the run's. [] when the model holds no such block.
ctx = [];
try
    v = @(b) str2num(get_param([mdl '/' b], 'Value')); %#ok<ST2NM>
    ctx = struct('seed', v('Seed'), 'fd', v('Doppler'), 'lev', str2double(get_param([mdl '/Level'], 'Gain')), ...
        'aoa', v('AoA'), 'kfac', v('Kfac'), 'yaw', v('Yaw'), 'rho', v('Corr'), 'att', v('Att'), 'gate', v('Gate'), ...
        'tdl', v('Tdl'), 'cap', v('Cap'), 'cal', v('Cal'));
catch
    ctx = [];
end
end
