function [configLines, seq, S, rep, measured] = mainSpiralB00630(baseDir, seq_name, mergedCV, gui_params)

pislquant = 10;

% Load scanner configurations
hw = getScannerConfigMerged(mergedCV);
configtxt = fullfile(baseDir, 'configOut.txt');
configLines = showScannerConfigToFile(hw, configtxt);

% Build Pulseq design system
sys = buildPulseqSystem(hw, ...
    'UseObliqueMargin', true, ...
    'UseRealDeadTimes', false);

% Write .seq file
% ONLY NEED TO CHANGE THE WRITE FUNCTION
[seq, rep, measured] = writeSpiralB00630(baseDir, seq_name, hw, sys, gui_params);

% Convert .seq to a Pulseg object
seq_path = fullfile(baseDir, seq_name);
psq = pulseg.fromSeq([seq_path '.seq']); 

% Build GE HW system
sys_ge = buildGESystem(hw);

% Check PNS, RF, gradient limits

PNSwt = [1.0 1.0 1.0];
params = pge2.check(psq, sys_ge, ...
    'PNSwt', PNSwt, ...
    'PNSThresholdPct', 100); % MJG added PNS threshold 80 % or 100 %

% Save Pulseg object and parameters
seq_mat_path = fullfile(baseDir, seq_name);
save(seq_mat_path, 'psq', 'params', 'pislquant');

% Plot sequence
S = pge2.plot(psq, sys_ge, 'blockRange', [1 2], ...
    'PNSwt', PNSwt, ...
    'rotate', false, ...
    'interpolate', false);

% Read original .seq sequence
seq = mr.Sequence();
seq.read([seq_path '.seq']);

% Validate the PulSeg/GE representation against the original .seq
pge2.validate(psq, sys_ge, seq, [], 'row', [], 'plot', false);

% Apply slice offset for the Pulseg object
xloc = 0;
yloc = 0;
zloc = 0;
psq = pge2.translateFOVrf(psq, [xloc yloc zloc]);

% Write .pge file for scanners
pge_path = fullfile(baseDir, seq_name);
pge2.serialize(psq, [pge_path '.pge'], 'pislquant', 10, 'params', params, 'checkHash', false);

end