function tests = test_rx_ne_fix
%TEST_RX_NE_FIX  The delay-line receiver options of p.rx_ne_fix (build_threat_model.m):
%   field absent or 'off' leaves the receiver's script unchanged, 'log' adds print lines only,
%   every token changes only its own lines, the options touch the delay-line path only, and
%   every real receiver path writes its pilot error (sy(8)); the twin tokens wire the own
%   component to a third receiver input only when set. Run from the repository root:
%   results = runtests('code/tests/test_rx_ne_fix.m')
%   The two text tests alone: runtests('code/tests/test_rx_ne_fix.m', 'ProcedureName',
%   {'test_off_is_unchanged', 'test_log_is_prints_only'})
%   The twin tests: 'ProcedureName', {'test_off_is_unchanged', 'test_log_is_prints_only',
%   'test_twin_tokens_change_only_their_lines', 'test_twin_wiring',
%   'test_twin_other_paths_bit_identical', 'test_twin_runs_on_delay_line'}
%   The per-block twin tests: 'ProcedureName', {'test_twinb_tokens_refused',
%   'test_twinb_tokens_change_only_their_lines', 'test_twinb_wiring',
%   'test_twinb_other_paths_bit_identical', 'test_twinb_runs_on_delay_line',
%   'test_twinb_profiles_at_receiver_level'}; the last flies three validation flights of the
%   link-floor folder (RX_LINK_FLOOR, else the worktree beside this one)
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
for m = {'nope', 'off+log', 'freq+freqa', 'freqa+freqf', 'noburst+burstn', 'log+', 'twin', 'twinf', 'twing'}
    p.rx_ne_fix = m{1};
    verifyError(tc, @() rx_text(p), ?MException, m{1});   % the twin tokens need the own component
end
p.own_out = true;
p.rx_ne_fix = 'off';
verifyEqual(tc, rx_text(p), s0);
for m = {'twinf+freqa', 'twin+freq', 'twinf+freqf', 'twin+twinf+freqa'}
    p.rx_ne_fix = m{1};
    verifyError(tc, @() rx_text(p), ?MException, m{1});
end
p.rx_ne_fix = 'twin+log'; p.rx_release = true;
verifyError(tc, @() rx_text(p), ?MException);          % a release build refuses diagnostic tokens
p.rx_ne_fix = 'freqa+burstn';
verifyNotEmpty(tc, rx_text(p));                         % adoptable tokens pass it
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

function test_twin_tokens_change_only_their_lines(tc)
% each twin token: the twin's input, filter and copies of the frequency and whitening (common
% to the three), and its own step: 'twinf' the frequency line and twin_freq, 'twing' the
% template line, 'twin' both; 'log' with a twin token adds prints only
p = dl_params(); p.own_out = true;
s0 = splitlines(rx_text(p));
sig0 = 'function [bits, iqa, z, Hq, Rq, sy] = fcn(u, txbits)'; per0 = 'persistent rxf';
sig1 = 'function [bits, iqa, z, Hq, Rq, sy] = fcn(u, txbits, ut)'; per1 = 'persistent rxf rxt';
bf0 = '                bf = sxy / max(sxx, 1e-30);';
kf = find(strcmp(s0, 'if isempty(rxf)'));
W = {'% the twin: our own component alone, through its own receive filter'
    'if isempty(rxt)'
    strrep(s0{kf + 1}, 'rxf = ', 'rxt = ')
    'end'
    'rft = rxt(ut);'
    'rwt = complex(zeros(Ns, NR)); rwst = complex(zeros(Ns, NR));'
    '        rwht = complex(zeros(Ns, NR));'
    '        rwht(:, :) = rft;'
    '                rwht(m, :) = rft(m, :) * Wh.'';'
    '            rwst(:, :) = rwht;'
    '    % the twin: the same frequency and whitening'
    '    for a = 1:NR'
    '        rft(:, a) = rft(:, a) .* ph;'
    '    end'
    '    if hsel == 3'
    '        rwt(:, :) = rwst;'
    '        for a = 1:NR'
    '            rwt(:, a) = rwt(:, a) .* ph;'
    '        end'
    '    else'
    '        rwt(:, :) = rft * W.'';'
    '    end'
    '        yxt = complex(zeros(NS + 2*XO, NR)); ywxt = complex(zeros(NS + 2*XO, NR));'
    '                yxt(k + XO, :) = rft(base + deq + tk + 1, :) * phk;'
    '                ywxt(k + XO, :) = rwt(base + deq + tk + 1, :) * phk;'
    '                    yxt(k + XO, :) = yxt(k + XO, :) * exp(-1j * bf * (k - 1));'
    '                    ywxt(k + XO, :) = ywxt(k + XO, :) * exp(-1j * bf * (k - 1));'
    sig1
    per1};
