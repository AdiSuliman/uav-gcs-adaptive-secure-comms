function [p, sevTxt, fd_hz, comps] = console_scenario(p0, sev, threat, sevLevel, v_kmh)
%CONSOLE_SCENARIO  Link parameters of one operator-console scenario (demo_gui.m).
%   threat    a single threat, 'none', or a combination 'a+b[+c]' (decision_config.m
%             C.combos)
%   sev       severity axes per threat (dataset_levels.m): sev.(name).param, .levels
%   sevLevel  0 = every component at its nominal value (init_params.m), k = every
%             component at level k of its own axis
%   v_kmh     UAV speed -> channel Doppler fd = v*fc/c
%   comps     the component threats: a detection of any of them is correct, as the
%             evaluation counts a combined threat (edge_map.m, DET)
fd_hz = (v_kmh/3.6) * p0.carrier_freq / p0.c_light;
p = p0;
p.active_threat = threat;
comps = strsplit(threat, '+');
sevTxt = 'nominal';
if sevLevel > 0 && ~strcmp(threat, 'none')
    txt = cell(1, numel(comps));
    for i = 1:numel(comps)
        sv = sev.(comps{i});
        p.(sv.param) = sv.levels(sevLevel);
        txt{i} = sprintf('%s=%g', sv.param, sv.levels(sevLevel));
    end
    sevTxt = sprintf('L%d (%s)', sevLevel, strjoin(txt, ', '));
end
p.v_kmh = v_kmh; p.v = v_kmh/3.6; p.fd_max = fd_hz;
p.quiet_build = true;                      % build the Simulink model without opening its window
p.gcs_aoa_random = false;                  % the GCS at broadside, as the 3D view draws it
p.jam_timing_random = false;               % the sweeper on our channel in every frame of the run
end
