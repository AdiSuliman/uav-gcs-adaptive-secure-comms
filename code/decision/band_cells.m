function [cells, scen] = band_cells(p)
%BAND_CELLS  Threat cells and scenarios of the bandwidth study (experiment_core_bw.m).
%   [cells, scen] = band_cells(p)   p the link params (tone_offset_hz, inband_cap_db; defaults
%   300 kHz and 30 dB)
%   Jammer widths B_J (each in its source) and the span its coverage uses (band_cover.m):
%     CW tone   narrowband; offset uniform in +-300 kHz (init_params.m): the tone's range
%     4 MHz     Liu et al.: jamming of 4 MHz instantaneous bandwidth, raised cosine of
%               roll-off 0.3, the 4 MHz read as its noise bandwidth (symbol rate; the paper
%               does not say, and the readings trade 1.14 dB in band against a row of the
%               hop's rejection, docs/core_bw_protocol.md 3): +-2.6 MHz, its occupied edge
%     8 MHz     Mekdad et al.: Gaussian noise at 10 MS/s low-passed at 4 MHz with a 1 MHz
%               transition: +-4.5 MHz, the stopband edge
%     20 MHz    Panitsas et al.: a $20 dongle covering 20 MHz: +-10 MHz
%     70 MHz    Panitsas et al.: AWGN over 802.11 channels 1, 6 and 11 (2412, 2437, 2462 MHz,
%               20 MHz each): fixed 2402-2472 MHz
%     83.5 MHz  the whole 2400-2483.5 MHz band (ETSI EN 300 328), inside the 160 MHz of
%               Panitsas et al.'s jammer radio
%   Every B_J of 4 MHz and more fills the receiver's +-2 MHz window flat, so it is the barrage
%   'jamming' waveform at its in-band level; the tone is 'tone_jamming'. Noise jammers are
%   centred on our home channel (Mekdad et al. tuned to the target's channel), the 70 MHz one
%   sits where Panitsas et al. put it.
%   Fixed total power (primary): JSR_tot in {4, 10, 16, 23, 30} dB, the decision layer's five
%   levels, the top Liu et al.'s 30 dB; level jsr_inband.m. Equal in-band level (secondary):
%   JSR_in in {4, 10, 16, 23} dB of the barrage, one cell serving every B_J >= 4 MHz, read only
%   where JSR_in + 10 log10(B_J / 1 MHz) <= 30 dB.
%   cells  1 x 34: name, threat, field (level field), level [dB], bj [MHz], jsr_tot (NaN on
%          the equal-level cells), jsr_in, slice (equal-level cell), J (span, band_cover.m)
%   scen   1 x 44 scenarios: cell (index into cells), bj, jsr_tot, jsr_in, slice, J, band
%          ('narrowband' or 'wideband')
if nargin < 1, p = struct(); end
toff = 0.3; if isfield(p, 'tone_offset_hz'), toff = p.tone_offset_hz / 1e6; end
cap = 30; if isfield(p, 'inband_cap_db'), cap = p.inband_cap_db; end
BJ = [0 4 8 20 70 83.5];
SPAN = {struct('kind', 'tone', 'half', toff, 'lo', NaN, 'hi', NaN), ...
        struct('kind', 'centred', 'half', 2.6, 'lo', NaN, 'hi', NaN), ...
        struct('kind', 'centred', 'half', 4.5, 'lo', NaN, 'hi', NaN), ...
        struct('kind', 'centred', 'half', 10, 'lo', NaN, 'hi', NaN), ...
        struct('kind', 'fixed', 'half', NaN, 'lo', 2402, 'hi', 2472), ...
        struct('kind', 'fixed', 'half', NaN, 'lo', 2400, 'hi', 2483.5)};
TOT = [4 10 16 23 30];
INB = [4 10 16 23];
cells = struct('name', {}, 'threat', {}, 'field', {}, 'level', {}, 'bj', {}, 'jsr_tot', {}, 'jsr_in', {}, ...
    'slice', {}, 'J', {});
scen = struct('cell', {}, 'bj', {}, 'jsr_tot', {}, 'jsr_in', {}, 'slice', {}, 'J', {}, 'band', {});
for b = 1:numel(BJ)
    for t = TOT
        L = jsr_inband(t, BJ(b));
        if BJ(b) == 0
            c = struct('name', sprintf('cw_tot%g', t), 'threat', 'tone_jamming', 'field', 'tone_jsr_db');
        else
            c = struct('name', sprintf('bw%g_tot%g', BJ(b), t), 'threat', 'jamming', 'field', 'jsr_db');
        end
        c.level = L; c.bj = BJ(b); c.jsr_tot = t; c.jsr_in = L; c.slice = false; c.J = SPAN{b};
        cells(end+1) = c; %#ok<AGROW>
        scen(end+1) = struct('cell', numel(cells), 'bj', BJ(b), 'jsr_tot', t, 'jsr_in', L, 'slice', false, ...
            'J', SPAN{b}, 'band', band_of(BJ(b))); %#ok<AGROW>
    end
end
for L = INB
    cells(end+1) = struct('name', sprintf('inb%g', L), 'threat', 'jamming', 'field', 'jsr_db', 'level', L, ...
        'bj', NaN, 'jsr_tot', NaN, 'jsr_in', L, 'slice', true, 'J', []); %#ok<AGROW>
    for b = find(BJ >= 4)
        t = jsr_inband(L, BJ(b), 'total');
        if t > 30 + 1e-9, continue; end
        scen(end+1) = struct('cell', numel(cells), 'bj', BJ(b), 'jsr_tot', t, 'jsr_in', L, 'slice', true, ...
            'J', SPAN{b}, 'band', 'wideband'); %#ok<AGROW>
    end
end
assert(all([cells.level] <= cap + 1e-9), 'band_cells: a level above the %g dB in-band cap', cap);
end

function s = band_of(bj)
if bj == 0, s = 'narrowband'; else, s = 'wideband'; end
end
