function pool_worker_init(repo)
%POOL_WORKER_INIT  Prepare a parallel worker for Simulink runs (D59): its own
%   working and code-generation folder (no two workers share a model file or
%   compiled block code), the repository on the path, the notice of repeated
%   sim() calls silenced.
d = fullfile(tempdir, sprintf('uavgcs_worker_%d', feature('getpid')));
if ~isfolder(d), mkdir(d); end
addpath(repo);
cd(d);
Simulink.fileGenControl('set', 'CacheFolder', d, 'CodeGenFolder', d, 'createDir', true);
warning('off', 'Simulink:cgxe:LeakedJITEngine');
load_system('simulink');
end
