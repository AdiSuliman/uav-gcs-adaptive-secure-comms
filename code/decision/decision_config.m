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
% hop, drawn per training and validation episode; 0 = on the new channel at the hop
% itself (Liu et al.'s comb jammer)
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
% middle one is init_params' nominal). In-band interferers up to 28 dB over our
% signal: a 10 W jammer from 4.5 times to 0.28 times the GCS distance
% (link_budget_table.m; a 30 dB jammer as in Liu et al.). Combined threats run
% at the middle three (C.combo_sev).
C.sev_names = {'very low', 'low', 'nominal', 'high', 'very high'};
C.sev = struct( ...
    'jamming',             struct('field', 'jsr_db',        'levels', [4 10 16 22 28]), ...
    'noise_burst',         struct('field', 'jsr_db',        'levels', [4 10 16 22 28]), ...
    'reactive_jamming',    struct('field', 'jsr_db',        'levels', [4 10 16 22 28]), ...
    'sweeping_jammer',     struct('field', 'jsr_db',        'levels', [4 10 16 22 28]), ...
    'tone_jamming',        struct('field', 'tone_jsr_db',   'levels', [4 10 16 22 28]), ...
    'path_loss',           struct('field', 'path_loss_db',  'levels', [6 10 14 18 22]), ...
    'spoofing',            struct('field', 'spoof_sir_db',  'levels', [-3 0 3 6 9]), ...
    'antenna_fault',       struct('field', 'fault_duty',    'levels', [0.1 0.2 0.3 0.45 0.6]), ...
    'benign_interference', struct('field', 'benign_int_db', 'levels', [-10 -8 -6 -4 -2]), ...
    'airframe_shadowing',  struct('field', 'shadow_db',     'levels', [8 14 20 26 32]));
C.nominal   = 3;            % index of the nominal level
C.combo_sev = [2 3 4];      % levels of each component of a combined threat
C.combos = {'jamming+path_loss', 'noise_burst+antenna_fault', 'sweeping_jammer+path_loss', 'spoofing+noise_burst', ...
            'reactive_jamming+path_loss', 'jamming+antenna_fault', 'spoofing+sweeping_jammer', ...
            'benign_interference+noise_burst', 'jamming+airframe_shadowing', 'tone_jamming+path_loss'};

% Signalling delay of a configuration change: the GCS must receive and apply the
% new configuration before the link runs on it, so a change decided in one cycle
% takes effect this many cycles later (an assumption; evaluate_policies.m checks
% the sensitivity to twice the value)
C.switch_delay = 1;
end
