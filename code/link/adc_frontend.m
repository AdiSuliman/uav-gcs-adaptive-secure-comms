function [y, fs, clip] = adc_frontend(u, nbits, bo_db, iq, is, att_db)
%ADC_FRONTEND  Receive front end of one frame: AGC and ADC on every antenna.
%   [y, fs, clip] = adc_frontend(u, nbits, bo_db, iq, is, att_db)
%   u      received samples of the frame (samples x antennas)
%   nbits  ADC resolution per rail (AD9361: 12-bit ADCs, data sheet Rev. F, p. 33);
%          0 or Inf: no front end, y = u
%   bo_db  full scale over the rail RMS the AGC aims at [dB]
%   iq, is the quiet slot's samples and the training's start: the AGC sets the frame's
%          gain from the larger of their mean powers (802.11's short training serves AGC
%          convergence, IEEE 802.11-2007, 17.3.2.1; the data sheet gives a 1 dB gain step
%          and no settling time)
%   att_db fast attack (default Inf: the gain held over the frame): after the training's
%          start, every block of 16 samples whose mean rail power exceeds the level the
%          gain was set for by more than att_db steps the gain down to that block's level,
%          from 16 samples after the block on (an AGC that adjusts its gain while
%          receiving unless frozen, averaging 16 samples and waiting 16 after a change: the
%          CC2500's defaults, data sheet p. 76, taken at this sample rate; the AD9361 names
%          a fast AGC mode without its timing, p. 33)
%   y      the quantized samples with the AGC gain taken out again (the receiver knows its
%          gain index), so the levels of u are kept
%   fs     full scale of every antenna's rails at the end of the frame, in the units of u
%   clip   share of the rails clipped at full scale
% The gain moves in the data sheet's 1 dB steps (Table 1, gain step): the rail level is
% rounded up to the 1 dB grid, so full scale sits bo_db to bo_db + 1 dB above the RMS.
% Uniform mid-rise quantizer of 2^nbits levels over [-fs, fs] on I and Q, hard clipping.
%#codegen
if nargin < 6, att_db = Inf; end
y = u;
fs = inf(1, size(u, 2));
clip = 0;
if nbits <= 0 || ~isfinite(nbits), return; end
L = 2^(nbits - 1);
NA = 16;                                                  % samples the attack averages and waits
N = size(u, 1);
nc = 0;
for a = 1:size(u, 2)
    p = max(mean(abs(u(iq, a)).^2), mean(abs(u(is, a)).^2));
    lr = ceil(10*log10(max(p / 2, 1e-300)));              % rail power on the 1 dB gain grid [dB]
    fs(a) = 10^((lr + bo_db) / 20);
    fv = fs(a) * ones(N, 1);                              % full scale of every sample
    if isfinite(att_db)
        k = is(end) + 1;
        while k + NA - 1 <= N
            lb = 10*log10(max(mean(abs(u(k:k+NA-1, a)).^2) / 2, 1e-300));
            if lb > lr + att_db && k + 2*NA <= N
                lr = ceil(lb); fs(a) = 10^((lr + bo_db) / 20);
                fv(k + 2*NA:N) = fs(a);
                k = k + 2*NA;
            else
                k = k + NA;
            end
        end
    end
    d = fv / L;                                           % quantization step
    qi = min(max(floor(real(u(:, a)) ./ d) + 0.5, -L + 0.5), L - 0.5);
    qq = min(max(floor(imag(u(:, a)) ./ d) + 0.5, -L + 0.5), L - 0.5);
    nc = nc + sum(abs(real(u(:, a))) >= fv) + sum(abs(imag(u(:, a))) >= fv);
    y(:, a) = complex(qi .* d, qq .* d);
end
clip = nc / (2 * numel(u));
end