F = {'                % the twin''s frequency: every antenna''s products of pilot blocks one spacing apart'
    '                bf = twin_freq(ywxt, PRE, SK, KN, IDXP, PC, NRK, RP, RQ, XO, PB);'};
G = {'        % the twin''s training gives the lag model; s2 stays the samples'' own'
    '        Gt = eq_train(yxt, PRE, SK, KN, IDXP, PC, NRK, RP, RQ, XO, PB);'};
s0w = s0; s0w{strcmp(s0w, sig0)} = sig1; s0w{strcmp(s0w, per0)} = per1;
p.rx_ne_fix = 'twing';
sg = splitlines(rx_text(p));
verifyTrue(tc, is_subseq(s0w, sg));
verifyEqual(tc, msdiff(s0, sg), sort({sig0; per0}));
verifyEqual(tc, msdiff(sg, s0), sort([W; G]));
p.rx_ne_fix = 'twinf';
sf = splitlines(rx_text(p));
k = find(strcmp(sf, 'function bf = twin_freq(yx, PRE, SK, KN, IDXP, PC, NRK, RP, RQ, XO, PB)'));
verifyNumElements(tc, k, 1);
verifyTrue(tc, strcmp(sf{k - 1}, '') && strcmp(sf{end - 1}, 'end') && strcmp(sf{end - 2}, 'bf = angle(cc) / DP;'));
verifyEqual(tc, msdiff(s0, sf), sort({sig0; per0; bf0}));
verifyEqual(tc, msdiff(sf(1:k - 2), s0), sort([W; F]));
s0wf = s0w(~strcmp(s0w, bf0));
verifyTrue(tc, is_subseq(s0wf, sf(1:k - 1)));
p.rx_ne_fix = 'twin';
st = splitlines(rx_text(p));
kt = find(strcmp(st, 'function bf = twin_freq(yx, PRE, SK, KN, IDXP, PC, NRK, RP, RQ, XO, PB)'));
verifyEqual(tc, st(kt:end), sf(k:end));
verifyEqual(tc, msdiff(s0, st), sort({sig0; per0; bf0}));
verifyEqual(tc, msdiff(st(1:kt - 2), s0), sort([W; F; G]));
verifyTrue(tc, is_subseq(s0wf, st(1:kt - 1)));
for s = {sg, sf, st}
    verifyEmpty(tc, find(contains(s{1}, 'fprintf('), 1));
end
% with 'log': prints only, and RXL per block (0: the training) and antenna
p.rx_ne_fix = 'twin+log';
sl = splitlines(rx_text(p));
verifyEqual(tc, strip_prints(sl), st);                 % twin_freq sits before the print-only functions
L = frame_layout(p);
verifyEqual(tc, nnz(startsWith(strtrim(sl), 'fprintf(''RXL ')), (numel(L.pil_center) + 1) * p.n_rx);
kr = find(startsWith(sl, 'function v = rxd_'), 1);
body = sl(1:kr - 1);
verifyTrue(tc, all(startsWith(strtrim(body(contains(body, 'rxd_'))), 'fprintf(')));
verifyNotEmpty(tc, find(strcmp(sl, 'function v = rxd_true(k, b, a, yxt, Gt, SK, IDXD, IDXP, PB, NRK, RP, RQ, XO, NPRE, txbits)'), 1));
% the template print follows the template the receiver uses
kg = find(strcmp(sl, G{2}));
verifyTrue(tc, startsWith(strtrim(sl{kg + 1}), 'fprintf(''RXT '));
bdclose('all');
end

