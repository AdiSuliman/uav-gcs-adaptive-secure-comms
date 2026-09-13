function [action, mitigation_db] = rule_based_policy(threat_class)
%% C1 — RULE-BASED COUNTERMEASURE POLICY (updated: 8 threats)
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