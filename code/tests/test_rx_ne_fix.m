function tests = test_rx_ne_fix
%TEST_RX_NE_FIX  The delay-line receiver options of p.rx_ne_fix (build_threat_model.m):
%   'off' leaves the receiver's script unchanged, the options touch the delay-line path only,
%   and every real receiver path writes its pilot error (sy(8)). Run from the repository root:
%   results = runtests('code/tests/test_rx_ne_fix.m')
tests = functiontests(localfunctions);
end

function setupOnce(tc)
tc.TestData.root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(tc.TestData.root, 'code'));
setup_paths;
tc.TestData.cwd = pwd;
tc.TestData.tmp = tempname; mkdir(tc.TestData.tmp); cd(tc.TestData.tmp);
tc.TestData.cfg = Simulink.fileGenControl('getConfig');
Simulink.fileGenControl('set', 'CacheFolder', tc.TestData.tmp, 'CodeGenFolder', tc.TestData.tmp);
end

function teardownOnce(tc)
Simulink.fileGenControl('setConfig', 'config', tc.TestData.cfg);
cd(tc.TestData.cwd);
end

function test_off_is_unchanged(tc)
p = dl_params();
s0 = rx_text(p);
p.rx_ne_fix = 'off';
verifyEqual(tc, rx_text(p), s0);
verifyEmpty(tc, strfind(s0, 'flat_first'));
verifyEmpty(tc, strfind(s0, 'angle(cc) / DP'));
verifyNotEmpty(tc, strfind(s0, 'bf = sxy / max(sxx, 1e-30);'));
p.rx_ne_fix = 'nope';
verifyError(tc, @() rx_text(p), ?MException);
bdclose('all');
end

function test_modes_change_only_their_lines(tc)
p = dl_params();
s0 = splitlines(rx_text(p));
p.rx_ne_fix = 'keep';
sk = splitlines(rx_text(p));
verifyTrue(tc, is_subseq(s0, sk));                  % 'keep' only adds lines
verifyNotEmpty(tc, find(contains(sk, 'sy(8) = min(ea, ee);'), 1));
verifyNotEmpty(tc, find(contains(sk, 'function za = flat_first('), 1));
p.rx_ne_fix = 'freq';
sf = splitlines(rx_text(p));
verifyEmpty(tc, find(strcmp(sf, '                bf = sxy / max(sxx, 1e-30);'), 1));
verifyNotEmpty(tc, find(strcmp(sf, '                bf = angle(cc) / DP;'), 1));
verifyEqual(tc, numel(setdiff(s0, sf)), 4);         % the four replaced lines
p.rx_ne_fix = 'both';
sb = splitlines(rx_text(p));
verifyNotEmpty(tc, find(contains(sb, 'flat_first('), 1));
verifyNotEmpty(tc, find(contains(sb, 'angle(cc) / DP'), 1));
bdclose('all');
end

function test_other_paths_bit_identical(tc)
% the flat path (NE == 1) and the space-time path (NT > 1) with every option on
p = dl_params(); p.tdl = false; p.tdl_random = false;
[z0, s0, b0] = run_frames(p);
p.rx_ne_fix = 'both';
[z1, s1, b1] = run_frames(p);
verifyEqual(tc, max(abs(z1(:) - z0(:))), 0);
verifyEqual(tc, max(abs(s1(:) - s0(:))), 0);
verifyEqual(tc, b1, b0);
p = dl_params(); p.rx_combiner = 'mmse';
[z0, s0, b0] = run_frames(p);
p.rx_ne_fix = 'both';
[z1, s1, b1] = run_frames(p);
verifyEqual(tc, max(abs(z1(:) - z0(:))), 0);
verifyEqual(tc, max(abs(s1(:) - s0(:))), 0);
verifyEqual(tc, b1, b0);
end

function test_pilot_error_on_every_path(tc)
% sy(8) on every real receiver path, decision-directed passes on or off; 'off' leaves the
% delay line's gap at rx_dd_iter = 0 as it was
for ddi = [0 2]
    for m = {'keep', 'freq', 'both'}
        p = dl_params(); p.rx_dd_iter = ddi; p.rx_ne_fix = m{1};
        [~, s] = run_frames(p);
        verifyTrue(tc, all(s(8, :) > 0 & isfinite(s(8, :))), sprintf('%s ddi %d', m{1}, ddi));
    end
    p = dl_params(); p.rx_dd_iter = ddi; p.tdl = false; p.tdl_random = false;
    [~, s] = run_frames(p);
    verifyTrue(tc, all(s(8, :) > 0), sprintf('flat ddi %d', ddi));
    p = dl_params(); p.rx_dd_iter = ddi; p.rx_combiner = 'mmse';
    [~, s] = run_frames(p);
    verifyTrue(tc, all(s(8, :) > 0), sprintf('space-time ddi %d', ddi));
end
p = dl_params(); p.rx_dd_iter = 0;
[~, s] = run_frames(p);
verifyEqual(tc, s(8, :), zeros(1, size(s, 2)));
end

%% helpers
function p = dl_params()
evalc('init_params');
p = load('params.mat').params;
p.quiet_build = true; p.active_threat = 'none'; p.seed = 11; p.rx_sync = 'real';
p.rx_combiner = 'mrc'; p.tdl = true;
end

function s = rx_text(p)
mdl = 'UAV_GCS_Threat_Link';
evalc('build_threat_model(p)');
ch = sfroot().find('-isa', 'Stateflow.EMChart', 'Path', [mdl '/Rx']);
s = ch.Script;
close_system(mdl, 0);
end

function [z, s, b] = run_frames(p)
mdl = 'UAV_GCS_Threat_Link';
evalc('build_threat_model(p)');
set_link_snr(mdl, 12 + 10*log10(p.bits_per_symbol) - 10*log10(p.sps), p);
link_seed(mdl, 11, 160);
out = sim(mdl, 'StopTime', num2str(3 * p.frame_duration));
z = out.get('Rx_Z'); s = reshape(out.get('Rx_S'), 8, []); b = out.get('rx_bits_out');
close_system(mdl, 0);
end

function t = is_subseq(a, b)
% true when the lines a appear in b in the same order
j = 1;
for i = 1:numel(b)
    if j <= numel(a) && strcmp(a{j}, b{i})
        j = j + 1;
    end
end
t = j > numel(a);
end