function test_twin_wiring(tc)
% field absent or 'off': no twin input; a twin token: output 4 of the threat block through
% 'LevelTw' (the gain of 'Level') to the receiver's third input
mdl = 'UAV_GCS_Threat_Link';
p = dl_params(); p.own_out = true;
for m = {'', 'off', 'log', 'freqa+burstn'}
    if isempty(m{1}), q = p; else, q = p; q.rx_ne_fix = m{1}; end
    evalc('build_threat_model(q)');
    verifyEqual(tc, getSimulinkBlockHandle([mdl '/LevelTw']), -1, m{1});
    pt = get_param([mdl '/Rx'], 'Ports');
    verifyEqual(tc, pt(1), 2, m{1});
    close_system(mdl, 0);
end
for m = {'twin', 'twinf', 'twing', 'twin+log'}
    q = p; q.rx_ne_fix = m{1};
    evalc('build_threat_model(q)');
    verifyNotEqual(tc, getSimulinkBlockHandle([mdl '/LevelTw']), -1, m{1});
    verifyEqual(tc, get_param([mdl '/LevelTw'], 'Gain'), get_param([mdl '/Level'], 'Gain'), m{1});
    pt = get_param([mdl '/Rx'], 'Ports');
    verifyEqual(tc, pt(1), 3, m{1});
    ph = get_param([mdl '/Rx'], 'PortHandles');
    ln = get_param(ph.Inport(3), 'Line');
    verifyEqual(tc, get_param(get_param(ln, 'SrcBlockHandle'), 'Name'), 'LevelTw', m{1});
    ph = get_param([mdl '/LevelTw'], 'PortHandles');
    ln = get_param(ph.Inport(1), 'Line');
    verifyEqual(tc, get_param(get_param(ln, 'SrcBlockHandle'), 'Name'), 'Threat', m{1});
    verifyEqual(tc, get_param(get_param(ln, 'SrcPortHandle'), 'PortNumber'), 4, m{1});
    close_system(mdl, 0);
end
end

function test_twin_other_paths_bit_identical(tc)
% the flat path (NE == 1) and the space-time path (NT > 1) with every twin token on
for path = {'flat', 'space-time'}
    p = dl_params(); p.own_out = true;
    if strcmp(path{1}, 'flat'), p.tdl = false; p.tdl_random = false; else, p.rx_combiner = 'mmse'; end
    [z0, s0, b0] = run_frames(p);
    for m = {'twin', 'twinf+log', 'twing+log', 'twin+log', 'twing+freqa+burstn+hsel1+deq0+log'}
        p.rx_ne_fix = m{1};
        [z1, s1, b1, txt] = run_frames(p);
        verifyEqual(tc, max(abs(z1(:) - z0(:))), 0, [path{1} ' ' m{1}]);
        verifyEqual(tc, max(abs(s1(:) - s0(:))), 0, [path{1} ' ' m{1}]);
        verifyEqual(tc, b1, b0, [path{1} ' ' m{1}]);
        verifyEmpty(tc, strfind(txt, 'RXS '), [path{1} ' ' m{1}]);
        verifyEmpty(tc, strfind(txt, 'RXL '), [path{1} ' ' m{1}]);
    end
end
end

