function R = fec_rx_config(f)
%FEC_RX_CONFIG  The coded link's decoder this checkout builds its frames with: the switch
%   fec_rx of its profile.json (f, default 'profile.json').
%   R = []      no profile.json or no fec_rx: nothing stated
%   R.mode 'd78'   "fec_rx": "d78", the D78 erasure rules (fec_packets.m without jsi): the
%               rules profile 1's pools were decoded with
%   R.mode 'jsi'   "fec_rx": {"mode": "jsi", "rev": ..., "q": ..., "c": ..., "h": ...,
%               "erase_sym": ..., "frame": ..., "thr": ..., "flag_clean": ...}: per-symbol
%               jammer state information on the combiner output and erasures against the
%               codeword's quiet floor (fec_packets.m, jsi_inputs.m), with the values chosen
%               on dev set C (dev_fec_burst.m, docs/noise_burst_protocol.md):
%       rev         the decisions entry that records the choice (a tag of the pools' model)
%       q           quantile of the residuals that starts the floor (jsi_floor.m)
%       c           a symbol is flagged when its variance exceeds c x the floor
%       h           neighbours on each side averaged into a symbol's variance (0 or 1)
%       erase_sym   flagged symbols enter as erasures (false: their low weight alone)
%       frame       whole-frame erasure: 'a' pilot error > p.erase_pilot_mse, 'b' none, 'c'
%                   pilot error > thr in a frame whose flagged share is below 3 x flag_clean
%       thr, flag_clean  frame 'c' only: the pilot-error threshold and the clean frames'
%                   flagged share at c
%   Only init_params reads n_rx from the same file; params.mat and params_id stay as they are.
if nargin < 1 || isempty(f), f = 'profile.json'; end
R = [];
if ~isfile(f), return; end
P = jsondecode(fileread(f));
if ~isstruct(P) || ~isfield(P, 'fec_rx') || isempty(P.fec_rx), return; end
v = P.fec_rx;
if (ischar(v) || isstring(v)) && strcmp(v, 'd78')
    R = struct('mode', 'd78');
    return
end
bad = @(m) error('fec_rx_config:value', '%s: fec_rx %s', f, m);
if ~isstruct(v) || ~isfield(v, 'mode') || ~strcmp(v.mode, 'jsi')
    bad('must be "d78" or a struct with mode "jsi"');
end
need = {'rev', 'q', 'c', 'h', 'erase_sym', 'frame'};
miss = need(~isfield(v, need));
if ~isempty(miss), bad(['lacks ' strjoin(miss, ', ')]); end
if ~ischar(v.rev) || isempty(v.rev), bad('rev must name the decisions entry'); end
if ~(isscalar(v.q) && v.q > 0 && v.q < 0.5), bad('q must lie in (0, 0.5)'); end
if ~(isscalar(v.c) && isfinite(v.c) && v.c > 1), bad('c must be finite and above 1'); end
if ~(isscalar(v.h) && ismember(v.h, [0 1])), bad('h must be 0 or 1'); end
if ~(isscalar(v.erase_sym) && islogical(v.erase_sym)), bad('erase_sym must be true or false'); end
if ~ischar(v.frame) || ~ismember(v.frame, {'a', 'b', 'c'}), bad('frame must be a, b or c'); end
if strcmp(v.frame, 'c')
    if ~isfield(v, 'thr') || ~(isscalar(v.thr) && v.thr > 0), bad('frame c needs thr > 0'); end
    if ~isfield(v, 'flag_clean') || ~(isscalar(v.flag_clean) && v.flag_clean >= 0 && v.flag_clean < 1)
        bad('frame c needs flag_clean in [0, 1)');
    end
else
    v.thr = NaN; v.flag_clean = NaN;
end
R = struct('mode', 'jsi', 'rev', v.rev, 'q', v.q, 'c', v.c, 'h', v.h, 'erase_sym', v.erase_sym, 'frame', v.frame, ...
    'thr', v.thr, 'flag_clean', v.flag_clean);
end
