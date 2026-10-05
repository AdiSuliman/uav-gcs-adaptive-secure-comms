function C = dev_cases()
%DEV_CASES  The receiver's dev flights (dev_dump.m): validate_phy's fixed geometry, the
%   real receiver, 10 flights of 22 frames at two Eb/N0 per case (440 frames).
%   Columns: tag, threat, JSR [dB], rho, K of our signal [dB], RMS delay spreads [ns]
%   (ours, the interferer's), Eb/N0 [dB], seeds.
C = {
  'j16r3d234',  'jamming',              16, 0.3, 10, [0 234],    [6 12], 7001:7010
  'j30r3d234',  'jamming',              30, 0.3, 10, [0 234],    [6 12], 7001:7010
  'j16r3d1000', 'jamming',              16, 0.3, 10, [0 1000],   [6 12], 7001:7010
  'j16r9d1000', 'jamming',              16, 0.9, 10, [0 1000],   [6 12], 7001:7010
  'j30r9d64',   'jamming',              30, 0.9, 10, [0 64],     [6 12], 7001:7010
  'j30r9d1000', 'jamming',              30, 0.9, 10, [0 1000],   [6 12], 7001:7010
  'j30r3d0',    'jamming',              30, 0.3, 10, [0 0],      [6 12], 7001:7010
  'c5d1000',    'none',                  0, 0.3, -5, [1000 0],   [0 6],  7011:7020
  'c2d234',     'none',                  0, 0.3,  2, [234 0],    [0 6],  7011:7020
  'j16k5b',     'jamming',              16, 0.3, -5, [234 234],  [6 12], 7021:7030
  'jt',         'jamming+tone_jamming', 16, 0.3, 10, [234 234],  [6 12], 7031:7040
  'j16r3d64',   'jamming',              16, 0.3, 10, [0 64],     [0 6],  7041:7050
  'j30r3d1000', 'jamming',              30, 0.3, 10, [0 1000],   [9 15], 7051:7060
};
end