function test_twin_runs_on_delay_line(tc)
% the delay line with 'twin+log': one RXS line and (NB + 1) NR RXL lines per frame; on the
% training the twin's own template is its lag profile (the multiple near 1); with
% 'twinf+log' the template is the main samples', so the multiple on the training checks the
% twin's level (|c|^2), timing and rotations (angle c) against the main samples
p = dl_params(); p.own_out = true; p.rx_ne_fix = 'twin+log';
[z, s, ~, txt] = run_frames(p);
nf = size(s, 2);
verifyTrue(tc, all(isfinite(z(:))));
verifyEqual(tc, numel(strfind(txt, 'RXS ')), nf);
L = frame_layout(p); NB = numel(L.pil_center);
ln = splitlines(txt);
verifyEqual(tc, nnz(startsWith(strtrim(ln), 'RXL ')), nf * (NB + 1) * p.n_rx);
t0 = rxl_training(txt);
verifyLessThan(tc, median(abs(t0(:, 3))), 1);             % |c|^2 [dB] on the training
verifyLessThan(tc, median(t0(:, 5)), -10);                % the share the template leaves [dB]
p.rx_ne_fix = 'twinf+log';
[z, s, ~, txt] = run_frames(p);
nf = size(s, 2);
verifyTrue(tc, all(isfinite(z(:))));
t0 = rxl_training(txt);
verifyEqual(tc, size(t0, 1), nf * p.n_rx, 'twinf+log');
verifyLessThan(tc, median(abs(t0(:, 3))), 1, 'twinf+log');     % |c|^2 [dB]
verifyLessThan(tc, median(abs(t0(:, 4))), 0.2, 'twinf+log');   % angle(c) [rad]
end

function test_twinb_tokens_refused(tc)
% 'twinb' and 'eqt' need the own component; 'twinb' combines only with 'twinf', 'eqt' and
% 'log', 'eqt' only with 'twinb'; every build prints its options and its diagnostic-only
% tokens, and a release build refuses them
p = dl_params();
s0 = rx_text(p);
for m = {'twinb', 'twinb+log', 'twinb+eqt', 'twinb+twinf+log'}
    p.rx_ne_fix = m{1};
    verifyError(tc, @() rx_text(p), ?MException, m{1});   % without the own component
end
p.own_out = true;
p.rx_ne_fix = 'off';
verifyEqual(tc, rx_text(p), s0);
for m = {'eqt', 'eqt+log', 'eqt+twinf', 'eqt+twing', 'twinb+twing', 'twinb+twin', 'twinb+freq', 'twinb+freqa', ...
        'twinb+freqf', 'twinb+keep', 'twinb+both', 'twinb+noburst', 'twinb+burstn', 'twinb+hsel1', 'twinb+deq0', ...
        'twinb+shadow', 'twinb+eqt+freqa', 'twinb+off', 'twinb+'}
    p.rx_ne_fix = m{1};
    verifyError(tc, @() rx_text(p), ?MException, m{1});
end
p.rx_ne_fix = 'twinb+eqt+log';
txt = evalc('build_threat_model(p)');
close_system('UAV_GCS_Threat_Link', 0);
verifyNotEmpty(tc, strfind(txt, 'Rx NE>1 options: twinb+eqt+log'));
verifyNotEmpty(tc, strfind(txt, 'Rx NE>1 diagnostic-only: twinb+eqt+log'));
p.rx_release = true;
for m = {'twinb', 'twinb+eqt', 'twinb+twinf+log', 'twinb+eqt+log'}
    p.rx_ne_fix = m{1};
    verifyError(tc, @() rx_text(p), ?MException, m{1});   % a release build refuses diagnostic tokens
end
bdclose('all');
end

function test_twinb_tokens_change_only_their_lines(tc)
% 'twinb': the twin's input, filter and copies of the frequency and whitening (the lines of
% every twin token), the twin's block profiles (twin_blocks) in the MRC and every block's
% equalizer for the data symbols of its segment; 'eqt' keeps the training's equalizer; 'twinf'
% adds its frequency line and twin_freq; 'log' adds prints only, RXL per block and antenna and
% RXA per pilot block among them
p = dl_params(); p.own_out = true;
s0 = splitlines(rx_text(p));
sig0 = 'function [bits, iqa, z, Hq, Rq, sy] = fcn(u, txbits)'; per0 = 'persistent rxf';
sig1 = 'function [bits, iqa, z, Hq, Rq, sy] = fcn(u, txbits, ut)'; per1 = 'persistent rxf rxt';
bf0 = '                bf = sxy / max(sxx, 1e-30);';
rr0 = '                rr(k + E0) = rr(k + E0) + (gk .* Gt(:, l))'' * yx(k + l - 1 - RP + XO, :).'';';
z0 = '            z(m) = fe'' * rr(IDXD(m) : IDXD(m) + NE - 1);';
G = {'        % the twin''s training gives the lag model; s2 stays the samples'' own'
    '        Gt = eq_train(yxt, PRE, SK, KN, IDXP, PC, NRK, RP, RQ, XO, PB);'};
