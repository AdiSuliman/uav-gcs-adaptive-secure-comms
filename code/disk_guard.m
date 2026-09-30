function disk_guard(varargin)
%DISK_GUARD  Keep Simulink's temporary data and the free disk space in bounds.
%   Every sim() records its logged data in the Simulation Data Inspector
%   repository, a .dmr file in tempdir per MATLAB process; it is deleted when
%   MATLAB closes, but it grows during a long run and stays behind when a process
%   is killed (up to ~24 GB per parallel worker was found). The pipeline reads
%   the outputs right after each run, so the repository is not needed.
%   disk_guard('init')  per process: no automatic archive of old runs
%   disk_guard          after a run: empty the repository; stop the pipeline when
%                       the drive of tempdir has less than MIN_FREE_GB free, or
%                       when this machine's .dmr files exceed MAX_DMR_GB
MIN_FREE_GB = 200;
MAX_DMR_GB  = 2;
if nargin && strcmp(varargin{1}, 'init')
    load_system('simulink');                                % the SDI calls need Simulink loaded (parallel workers)
    Simulink.sdi.setAutoArchiveMode(false);
    Simulink.sdi.setArchiveRunLimit(0);
end
Simulink.sdi.clear;
persistent last
if ~isempty(last) && toc(last) < 20, return; end         % the disk checks at most every 20 s
last = tic;
free_gb = java.io.File(tempdir).getUsableSpace() / 1e9;
d = dir(fullfile(tempdir, '*.dmr'));
dmr_gb = sum([d.bytes]) / 1e9;
if free_gb < MIN_FREE_GB
    error('disk_guard:space', 'Stopped: %.0f GB free on the drive of %s, below %d GB.', free_gb, tempdir, MIN_FREE_GB);
end
if dmr_gb > MAX_DMR_GB
    error('disk_guard:dmr', 'Stopped: %.1f GB of Simulink .dmr files in %s (limit %d GB).', dmr_gb, tempdir, MAX_DMR_GB);
end
end
