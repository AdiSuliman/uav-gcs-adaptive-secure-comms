function r = project_root()
%PROJECT_ROOT  The repository folder (the parent of code/). Data, results, models and
%   logs are read and written relative to it.
r = fileparts(fileparts(mfilename('fullpath')));
end
