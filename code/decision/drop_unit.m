function u = drop_unit(mode)
%DROP_UNIT  Unit of the drop alarm's threshold (PP.drop_db) for the monitor's alarm mode:
%   dB for the 3-cycle median window ('class_drop'), dB^2 for the window-limited CUSUM
%   ('class_cusum', drop_cusum.m).
u = 'dB'; if strcmp(mode, 'class_cusum'), u = 'dB^2'; end
end
