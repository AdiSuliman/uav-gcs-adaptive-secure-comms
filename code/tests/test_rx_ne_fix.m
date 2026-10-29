function tests = test_rx_ne_fix
%TEST_RX_NE_FIX  The delay-line receiver options of p.rx_ne_fix (build_threat_model.m):
%   field absent or 'off' leaves the receiver's script unchanged, 'log' adds print lines only,
%   every token changes only its own lines, the options touch the delay-line path only, and
%   every real receiver path writes its pilot error (sy(8)). Run from the repository root:
%   results = runtests('code/tests/test_rx_ne_fix.m')
%   The two text tests alone: runtests('code/tests/test_rx_ne_fix.m', 'ProcedureName',
%   {'test_off_is_unchanged', 'test_log_is_prints_only'})
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
verifyFalse(tc, isfield(p, 'rx_ne_fix'));            % params.mat never carries the field
s0 = rx_text(p);
p.rx_ne_fix = 'off';
verifyEqual(tc, rx_text(p), s0);
p.rx_ne_fix = '';
verifyEqual(tc, rx_text(p), s0);
verifyEmpty(tc, strfind(s0, 'flat_first'));
verifyEmpty(tc, strfind(s0, 'angle(cc) / DP'));
verifyEmpty(tc, strfind(s0, 'fprintf('));
verifyEmpty(tc, strfind(s0, 'rxd_'));
verifyNotEmpty(tc, strfind(s0, 'bf = sxy / max(sxx, 1e-30);'));
for m = {'nope', 'off+log', 'freq+freqa', 'freqa+freqf', 'noburst+burstn', 'log+'}
    p.rx_ne_fix = m{1};
    verifyError(tc, @() rx_text(p), ?MException, m{1});
end
bdclose('all');
end

