function dev_rx_script(q, name, out)
%DEV_RX_SCRIPT  The Rx block of the model built from q written as the function
%   <out>/rxlib/<name>.m, [bits, iqa, z, Hq, Rq, sy] = name(u, txbits), so the receiver
%   runs on dumped frames (dev_eval_rx.m) without the rest of the link.
if nargin < 3 || isempty(out), out = fullfile(tempdir, 'uav_gcs_dev'); end
mdl = 'UAV_GCS_Threat_Link';
q.quiet_build = true;
evalc('build_threat_model(q)');
ch = sfroot().find('-isa', 'Stateflow.EMChart', 'Path', [mdl '/Rx']);
s = regexprep(ch.Script, 'function \[bits, iqa, z, Hq, Rq, sy\] = fcn\(u, txbits\)', ...
    sprintf('function [bits, iqa, z, Hq, Rq, sy] = %s(u, txbits)', name), 'once');
close_system(mdl, 0);
d = fullfile(out, 'rxlib');
if ~exist(d, 'dir'), mkdir(d); end
fid = fopen(fullfile(d, [name '.m']), 'w'); fwrite(fid, s); fclose(fid);
addpath(d);
clear(name);
end
