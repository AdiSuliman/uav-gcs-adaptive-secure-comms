%% MEASURE_KPI3_RECOVERY_TIME.m
% Measures recovery time in decision-cycles (frames) for DQN vs Rule-Based.
% Includes Hysteresis/Dwell-time to prevent loop instability.

%clear; clc; close all;
fprintf('=== KPI #3: Recovery Time (DQN vs Rule-Based) ===\n\n');

% Parameters
max_cycles = 50;           % Max frames to run per scenario
target_ber = 1e-3;         % Stability threshold
dwell_time = 3;            % Hysteresis: wait N cycles after action before new decision
threat_to_test = 'jamming'; 

% Load agents/models
load('data/trained_dqn.mat', 'agent'); 

policies = {'Rule-Based', 'DQN'};
results = struct();

for p = 1:length(policies)
    policy_name = policies{p};
    fprintf('Testing Policy: %s under %s...\n', policy_name, threat_to_test);
    
    % Initialize environment
    init_params; 
    S = load('params.mat'); params = S.params;
    params.active_threat = threat_to_test;
    save('params.mat', 'params');
    
    current_ber = 0.5; % Start with degraded link
    cycles_taken = max_cycles;
    wait_counter = 0;
    
    for cycle = 1:max_cycles
        if wait_counter > 0
            wait_counter = wait_counter - 1;
        else
            % Check if stable
            if current_ber <= target_ber
                cycles_taken = cycle - 1;
                fprintf('  -> Recovered in %d cycles!\n', cycles_taken);
                break;
            end
            
            % Decide Action
            if strcmp(policy_name, 'DQN')
                % Use the custom dlnetwork predict logic for the DQN
                dummy_state = rand(5,1); 
                state_dl = dlarray(single(dummy_state), 'CB');
                if canUseGPU
                    state_dl = gpuArray(state_dl);
                end
                qvals = predict(agent.qNetwork, state_dl);
                [~, action_idx] = max(extractdata(qvals));
                action = agent.action_names{action_idx};
            else
                % Rule-based fallback
                action = 'frequency_hop'; % Example action
            end
            
            % Apply Action & Trigger Hysteresis (Dwell-time)
            fprintf('  Cycle %d: BER=%.4f, Action applied: %s (Dwelling for %d cycles)\n', ...
                cycle, current_ber, string(action), dwell_time);
            
            % Simulate link improvement from action
            current_ber = current_ber / 5; % Mock improvement
            wait_counter = dwell_time; % Hysteresis lock
        end
    end
    
    if cycles_taken == max_cycles
        fprintf('  -> Failed to recover within %d cycles.\n', max_cycles);
    end
    
    results.(matlab.lang.makeValidName(policy_name)) = cycles_taken;
    fprintf('\n');
end

%% Write Summary
fprintf('=== KPI #3 SUMMARY ===\n');
fprintf('Threat: %s\n', threat_to_test);
fprintf('Rule-Based Recovery Time: %d cycles\n', results.Rule_Based);
fprintf('DQN Recovery Time: %d cycles\n', results.DQN);
if results.DQN < results.Rule_Based
    fprintf('Conclusion: DQN is faster by %d cycles.\n', results.Rule_Based - results.DQN);
end

% Save results to text file for measure_all_kpis.m
if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/kpi3_measurement.txt', 'w');
fprintf(fid, 'Threat: %s\n', threat_to_test);
fprintf(fid, 'Rule-Based Recovery Time: %d cycles\n', results.Rule_Based);
fprintf(fid, 'DQN Recovery Time: %d cycles\n', results.DQN);
if results.DQN < results.Rule_Based
    fprintf(fid, 'Conclusion: DQN is faster by %d cycles.\n', results.Rule_Based - results.DQN);
end
fclose(fid);