F = {'                % the twin''s frequency: every antenna''s products of pilot blocks one spacing apart'
    '                bf = twin_freq(ywxt, PRE, SK, KN, IDXP, PC, NRK, RP, RQ, XO, PB);'};
B = {'        % the twin''s lag profile at the training and at every pilot block, every symbol known;'
    '        % every MRC output symbol takes the profile of the nearest block centre (ties: the earlier)'
    '        Gb = twin_blocks(yxt, SK, IDXD, IDXP, PC, PB, NRK, RP, RQ, XO, NPRE, txbits);'
    '            [~, ib] = min(abs(kc - tq));'
    '                rr(k + E0) = rr(k + E0) + Gb(:, l, ib)'' * yx(k + l - 1 - RP + XO, :).'';'};
E = {'        % the equalizer of every block''s profile, for the data symbols of its segment'
    '        Fb = complex(zeros(NE, NB + 1));'
    '        for b = 1:NB + 1'
    '            Fb(:, b) = le_taps(Gb(:, :, b), s2, NE);'
    '        end'
    '            [~, ib] = min(abs(IDXD(m) - tq));'
    '            z(m) = Fb(:, ib)'' * rr(IDXD(m) : IDXD(m) + NE - 1);'};
fb = 'function G = twin_blocks(yxt, SK, IDXD, IDXP, PC, PB, NRK, RP, RQ, XO, NPRE, txbits)';
ff = 'function bf = twin_freq(yx, PRE, SK, KN, IDXP, PC, NRK, RP, RQ, XO, PB)';
p.rx_ne_fix = 'twing';
W = msdiff(msdiff(splitlines(rx_text(p)), s0), G);   % the lines every twin token adds
verifyNotEmpty(tc, find(strcmp(W, sig1), 1));
s0w = s0; s0w{strcmp(s0w, sig0)} = sig1; s0w{strcmp(s0w, per0)} = per1;
% 'twinb+eqt': the block profiles in the MRC only
p.rx_ne_fix = 'twinb+eqt';
se = splitlines(rx_text(p));
k = find(strcmp(se, fb));
verifyNumElements(tc, k, 1);
verifyTrue(tc, strcmp(se{k - 1}, '') && strcmp(se{end - 1}, 'end') && strcmp(se{end - 2}, 'end'));
verifyEqual(tc, msdiff(s0, se), sort({sig0; per0; rr0}));
verifyEqual(tc, msdiff(se(1:k - 2), s0), sort([W; B]));
verifyTrue(tc, is_subseq(s0w(~strcmp(s0w, rr0)), se(1:k - 1)));
TB = se(k:end);
% 'twinb': and every block's equalizer
p.rx_ne_fix = 'twinb';
sb = splitlines(rx_text(p));
kb = find(strcmp(sb, fb));
verifyNumElements(tc, kb, 1);
verifyEqual(tc, sb(kb:end), TB);
verifyEqual(tc, msdiff(s0, sb), sort({sig0; per0; rr0; z0}));
verifyEqual(tc, msdiff(sb(1:kb - 2), s0), sort([W; B; E]));
verifyTrue(tc, is_subseq(s0w(~ismember(s0w, {rr0; z0})), sb(1:kb - 1)));
% 'twinb+twinf': and the twin's frequency
p.rx_ne_fix = 'twinb+twinf';
sf = splitlines(rx_text(p));
kf = find(strcmp(sf, ff)); kb = find(strcmp(sf, fb));
verifyNumElements(tc, kf, 1);
verifyNumElements(tc, kb, 1);
verifyLessThan(tc, kf, kb);
verifyEqual(tc, sf(kb:end), TB);
verifyEqual(tc, msdiff(s0, sf), sort({sig0; per0; bf0; rr0; z0}));
verifyEqual(tc, msdiff(sf(1:kf - 2), s0), sort([W; F; B; E]));
verifyTrue(tc, is_subseq(s0w(~ismember(s0w, {bf0; rr0; z0})), sf(1:kf - 1)));
for s = {se, sb, sf}
    verifyEmpty(tc, find(contains(s{1}, 'fprintf('), 1));
