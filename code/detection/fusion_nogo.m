function ok = fusion_nogo(action, PK, GP)
%FUSION_NOGO  The no-go of the deployed fusion design on this profile (docs/d91_deploy.md).
%   fusion_nogo('write', PK, GP)  B2F (select_fusion.m with FUSION_FIT = 'enlarged'): the
%       measured design PK failed the adoption rule (check GP) on this profile's enlarged fit
%       set. B2F stops before its save, so data/fusion.mat stays the kept fusion. Writes
%       data/fusion_nogo.mat: the design, the check, the time and the kept fusion's SHA-256.
%   ok = fusion_nogo('check')  true when data/fusion_nogo.mat records a no-go of fusion_pick()
%       and data/fusion.mat is still the fusion it kept (same SHA-256). B3r then reads the
%       fourth test set once with the kept fusion.
%   ok = fusion_nogo('clear')  after a B2F that saved a fusion: the record is kept aside as
%       data/fusion_nogo_superseded_<time>.mat (true when there was one).
f = 'data/fusion_nogo.mat'; fk = 'data/fusion.mat';
switch action
    case 'write'
        assert(isfile(fk), 'fusion_nogo:kept', '%s not found: there is no kept fusion to record', fk);
        h = file_sha256(fk);
        nogo = struct('pick', PK, 'check', GP, 'time', datestr(now, 'yyyy-mm-dd HH:MM:SS'), ...
            'kept_sha256', h, 'rule', 'fusion_adopt(''branch'') failed'); %#ok<NASGU>
        save(f, 'nogo');
        fprintf('No-go recorded in %s: the kept fusion %s stays (SHA-256 %s)\n', f, fk, h);
        ok = true;
    case 'check'
        ok = false;
        if ~isfile(f) || ~isfile(fk), return; end
        L = load(f, 'nogo');
        if ~isfield(L, 'nogo') || ~all(isfield(L.nogo, {'pick', 'kept_sha256'})), return; end
        ok = isequal(L.nogo.pick, fusion_pick()) && strcmp(L.nogo.kept_sha256, file_sha256(fk));
    case 'clear'
        ok = isfile(f);
        if ok
            g = sprintf('data/fusion_nogo_superseded_%s.mat', datestr(now, 'yyyymmdd_HHMMSS'));
            movefile(f, g);
            fprintf('The no-go record %s no longer names data/fusion.mat: kept as %s\n', f, g);
        end
    otherwise
        error('fusion_nogo:action', 'unknown action %s', action);
end
end

function h = file_sha256(f)
% SHA-256 of a file's bytes, as sha256sum prints it.
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r');
assert(fid > 0, 'fusion_nogo:read', 'cannot read %s', f);
b = fread(fid, 2^24, '*uint8');
while ~isempty(b)
    md.update(b);
    b = fread(fid, 2^24, '*uint8');
end
fclose(fid);
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end
