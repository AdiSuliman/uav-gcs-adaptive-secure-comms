function varargout = unk_write(cmd, varargin)
%UNK_WRITE  FM.unk in data/fusion.mat (D111): the only file the OOD run writes beside its report
%   and its set-4 marker, its removal by guard (e) at C1d, and the KPI 1 provenance check.
%   unk_write('add', U, f)        FM.unk = U (unk_stat('model')) into the fusion file f, every
%                                 other variable and field as it was, saved in one rename
%                                 (commit_mat.m); U.base records f before it: its SHA-256 and the
%                                 SHA-256 of its content (rest_id); refused when FM.unk exists
%   unk_write('remove', reason, f)  FM.unk removed from f (a copy of f kept beside it); the
%                                 removed model, its base and the reason in
%                                 <folder>/fusion_unk_removed.mat
%   [ok, why] = unk_write('base_ok', f, marker)  f differs from the fusion the fourth set was
%                                 read with (B3r: marker, results/fresh3_read_started.txt, records
%                                 its SHA-256) only by FM.unk: its base, or the removed one's,
%                                 names that file, and f's content without FM.unk is the base's
%   h = unk_write('rest_id', L)   SHA-256 of a loaded fusion file's content without FM.unk
switch cmd
    case 'add'
        [U, f] = varargin{:};
        L = load(f);
        assert(isfield(L, 'FM') && isstruct(L.FM), 'unk_write:fusion', '%s holds no fusion FM', f);
        assert(~isfield(L.FM, 'unk'), 'unk_write:exists', '%s holds FM.unk already: it is written once', f);
        U.base = struct('sha256', file_sha(f), 'rest', rest_id(L), 'time', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
        L.FM.unk = U;
        save_as(L, f);
    case 'remove'
        [reason, f] = varargin{:};
        L = load(f);
        assert(isfield(L, 'FM') && isfield(L.FM, 'unk'), 'unk_write:none', '%s holds no FM.unk', f);
        R = struct('unk', L.FM.unk, 'reason', reason, 'time', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
        bak = sprintf('%s_before_unk_removal_%s.mat', f(1:end-4), char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
        [ok, msg] = copyfile(f, bak);
        if ~ok || dir(bak).bytes ~= dir(f).bytes, error('unk_write:backup', 'no copy of %s: %s', f, msg); end
        L.FM = rmfield(L.FM, 'unk');
        save_as(L, f);
        save(removed_file(f), 'R');
    case 'base_ok'
        [f, marker] = varargin{:};
        [varargout{1}, varargout{2}] = base_ok(f, marker);
    case 'rest_id'
        varargout{1} = rest_id(varargin{1});
    otherwise
        error('unk_write:cmd', 'unk_write: unknown command %s', cmd);
end
end

function [ok, why] = base_ok(f, marker)
ok = false; why = '';
if ~isfile(f) || ~isfile(marker), why = 'no fusion file or no B3r marker'; return; end
tk = regexp(fileread(marker), 'data/fusion.mat sha256 (\w+)', 'tokens', 'once');
if isempty(tk), why = 'the B3r marker records no SHA-256 of the fusion'; return; end
L = load(f);
B = [];
if isfield(L, 'FM') && isstruct(L.FM) && isfield(L.FM, 'unk') && isfield(L.FM.unk, 'base')
    B = L.FM.unk.base;
elseif isfile(removed_file(f))
    R = load(removed_file(f), 'R'); B = R.R.unk.base;
end
if isempty(B), why = 'no FM.unk base'; return; end
if ~strcmp(B.sha256, tk{1}), why = 'FM.unk was added to another fusion file than the one B3r read'; return; end
if ~strcmp(B.rest, rest_id(L)), why = 'the fusion differs from the one B3r read beyond FM.unk'; return; end
ok = true;
end

function h = rest_id(L)
% The content of a fusion file without FM.unk, variables in name order.
if isfield(L, 'FM') && isstruct(L.FM) && isfield(L.FM, 'unk'), L.FM = rmfield(L.FM, 'unk'); end
v = sort(fieldnames(L));
c = cellfun(@(n) L.(n), v, 'UniformOutput', false);
md = java.security.MessageDigest.getInstance('SHA-256');
md.update(getByteStreamFromArray({v, c}));
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end

function save_as(L, f)
% L's variables into f in one rename, in f's MAT-file version.
v = '-v7'; if mat73(f), v = '-v7.3'; end
tmp = [f(1:end-4) '_unk_tmp.mat'];
assert(~isfile(tmp), 'unk_write:tmp', '%s exists (a cut write): look at it before writing again', tmp);
save(tmp, '-struct', 'L', v);
commit_mat(tmp, f);
end

function y = mat73(f)
fid = fopen(f, 'r'); h = fread(fid, 116, '*char')'; fclose(fid);
y = contains(h, 'MATLAB 7.3');
end

function r = removed_file(f)
r = fullfile(fileparts(f), 'fusion_unk_removed.mat');
end

function h = file_sha(f)
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r');
assert(fid > 0, 'unk_write:read', 'cannot read %s', f);
c = onCleanup(@() fclose(fid));
while true
    b = fread(fid, 2^25, '*uint8');
    if isempty(b), break; end
    md.update(b);
end
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end