end
% with 'log': prints only; RXL per block (0: the training) and antenna, RXA per pilot block
L = frame_layout(p); NB = numel(L.pil_center);
for m = {'twinb+eqt', 'twinb', 'twinb+twinf'; se, sb, sf}
    p.rx_ne_fix = [m{1} '+log'];
    sl = splitlines(rx_text(p));
    verifyEqual(tc, strip_prints(sl), m{2}, m{1});
    pr = strtrim(sl(startsWith(strtrim(sl), 'fprintf(')));
    verifyEqual(tc, nnz(startsWith(pr, 'fprintf(''RXL ')), (NB + 1) * p.n_rx, m{1});
    verifyEqual(tc, nnz(startsWith(pr, 'fprintf(''RXA ')), NB, m{1});
    verifyNotEmpty(tc, find(startsWith(pr, 'fprintf(''RXS '), 1), m{1});
    kr = find(startsWith(sl, 'function v = rxd_'), 1);
    body = sl(1:kr - 1);
    verifyTrue(tc, all(startsWith(strtrim(body(contains(body, 'rxd_'))), 'fprintf(')), m{1});
end
bdclose('all');
end

function test_twinb_wiring(tc)
% every 'twinb' arm: output 4 of the threat block through 'LevelTw' (the gain of 'Level') to
% the receiver's third input
mdl = 'UAV_GCS_Threat_Link';
p = dl_params(); p.own_out = true;
for m = {'twinb', 'twinb+eqt+log', 'twinb+twinf+log'}
    q = p; q.rx_ne_fix = m{1};
    evalc('build_threat_model(q)');
    verifyNotEqual(tc, getSimulinkBlockHandle([mdl '/LevelTw']), -1, m{1});
    verifyEqual(tc, get_param([mdl '/LevelTw'], 'Gain'), get_param([mdl '/Level'], 'Gain'), m{1});
    pt = get_param([mdl '/Rx'], 'Ports');
    verifyEqual(tc, pt(1), 3, m{1});
    ph = get_param([mdl '/Rx'], 'PortHandles');
    ln = get_param(ph.Inport(3), 'Line');
    verifyEqual(tc, get_param(get_param(ln, 'SrcBlockHandle'), 'Name'), 'LevelTw', m{1});
    ph = get_param([mdl '/LevelTw'], 'PortHandles');
    ln = get_param(ph.Inport(1), 'Line');
    verifyEqual(tc, get_param(get_param(ln, 'SrcBlockHandle'), 'Name'), 'Threat', m{1});
    verifyEqual(tc, get_param(get_param(ln, 'SrcPortHandle'), 'PortNumber'), 4, m{1});
    close_system(mdl, 0);
end
end

function test_twinb_other_paths_bit_identical(tc)
% the flat path (NE == 1) and the space-time path (NT > 1) with 'twinb+twinf' and 'twinb+eqt'
% (and their prints)
for path = {'flat', 'space-time'}
    p = dl_params(); p.own_out = true;
    if strcmp(path{1}, 'flat'), p.tdl = false; p.tdl_random = false; else, p.rx_combiner = 'mmse'; end
    [z0, s0, b0] = run_frames(p);
    for m = {'twinb+twinf+log', 'twinb+eqt+log'}
        p.rx_ne_fix = m{1};
        [z1, s1, b1, txt] = run_frames(p);
        verifyEqual(tc, max(abs(z1(:) - z0(:))), 0, [path{1} ' ' m{1}]);
        verifyEqual(tc, max(abs(s1(:) - s0(:))), 0, [path{1} ' ' m{1}]);
        verifyEqual(tc, b1, b0, [path{1} ' ' m{1}]);
        verifyEmpty(tc, strfind(txt, 'RXS '), [path{1} ' ' m{1}]);
        verifyEmpty(tc, strfind(txt, 'RXL '), [path{1} ' ' m{1}]);
        verifyEmpty(tc, strfind(txt, 'RXA '), [path{1} ' ' m{1}]);
    end
