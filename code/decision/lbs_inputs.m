function out = lbs_inputs(cmd, varargin)
%LBS_INPUTS  The inputs of the LB-S screen (lbs_screen.m): copy with SHA-256, verify, clean reference.
%   out = lbs_inputs('copy', src, dst)    copies policy_pools.mat, unknown_threat_agents.mat,
%       trained_dqn.mat and clean_val_pools.mat from the folder src to the folder dst, hashes the
%       source and the copy, and writes dst/lbs_inputs.sha256 (sha256sum format). out.files,
%       out.sha256. src is only read.
%   out = lbs_inputs('verify', dst)       hashes the files of dst against dst/lbs_inputs.sha256
%   h = lbs_inputs('hash', file)          SHA-256 of one file, lower-case hex
%   r = lbs_inputs('clean_ref', ebno)     stops unless the clean reference read from
%       data/policy_pools.mat of the current folder (clean_ber_ref.m) is finite at ebno [dB]: a
%       folder without that file reads NaN and every cycle then reads as degraded
switch cmd
    case 'hash'
        out = sha256_file(varargin{1});
    case 'copy'
        out = copy_inputs(varargin{:});
    case 'verify'
        out = verify_inputs(varargin{:});
    case 'clean_ref'
        out = clean_ref_check(varargin{:});
    otherwise
        error('lbs_inputs: unknown command %s', cmd);
end
end

function f = input_files()
f = {'policy_pools.mat', 'unknown_threat_agents.mat', 'trained_dqn.mat', 'clean_val_pools.mat'};
end

function out = copy_inputs(src, dst)
files = input_files();
if ~isfolder(src), error('lbs_inputs:source', 'lbs_inputs: %s is not a folder', src); end
if ~isfolder(dst), mkdir(dst); end
if strcmpi(canon(src), canon(dst)), error('lbs_inputs:same', 'lbs_inputs: the copy would land on its source %s', src); end
need = 0;
for i = 1:numel(files)
    f = fullfile(src, files{i});
    if ~isfile(f), error('lbs_inputs:missing', 'lbs_inputs: %s is missing', f); end
    d = dir(f); need = need + d.bytes;
end
free = double(java.io.File(dst).getUsableSpace());
if free < need + 2^30
    error('lbs_inputs:space', 'lbs_inputs: %.1f GB free in %s, %.1f GB needed', free / 2^30, dst, (need + 2^30) / 2^30);
end
h = cell(1, numel(files));
for i = 1:numel(files)
    fs = fullfile(src, files{i}); fd = fullfile(dst, files{i}); part = [fd '.part'];
    h{i} = sha256_file(fs);
    copyfile(fs, part);
    if ~strcmp(sha256_file(part), h{i})
        error('lbs_inputs:copy', 'lbs_inputs: the copy %s differs from %s (left in place)', part, fs);
    end
    movefile(part, fd);
end
fid = fopen(fullfile(dst, 'lbs_inputs.sha256'), 'w');
for i = 1:numel(files), fprintf(fid, '%s  %s\n', h{i}, files{i}); end
fclose(fid);
out = struct('files', {files}, 'sha256', {h});
end

function out = verify_inputs(dst)
files = input_files();
mf = fullfile(dst, 'lbs_inputs.sha256');
if ~isfile(mf), error('lbs_inputs:manifest', 'lbs_inputs: %s is missing', mf); end
t = regexp(fileread(mf), '([0-9a-f]{64})\s+(\S+)', 'tokens');
want = struct();
for i = 1:numel(t), want.(matlab.lang.makeValidName(t{i}{2})) = t{i}{1}; end
h = cell(1, numel(files));
for i = 1:numel(files)
    k = matlab.lang.makeValidName(files{i});
    if ~isfield(want, k), error('lbs_inputs:manifest', 'lbs_inputs: %s lists no hash for %s', mf, files{i}); end
    f = fullfile(dst, files{i});
    if ~isfile(f), error('lbs_inputs:missing', 'lbs_inputs: %s is missing', f); end
    h{i} = sha256_file(f);
    if ~strcmp(h{i}, want.(k)), error('lbs_inputs:hash', 'lbs_inputs: %s differs from its recorded SHA-256', f); end
end
out = struct('files', {files}, 'sha256', {h});
end

function r = clean_ref_check(ebno)
f = fullfile(pwd, 'data', 'policy_pools.mat');
if ~isfile(f)
    error('lbs_inputs:clean_ref', ['lbs_inputs: %s is missing; the clean reference is read from data/policy_pools.mat of the ' ...
        'current folder'], f);
end
L = load(f, 'clean_ref');
if ~isfield(L, 'clean_ref'), error('lbs_inputs:clean_ref', 'lbs_inputs: %s holds no clean_ref', f); end
for k = {'ebno', 'ber', 'ber_est'}
    if ~isfield(L.clean_ref, k{1}) || ~all(isfinite(L.clean_ref.(k{1})(:)))
        error('lbs_inputs:clean_ref', 'lbs_inputs: the clean reference table (%s) of %s is missing or not finite', k{1}, f);
    end
end
clear clean_ber_ref
r = struct();
for k = {'ber', 'ber_est'}
    b = clean_ber_ref(ebno, k{1});
    if ~all(isfinite(b(:))) || any(b(:) <= 0)
        error('lbs_inputs:clean_ref', 'lbs_inputs: the clean reference (%s) is not finite and positive at the Eb/N0 grid', k{1});
    end
    r.(k{1}) = [min(b(:)), max(b(:))];
end
b = clean_ber_ref(ebno, 'plr_fec');
r.plr_fec = all(isfinite(b(:)));
if ~r.plr_fec && any(isfinite(b(:)))
    error('lbs_inputs:clean_ref', 'lbs_inputs: the coded-link clean reference (plr_fec) is finite at some Eb/N0 only');
end
end

function p = canon(p)
p = char(java.io.File(p).getCanonicalPath());
end

function h = sha256_file(f)
% SHA-256 of a file, read in 16 MB blocks.
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r');
if fid < 0, error('lbs_inputs:open', 'lbs_inputs: cannot open %s', f); end
c = onCleanup(@() fclose(fid));
while true
    b = fread(fid, 2^24, '*uint8');
    if isempty(b), break; end
    md.update(typecast(b, 'int8'));
end
d = typecast(md.digest(), 'uint8');
h = lower(reshape(dec2hex(d, 2)', 1, []));
end
