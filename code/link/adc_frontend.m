function [y, fs, clip] = adc_frontend(u, nbits, bo_db, iq, is)
%ADC_FRONTEND  Receive front end of one frame: AGC and ADC on every antenna.
%   [y, fs, clip] = adc_frontend(u, nbits, bo_db, iq, is)
%   u      received samples of the frame (samples x antennas)
%   nbits  ADC resolution per rail (AD9361: 12-bit ADCs, data sheet Rev. F, p. 33);
%          0 or Inf: no front end, y = u
%   bo_db  full scale over the rail RMS the AGC aims at [dB]
%   iq, is the quiet slot's samples and the training's start: the AGC holds one gain over
%          the frame, set from the larger of their mean powers (802.11's short training
%          serves AGC settling; the data sheet gives a 1 dB gain step and no settling time)
%   y      the quantized samples with the AGC gain taken out again (the receiver knows its
%          gain index), so the levels of u are kept
%   fs     full scale of every antenna's rails, in the units of u
%   clip   share of the rails clipped at full scale
% The gain moves in the data sheet's 1 dB steps (Table 1, gain step): the rail level is
% rounded up to the 1 dB grid, so full scale sits bo_db to bo_db + 1 dB above the RMS.
% Uniform mid-rise quantizer of 2^nbits levels over [-fs, fs] on I and Q, hard clipping.
%#codegen
y = u;
fs = inf(1, size(u, 2));
clip = 0;
if nbits <= 0 || ~isfinite(nbits), return; end
L = 2^(nbits - 1);
nc = 0;
for a = 1:size(u, 2)
    p = max(mean(abs(u(iq, a)).^2), mean(abs(u(is, a)).^2));
    lr = ceil(10*log10(max(p / 2, 1e-300)));              % rail power on the 1 dB gain grid [dB]
    fs(a) = 10^((lr + bo_db) / 20);
    d = fs(a) / L;                                        % quantization step
    qi = min(max(floor(real(u(:, a)) / d) + 0.5, -L + 0.5), L - 0.5);
    qq = min(max(floor(imag(u(:, a)) / d) + 0.5, -L + 0.5), L - 0.5);
    nc = nc + sum(abs(real(u(:, a))) >= fs(a)) + sum(abs(imag(u(:, a))) >= fs(a));
    y(:, a) = complex(qi * d, qq * d);
end
clip = nc / (2 * numel(u));
end