end
end

function test_twinb_runs_on_delay_line(tc)
% the delay line with 'twinb+twinf+log' and 'twinb+eqt+log': finite outputs, one RXS line,
% (NB + 1) NR RXL lines and NB RXA lines per frame
p = dl_params(); p.own_out = true;
L = frame_layout(p); NB = numel(L.pil_center);
for m = {'twinb+twinf+log', 'twinb+eqt+log'}
    p.rx_ne_fix = m{1};
    [z, s, ~, txt] = run_frames(p);
    nf = size(s, 2);
    verifyTrue(tc, all(isfinite(z(:))), m{1});
    verifyEqual(tc, numel(strfind(txt, 'RXS ')), nf, m{1});
    ln = strtrim(splitlines(txt));
    verifyEqual(tc, nnz(startsWith(ln, 'RXL ')), nf * (NB + 1) * p.n_rx, m{1});
    verifyEqual(tc, nnz(startsWith(ln, 'RXA ')), nf * NB, m{1});
end
end

function test_twinb_profiles_at_receiver_level(tc)
% (f3b): 'twinb+log' on the flights of the three frames at 12 dB (runs 420, 452 and 459 of the
% clean validation pool, link_floor_partA.mat, with the link-floor params). On the antenna-blocks
% of their clean frames (BER < 1e-3) where the receiver's template fits the twin (misfit
% <= -10 dB), the multiple c_b of Gt(a, :) closest to the twin's profile G_b(a, :) sits at the
% measured gain ga(a, b): median |10 log10(|c_b|^2 / |ga|^2)| < 1 dB (level) and median
% |angle(c_b / ga)| < 0.2 rad (timing and rotations). The frame BER is the chart's (RXS).
lf = getenv('RX_LINK_FLOOR');
if isempty(lf), lf = fullfile(fileparts(tc.TestData.root), 'link-floor'); end
fa = fullfile(lf, 'results', 'link_floor_partA.mat'); fp = fullfile(lf, 'data', 'params.mat');
assertTrue(tc, isfile(fa) && isfile(fp), sprintf('link-floor data not found under %s', lf));
p0 = load(fp).params; p0.quiet_build = true; p0.active_threat = 'none';
[C, ~, ~] = pool_configs(p0, 'none', {'no_action'}); q = C(1).p; g_db = C(1).g_db;
q.own_out = true; q.rx_ne_fix = 'twinb+log';
A = load(fa).A;
T = A(find([A.e] == 12, 1)).T;
mdl = 'UAV_GCS_Threat_Link';
evalc('build_threat_model(q)');
set_link_snr(mdl, 12 + 10*log10(q.bits_per_symbol) - 10*log10(q.sps) + g_db, q);
set_param([mdl '/LevelTw'], 'Gain', get_param([mdl '/Level'], 'Gain'));
Lf = frame_layout(q); NB = numel(Lf.pil_center); NR = q.n_rx;
dc = []; dp = []; nfr = 0;
for rn = [420 452 459]
    j = find(T.run == rn, 1);
    assertNotEmpty(tc, j, sprintf('run %d not in the 12 dB part', rn));
    fd = T.speed(j) / 3.6 * q.carrier_freq / q.c_light;
    link_seed(mdl, double(T.seed(j)), fd, struct('ebno', 12, 'alt_m', NaN, 'k_sig_db', NaN, 'aoa1_deg', NaN, ...
        'rho', NaN, 'event_frame', NaN, 'frames', 20));
    txt = evalc('so = sim(mdl, ''StopTime'', num2str(19 * q.frame_duration));'); %#ok<NASGU>
    D = rx_blocks(txt, NR, NB);
    verifyNotEmpty(tc, D, sprintf('run %d: no frame printed', rn));
    for f = 1:numel(D)
        if ~(D(f).nbit / q.frame_length < 1e-3), continue; end
        nfr = nfr + 1;
        for b = 1:NB
            for a = 1:NR
                if ~(D(f).l(b + 1, a, 3) <= -10), continue; end
                dc(end + 1) = D(f).l(b + 1, a, 1) - D(f).ga2(b, a); %#ok<AGROW>
                dp(end + 1) = angle(exp(1j * (D(f).l(b + 1, a, 2) - D(f).gph(b, a)))); %#ok<AGROW>
            end
        end
    end
