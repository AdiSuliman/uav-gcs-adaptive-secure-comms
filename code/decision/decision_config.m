function C = decision_config()
%DECISION_CONFIG  Constants of the decision layer in one place: restoration
%   criterion, monitor, rule timing, agent state, reward weights and the threat
%   severities of the frame pools. Every decision-layer function reads them here.

% Restoration (proposal KPI 4): BER and packet loss at most 2x the clean link
C.ratio_ok   = 2;           % restored: BER <= 2 x clean BER at the same Eb/N0
C.ber_floor  = 1e-4;        % smallest clean-BER reference the pools resolve (>= 19k bits per cell)

% Link monitor (policy_monitor.m)
C.win        = 5;           % frames of the estimated-BER and packet-loss windows
C.deg_floor  = 1e-4;        % smallest clean reference of the estimated BER
C.heal       = 5;           % healthy cycles that close an incident (tried list reset)
C.confirm    = [2 2];       % alarm confirmation m-of-n (consecutive detections, Barajas et al.)
C.drop_db    = 4;           % default Eb/N0-estimate drop that confirms path_loss; the deployed value comes from choose_drop_threshold.m

% Decision period: one cycle decides on one received frame; with the decision
% latency (median < 10 ms, p95 < 20 ms target) a deployed loop decides every 20 ms.
% The pools hold consecutive frames, so the fading between two cycles is more
% correlated than 20 ms apart (a stated limitation); times are reported in cycles
% and in ms at this period.
C.period_ms = 20;

% Rule and table policies (policy_decide.m, rule_based_policy.m); the hold binds
% the DQN too, through the shield (policy_mask.m)
C.dwell = 2;                % consecutive cycles a proposal must persist
C.hold  = 3;                % cycles after a change before the next one
C.esc   = 3;                % escalation: degraded cycles in an applied configuration, or confirmed-alarm cycles at no_action
C.rule_mmse_db = 6;         % predicted MMSE gain from which the rule also nulls the interferer
C.ladder = {'spatial_diversity+power_control', 'channel_switch+spatial_diversity+power_control', ...
            'freq_diversity+power_control+fec_interleave', 'channel_switch+rate_reduce+power_control', ...
            'spatial_diversity+rate_reduce+power_control', ...
            'freq_diversity+spatial_diversity+power_control+fec_interleave'};   % rule escalation, in order

% Follower jammer (link_env.m): cycles it needs to re-acquire the channel after a
% hop, drawn per training and validation episode; 0 = a single-channel follower on
% the new channel at the hop itself (a jammer on every channel, frequency diversity's
% second carrier included, is the comb set of evaluate_policies.m and edge_map.m)
C.fdelay = [0 5];

% Agent state (policy_state.m): the last H cycles of observations (Liu et al.,
% spectrum waterfall; Mnih et al., stacked frames)
C.hist = 4;

% Reward per cycle, points (link_env.m); divided by 100
C.w_goodput  = 30;          % per unit of goodput given up
C.w_spectrum = 5;           % per extra channel
C.w_power    = 10;          % per +6 dB of transmit power
C.w_mmse     = 2;           % adaptive combining (processing, pilots)
C.w_switch   = 5;           % per configuration change or channel hop
C.w_false    = 20;          % per change on a healthy link
C.q_restored = 100;         % link restored (<= 2x clean)
C.q_partial  = 40;          % best quality below restoration (log-linear to 0 at 10x the threshold or the unmitigated BER);
                            % below 100 minus the largest running cost (39.5), so a restoring configuration
                            % always earns more than a non-restoring one in the same geometry

% Threat severities of the frame pools, five per threat over the full range (the
% middle one is init_params' nominal), the strongest at the sources' most severe
% value (dataset_levels.m): in-band interferers, spoofer and WLAN packets up to
% 30 dB over our signal, path loss up to 22 dB, airframe shadowing up to 25 dB, an open
% connector 26-36 dB.
% Combined threats run at the middle three (C.combo_sev).
C.sev_names = {'very low', 'low', 'nominal', 'high', 'very high'};
C.sev = struct( ...
    'jamming',             struct('field', 'jsr_db',        'levels', [4 10 16 23 30]), ...
    'noise_burst',         struct('field', 'jsr_db',        'levels', [4 10 16 23 30]), ...
    'reactive_jamming',    struct('field', 'jsr_db',        'levels', [4 10 16 23 30]), ...
    'sweeping_jammer',     struct('field', 'jsr_db',        'levels', [4 10 16 23 30]), ...
    'tone_jamming',        struct('field', 'tone_jsr_db',   'levels', [4 10 16 23 30]), ...
    'path_loss',           struct('field', 'path_loss_db',  'levels', [6 10 14 18 22]), ...
    'spoofing',            struct('field', 'spoof_sir_db',  'levels', [-3 0 3 12 30]), ...
    'antenna_fault',       struct('field', 'fault_atten_db', 'levels', [26 28.5 31 33.5 36]), ...
    'benign_interference', struct('field', 'benign_int_db', 'levels', [-10 -5 0 12 30]), ...
    'airframe_shadowing',  struct('field', 'shadow_db',     'levels', [8 12 15.5 20 25]));
C.nominal   = 3;            % index of the nominal level
C.combo_sev = [2 3 4];      % levels of each component of a combined threat
% Triples (one or several jammers at once, Liu et al.; natural, internal and hostile
% interference together, Yang et al.): three emitters, more than three antennas can
% null; two emitters with a lost antenna, so the two left can null only one; a jammer
% in a banking turn at long range; a tone and a spoofer in a turn. Every combination
% is also measured left out of training (experiment_combo_generalization.m).
C.combos = {'jamming+path_loss', 'noise_burst+antenna_fault', 'sweeping_jammer+path_loss', 'spoofing+noise_burst', ...
            'reactive_jamming+path_loss', 'jamming+antenna_fault', 'spoofing+sweeping_jammer', ...
            'benign_interference+noise_burst', 'jamming+airframe_shadowing', 'tone_jamming+path_loss', ...
            'jamming+spoofing+benign_interference', 'noise_burst+spoofing+antenna_fault', ...
            'jamming+airframe_shadowing+path_loss', 'tone_jamming+spoofing+airframe_shadowing'};

% Signalling delay of a configuration change: the GCS must receive and apply the
% new configuration before the link runs on it, so a change decided in one cycle
% takes effect this many cycles later (an assumption; evaluate_policies.m checks
% the sensitivity to twice the value)
C.switch_delay = 1;
end
