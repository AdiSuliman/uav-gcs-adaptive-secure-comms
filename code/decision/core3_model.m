function [M, why] = core3_model(f)
%CORE3_MODEL  The three-state CNN that scores the pools for rule_core3 (D121 item 16, P-B): this
%   checkout's own B3c model (train_core_cnn.m, core_cnn_config.m model file by default).
%   [M, why] = core3_model(f)
%   M    net, N (the model's window, cycles), sha256 (of the file), id ('core3 <sha256> N<N>', in the
%        pool cells' key and in PP.core3_id); [] when the model is not there or not a three-state
%        model (clean, narrowband, wideband in order), why then saying what is missing
%   Condition (a) of P-B: the model exists.
M = []; why = '';
if nargin < 1 || isempty(f), f = core_cnn_config().model; end
if ~isfile(f)
    why = sprintf('%s not found', f); return
end
L = load(f, 'net', 'N', 'groups');
if ~all(isfield(L, {'net', 'N', 'groups'}))
    why = sprintf('%s holds no net, N and groups', f); return
end
if ~(isscalar(L.N) && L.N >= 1 && L.N == round(L.N))
    why = sprintf('%s holds no window N', f); return
end
if ~isequal(cellstr(string(L.groups(:)')), {'none', 'tone_jamming', 'jamming'})
    why = sprintf('%s does not hold the states clean, narrowband, wideband in order', f); return
end
h = file_sha(f);
M = struct('net', L.net, 'N', double(L.N), 'sha256', h, 'id', sprintf('core3 %s N%d', h, double(L.N)));
end

function h = file_sha(f)
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r');
b = fread(fid, Inf, '*uint8'); fclose(fid);
if ~isempty(b), md.update(b); end
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end