end
close_system(mdl, 0);
fprintf('(f3b) %d clean frames, %d antenna-blocks: median |c2/ga2| %.2f dB, median |angle(c/ga)| %.3f rad\n', ...
    nfr, numel(dc), median(abs(dc)), median(abs(dp)));
assertGreaterThan(tc, numel(dc), 0);
verifyLessThan(tc, median(abs(dc)), 1);
verifyLessThan(tc, median(abs(dp)), 0.2);
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
if getSimulinkBlockHandle([mdl '/LevelTw']) ~= -1      % the twin at the received level
    set_param([mdl '/LevelTw'], 'Gain', get_param([mdl '/Level'], 'Gain'));
end
link_seed(mdl, 11, 160);
txt = evalc('out = sim(mdl, ''StopTime'', num2str(3 * p.frame_duration));');
z = out.get('Rx_Z'); s = reshape(out.get('Rx_S'), 8, []); b = out.get('rx_bits_out');
close_system(mdl, 0);
end

function t0 = rxl_training(txt)
% the RXL lines of the training (block 0): [b, a, |c|^2 dB, angle c, share left dB, lags]
ln = splitlines(txt); ln = strtrim(ln(startsWith(strtrim(ln), 'RXL ')));
v = cell2mat(cellfun(@(x) str2double(strsplit(x(5:end))), ln, 'UniformOutput', false));
if isempty(v), t0 = zeros(0, 5); else, t0 = v(v(:, 1) == 0, :); end
end

function D = rx_blocks(txt, NR, NB)
% Per printed frame (an RXS line closes it): the chart's bit errors (RXS), every antenna's
% |ga|^2 [dB] (RXB) and angle(ga) [rad] (RXA) per pilot block, and the twin's |c|^2 [dB],
% angle c [rad] and misfit [dB] per block (0: the training) and antenna (RXL)
D = struct('nbit', {}, 'ga2', {}, 'gph', {}, 'l', {});
cur = blank_blocks(NR, NB);
for s = strtrim(splitlines(txt))'
    x = s{1};
    if numel(x) < 5 || x(4) ~= ' ', continue; end
    v = str2double(strsplit(strtrim(x(5:end))));
    switch x(1:3)
        case 'RXB'
            if numel(v) >= 3 + NR && v(1) >= 1 && v(1) <= NB, cur.ga2(v(1), :) = v(4:3 + NR); end
        case 'RXA'
            if numel(v) >= 1 + NR && v(1) >= 1 && v(1) <= NB, cur.gph(v(1), :) = v(2:1 + NR); end
        case 'RXL'
            if numel(v) >= 5 && v(1) >= 0 && v(1) <= NB && v(2) >= 1 && v(2) <= NR, cur.l(v(1) + 1, v(2), :) = v(3:5); end
        case 'RXS'
            if numel(v) >= 4, cur.nbit = v(4); end
            D(end + 1) = cur; %#ok<AGROW>
            cur = blank_blocks(NR, NB);
    end
end
end

function x = blank_blocks(NR, NB)
x = struct('nbit', NaN, 'ga2', nan(NB, NR), 'gph', nan(NB, NR), 'l', nan(NB + 1, NR, 3));
end

function s = strip_prints(s)
% the script without its fprintf lines and without the print-only functions appended last
k = find(startsWith(s, 'function v = rxd_'), 1);
if ~isempty(k)
    s = s(1:k - 1);
end
s = s(~startsWith(strtrim(s), 'fprintf('));
end

function d = msdiff(a, b)
% the lines of a not in b, counted as a multiset, sorted
[u, ~, ia] = unique(a(:));
[~, ib] = ismember(b(:), u);
n = accumarray(ia, 1, [numel(u) 1]) - accumarray(ib(ib > 0), 1, [numel(u) 1]);
d = repelem(u, max(n, 0));
d = d(:);
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
