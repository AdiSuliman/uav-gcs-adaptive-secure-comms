function root = setup_paths()
%SETUP_PATHS  Put the project's code folders on the MATLAB path (legacy/ excluded)
%   and return the repository folder. Called by startup.m, main.m, run_stage.m, the
%   parallel workers and the tests.
code = fileparts(mfilename('fullpath'));
root = fileparts(code);
sub = {'', 'link', 'detection', 'decision', 'evaluation', 'gui', fullfile('gui', 'viz3d'), 'diagnostics'};
addpath(strjoin(cellfun(@(s) fullfile(code, s), sub, 'UniformOutput', false), pathsep));
end
