function h = side_sha256(f)
%SIDE_SHA256  SHA-256 of a file (lower-case hex), read in chunks.
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r');
if fid < 0, error('side_sha256:open', 'side_sha256: cannot open %s', f); end
c = onCleanup(@() fclose(fid));
while true
    b = fread(fid, 64 * 2^20, '*uint8');
    if isempty(b), break; end
    md.update(b);
end
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end
