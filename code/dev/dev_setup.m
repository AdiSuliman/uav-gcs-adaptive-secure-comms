function p0 = dev_setup(tag, out, fixed)
%DEV_SETUP  Work folder and parameters of a development run (code/dev/).
%   p0 = dev_setup(tag, out, fixed): out the folder of every dev output (default
%   tempdir/uav_gcs_dev), its subfolder 'w_<tag>' the working folder with its own
%   params.mat, models/ and Simulink cache (the repository's data/, results/ and models/
%   are never written); fixed true: validate_phy's fixed geometry (no drawn directions,
%   attitude, correlation, K or GCS pointing; real synchronization; K 10 dB). Dev seeds
%   (7001-7360) are never validate_phy's or the tests' flights.
if nargin < 2 || isempty(out), out = fullfile(tempdir, 'uav_gcs_dev'); end
if nargin < 3, fixed = false; end
addpath(fullfile(fileparts(fileparts(mfilename('fullpath')))));
setup_paths; addpath(fileparts(mfilename('fullpath')));
d = fullfile(out, ['w_' tag]);
if ~exist(fullfile(d, 'models'), 'dir'), mkdir(fullfile(d, 'models')); end
cd(d);
Simulink.fileGenControl('set', 'CacheFolder', d, 'CodeGenFolder', d);
warning('off', 'Simulink:cgxe:LeakedJITEngine');
evalc('init_params'); p0 = load('params.mat').params;
p0.quiet_build = true;
if fixed
    p0.int_aoa_random = false; p0.yaw_random = false; p0.corr_random = false; p0.k_random = false;
    p0.gcs_tracked = false; p0.gcs_aoa_random = false; p0.body_random = false;
    p0.rx_sync = 'real'; p0.tdl_random = false;
    p0.rician_k = 10; p0.int_rician_k = 10;
end
end
