function fail = crc32_fail(payload, e)
%CRC32_FAIL  CRC-32 check of a packet received with the error pattern e.
%   fail = crc32_fail(payload, e): the CRC-32 (IEEE 802.3 polynomial) of the payload is
%   appended, the error pattern e (payload + CRC bits) is applied to that codeword and the
%   codeword is checked; 1 when the check fails. A CRC is linear, so the check depends
%   only on e.
persistent cfg
if isempty(cfg)
    cfg = crcConfig('Polynomial', 'z^32 + z^26 + z^23 + z^22 + z^16 + z^12 + z^11 + z^10 + z^8 + z^7 + z^5 + z^4 + z^2 + z + 1');
end
cw = crcGenerate(payload(:), cfg);
[~, fail] = crcDetect(xor(cw, e(:) ~= 0), cfg);
fail = double(fail);
end