function test_log_is_prints_only(tc)
% 'log' = off plus fprintf lines and the print-only functions appended last, which only
% fprintf lines call
p = dl_params();
s0 = splitlines(rx_text(p));
p.rx_ne_fix = 'log';
sl = splitlines(rx_text(p));
verifyEqual(tc, strip_prints(sl), s0);
pr = sl(startsWith(strtrim(sl), 'fprintf('));
for g = {'RXY ', 'RXP ', 'RXT ', 'RXB ', 'RXG ', 'RXF ', 'RXS '}
    verifyNotEmpty(tc, find(contains(pr, ['''' g{1}]), 1), g{1});
end
L = frame_layout(p);
verifyEqual(tc, nnz(contains(pr, '''RXB ')), numel(L.pil_center));
k = find(startsWith(sl, 'function v = rxd_'), 1);
verifyNotEmpty(tc, k);
body = sl(1:k - 1);
use = body(contains(body, 'rxd_'));
verifyNotEmpty(tc, use);
verifyTrue(tc, all(startsWith(strtrim(use), 'fprintf(')));
verifyEmpty(tc, find(contains(sl, 'RXH '), 1));       % the shadow receiver only with 'shadow'
bdclose('all');
end

function test_tokens_change_only_their_lines(tc)
p = dl_params();
s0 = splitlines(rx_text(p));
p.rx_ne_fix = 'freqa';
s = splitlines(rx_text(p));
verifyNotEmpty(tc, find(strcmp(s, '                        cc = cc + Ca(:, b)'' * Ca(:, b + 1);'), 1));
verifyNotEmpty(tc, find(contains(s, 'Ca(:, b) = Ca(:, b) + conj(eq_known(G, SK, KN, n, RP)) .* yx(n + XO, :).'''), 1));
verifyEqual(tc, numel(setdiff(s0, s)), 3);            % the call, the slope and the signature
verifyEmpty(tc, find(contains(s, 'fprintf('), 1));
p.rx_ne_fix = 'freqf';
s = splitlines(rx_text(p));
verifyNotEmpty(tc, find(strcmp(s, '                bf = -angle(gf) / (PC(2) - PC(1));'), 1));
verifyEqual(tc, setdiff(s0, s), {'                bf = sxy / max(sxx, 1e-30);'});
k = find(strcmp(s0, '            if rb(b) > 4 * mr'));
s0r = s0([1:k - 2, k + 4:end]);                      % s0 without the burst replacement loop
p.rx_ne_fix = 'noburst';
s = splitlines(rx_text(p));
verifyEqual(tc, s, s0r);
p.rx_ne_fix = 'burstn';
s = splitlines(rx_text(p));
verifyTrue(tc, is_subseq(s0r, s));
verifyEmpty(tc, find(strcmp(s, '            if rb(b) > 4 * mr'), 1));
verifyNotEmpty(tc, find(strcmp(s, '            if rn(b) > 4 * en(b)'), 1));
p.rx_ne_fix = 'hsel1';
s = splitlines(rx_text(p));
verifyTrue(tc, is_subseq(s0, s));
verifyEqual(tc, numel(s) - numel(s0), 4);
verifyNotEmpty(tc, find(strcmp(s, '        NHYP = 1;'), 1));
p.rx_ne_fix = 'deq0';
s = splitlines(rx_text(p));
verifyTrue(tc, is_subseq(s, s0));
verifyEqual(tc, numel(s0) - numel(s), 3);
verifyEmpty(tc, find(strcmp(s, '            deq = d + jb*SPS;'), 1));
p.rx_ne_fix = 'shadow';
s = splitlines(rx_text(p));
verifyTrue(tc, is_subseq(s0, s));
verifyNotEmpty(tc, find(contains(s, 'vsh = rxd_shadow('), 1));
verifyNotEmpty(tc, find(contains(s, '''RXH '), 1));
for m = {'freq+log', 'freqa+noburst+log', 'freqa+burstn+log', 'freqf+noburst+log', 'hsel1+log+shadow', ...
        'deq0+log', 'freqa+burstn+hsel1+deq0+shadow+log', 'both+log'}
    p.rx_ne_fix = m{1};
    s = splitlines(rx_text(p));
    verifyNotEmpty(tc, find(contains(s, '''RXS '), 1), m{1});
end
bdclose('all');
end

function test_log_output_identical(tc)
% the delay line with 'log' gives the outputs of 'off' and prints one RXS line per frame
p = dl_params();
[z0, s0, b0] = run_frames(p);
p.rx_ne_fix = 'log';
[z1, s1, b1, txt] = run_frames(p);
verifyEqual(tc, max(abs(z1(:) - z0(:))), 0);
verifyEqual(tc, max(abs(s1(:) - s0(:))), 0);
verifyEqual(tc, b1, b0);
verifyEqual(tc, numel(strfind(txt, 'RXS ')), size(s1, 2));
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
for path = {'flat', 'space-time'}
    p = dl_params();
    if strcmp(path{1}, 'flat'), p.tdl = false; p.tdl_random = false; else, p.rx_combiner = 'mmse'; end
    [z0, s0, b0] = run_frames(p);
    for m = {'both', 'freqa+burstn+hsel1+deq0+shadow+log', 'freqf+noburst+log'}
        p.rx_ne_fix = m{1};
        [z1, s1, b1, txt] = run_frames(p);
        verifyEqual(tc, max(abs(z1(:) - z0(:))), 0, [path{1} ' ' m{1}]);
        verifyEqual(tc, max(abs(s1(:) - s0(:))), 0, [path{1} ' ' m{1}]);
        verifyEqual(tc, b1, b0, [path{1} ' ' m{1}]);
        verifyEmpty(tc, strfind(txt, 'RXS '), [path{1} ' ' m{1}]);
    end
end
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
    if ddi > 0
        verifyTrue(tc, all(s(8, :) > 0), sprintf('space-time ddi %d', ddi));
    else
        % space-time path, unchanged here: st_dd returns error 0 without passes, so sy(8) = 0
        % and the frame always keeps the space-time output
        verifyEqual(tc, s(8, :), zeros(1, size(s, 2)), 'space-time ddi 0');
    end
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

function [z, s, b, txt] = run_frames(p)
% three frames at 12 dB; txt: what the simulation printed
mdl = 'UAV_GCS_Threat_Link';
evalc('build_threat_model(p)');
set_link_snr(mdl, 12 + 10*log10(p.bits_per_symbol) - 10*log10(p.sps), p);
link_seed(mdl, 11, 160);
txt = evalc('out = sim(mdl, ''StopTime'', num2str(3 * p.frame_duration));');
z = out.get('Rx_Z'); s = reshape(out.get('Rx_S'), 8, []); b = out.get('rx_bits_out');
close_system(mdl, 0);
end

function s = strip_prints(s)
% the script without its fprintf lines and without the print-only functions appended last
k = find(startsWith(s, 'function v = rxd_'), 1);
if ~isempty(k)
    s = s(1:k - 1);
end
s = s(~startsWith(strtrim(s), 'fprintf('));
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
