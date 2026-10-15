function [rs, n] = seed_stream(seed, purpose)
%SEED_STREAM  Random stream of one purpose of one seeded flight.
%   [rs, n] = seed_stream(seed, purpose): mt19937ar stream rs with the seed
%   n = seed_base(seed) + the purpose's offset, so every draw of a flight comes from
%   its own stream and no stream serves two flights or two purposes.
%   Offsets: channel 0, awgn 1, bits 2, threat 7, aoa 11, cal 13, ds 17, roll 19, k 23,
%   yaw 29, corr 31, gcsaoa 37, gcs 41, jam 43, alt 47, speed 53, body 59, wobble 61, the
%   idle-time RSSI's own estimation noise 5 (idle_rssi.m), an emitter of opportunity 3
%   (emitter_reading.m).
switch purpose
    case 'channel', off = 0;
    case 'awgn',    off = 1;
    case 'bits',    off = 2;
    case 'threat',  off = 7;
    case 'aoa',     off = 11;
    case 'cal',     off = 13;
    case 'ds',      off = 17;
    case 'roll',    off = 19;
    case 'k',       off = 23;
    case 'yaw',     off = 29;
    case 'corr',    off = 31;
    case 'gcsaoa',  off = 37;
    case 'gcs',     off = 41;
    case 'jam',     off = 43;
    case 'alt',     off = 47;
    case 'speed',   off = 53;
    case 'body',    off = 59;
    case 'wobble',  off = 61;
    case 'idle',    off = 5;
    case 'amb',     off = 3;
    otherwise, error('seed_stream: unknown purpose ''%s''', purpose);
end
n = seed_base(seed) + off;
rs = RandStream('mt19937ar', 'Seed', n);
end
