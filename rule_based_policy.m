function [action, mitigation_db] = rule_based_policy(threat_class)
%% C1 — RULE-BASED COUNTERMEASURE POLICY (updated: 8 threats)
%
% NOTE (2026-09-19, D19): mitigation_db here is per-threat (15/10/15/8/6/9/12
% dB) but is NOT applied anywhere downstream -- both call sites
% (run_closed_loop_diagnostic.m, measure_kpi3_recovery_time.m) use only the
% returned `action` name. The physical mitigation effect for BOTH the DQN
% and the rule-based policy is computed via the shared action_mitigation_db
% (25/15/25/25 dB per action, see run_closed_loop_diagnostic.m /
% run_closed_loop_with_detector.m / train_dqn.m). This function's
% mitigation_db is kept for readability/documentation of what a real
% per-threat-tuned rule policy WOULD use, but "DQN-vs-rule agreement" is a
% decision-policy comparison only, not two independently-realized
% countermeasure systems. State this precisely in the report.
threat_class = char(threat_class);

switch threat_class
    case 'jamming'
        action = 'channel_switch'; mitigation_db = 15;
    case 'reactive_jamming'
        action = 'channel_switch_fast'; mitigation_db = 10;
    case 'sweeping_jammer'
        % Same power source as jamming (jsr_db); channel switch removes it
        % just as effectively since it's still full-power when present.
        action = 'channel_switch_fast'; mitigation_db = 15;
    case 'spoofing'
        action = 'freq_diversity'; mitigation_db = 8;
    case 'path_loss'
        action = 'rate_reduce'; mitigation_db = 6;
    case 'noise_burst'
        action = 'rate_reduce'; mitigation_db = 9;
    case 'antenna_fault'
        action = 'spatial_diversity'; mitigation_db = 12;
    case 'benign_interference'
        % NOT an attack -- correct response is to do nothing. Overreacting to
        % benign interference wastes resources and is exactly what the FAR
        % (False Alarm Rate) metric is meant to catch.
        action = 'no_action'; mitigation_db = 0;
    case 'none'
        action = 'no_action'; mitigation_db = 0;
    otherwise
        warning('rule_based_policy: unknown threat class "%s" — defaulting to no_action', threat_class);
        action = 'no_action'; mitigation_db = 0;
end
end