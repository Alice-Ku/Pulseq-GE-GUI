function [seq, rep] = writeMJGgre2dgui(baseDir, seq_name, sys, gui_params)
% AK: 0709 fixed timing for 3T and 1.5T

% Create a new sequence object
seq = mr.Sequence(sys);
warning('OFF', 'mr:restoreShape');

% AK unpack gui_params here
fov_x = gui_params.fov_x;
fov_y = gui_params.fov_y;
Nx = gui_params.Nx;
Ny = gui_params.Ny;
alpha = gui_params.alpha;
slice_thickness = gui_params.slice_thickness;
sliceGap = gui_params.sliceGap;
minTR = gui_params.minTR;
TR = gui_params.TR;
minTE = gui_params.minTE;
TE = gui_params.TE;
dwell = gui_params.dwell;
rfSpoil = gui_params.rfSpoil;
rfSpoilingInc = gui_params.rfSpoilingInc;
dda = gui_params.dda;
pislquant = gui_params.pislquant;
NSlices = gui_params.NSlices;

delta_kx=1/fov_x;
delta_ky=1/fov_y;

% Create RF and slice-select gradient
[rf, gz] = mr.makeSincPulse(alpha*pi/180, 'Duration', 3e-3, ...
    'SliceThickness', slice_thickness, 'apodization', 0.42, ...
    'use', 'excitation', ...
    'timeBwProduct', 4, 'system', sys);

% Create readout gradient and ADC
gx = mr.makeTrapezoid('x','FlatArea',Nx*delta_kx,'FlatTime',Nx*dwell,'system',sys);
adc = mr.makeAdc(Nx,'Duration',gx.flatTime,'Delay',gx.riseTime,'system',sys);

% Create prephaser and rephaser
gxPre = mr.makeTrapezoid('x','Area',-gx.area/2,'Duration',1.8e-3,'system',sys); % AK: changed 1e-3 to 1.2e-3 to match gzReph
gzReph = mr.makeTrapezoid('z','Area',-gz.area/2,'Duration',1.8e-3,'system',sys); % AK: changed 1e-3 to 1.2e-3 for 1.5T; 1.8 for 1mm on 3T

% Phase encoding
phaseAreas = ((0:Ny-1)-Ny/2)*delta_ky;
gyPre = mr.makeTrapezoid('y','Area',max(abs(phaseAreas)),'Duration',mr.calcDuration(gxPre),'system',sys);
peScales=phaseAreas/gyPre.area;

% Create spoilers
gxSpoil=mr.makeTrapezoid('x','Area',2*Nx*delta_kx,'Duration', 3e-3,'system',sys); % AK: changed 1.9e-3 to 3e-3 for 1.5T; 3 for 3T 1mm
gzSpoil=mr.makeTrapezoid('z','Area',4/slice_thickness,'Duration', 3e-3,'system',sys); % AK: changed 1.9e-3 to 2e-3 for 1.5T; 3 for 3T 1mm

% Calculate minimum TE
tRFcentre = mr.calcRfCenter(rf);
tDead = 0;
[TEmin_continuous, TEmin, TEbreakdown] = calcMinTE_GRE_2( ...
    tRFcentre, gz, gzReph, gxPre, gx, seq, tDead);

fprintf('Minimum TE (continuous) = %.3f ms\n', TEmin_continuous*1e3);
fprintf('Minimum TE (quantised)  = %.3f ms\n', TEmin*1e3);

if minTE
    delayTE = 0;
    fprintf('Using minimum TE = %.3f ms\n', TEmin*1e3);
else
    delayTE = TE - TEmin;
    fprintf('Selected TE = %.3f ms\n', TE*1e3);
    fprintf('Additional TE delay = %.3f ms\n', delayTE*1e3);
end

disp('TE breakdown:');
disp(TEbreakdown);

% Calculate minimum TR
TRmin = mr.calcDuration(rf, gz) ...
    + mr.calcDuration(gzReph, gxPre) ...
    + mr.calcDuration(gx, adc) ...
    + mr.calcDuration(gxSpoil, gzSpoil);

TRmin = ceil(TRmin/seq.gradRasterTime) * seq.gradRasterTime;
% Snap TRmin upward to the gradient raster.

if minTR
    delayTR = 0;
    fprintf('Minimum TR = %.3f ms\n', TRmin*1e3);
else
    delayTR = TR - TRmin;
    fprintf('Selected TR = %.3f ms\n', TR*1e3);
    fprintf('Additional TR delay = %.3f ms\n', delayTR*1e3);
end

% RF spoiling params
rf_phase=0;
rf_inc=0;

% Main scan loop
% TRID values:
%   1 = receiver gain calibration TR  
%   2 = disdaq / dummy TR
%   3 = imaging TR
% slicePositions = slice_thickness * ((1:NSlices) - (NSlices+1)/2);   % AK0729: added slice loop
slicePositions = (slice_thickness + sliceGap) * ((1:NSlices) - (NSlices+1)/2);       % AK0813: add slice gap 

% Receiver gain calibration: before all slices
for i = 1:pislquant
    s = 1;
    addEvents(i, s, slicePositions, 1);
end

% dda
for i = 1:dda
    for s = 1:NSlices
        addEvents(i, s, slicePositions, 2);
    end
end

% dda and main acquisition
for ky = 1:Ny
    for s = 1:NSlices
        addEvents(ky, s, slicePositions, 3);
    end
end
% End of main scan loop

% Define sequence metadata
seq.setDefinition('FOV', [fov_x fov_y slice_thickness]);

seq.setDefinition('Name', seq_name);

% Write .seq
seq_path = fullfile(baseDir, seq_name);
seq.write([seq_path '.seq'])

% Plot and test report
seq.plot('timeRange', [0 3]*TR);
rep = seq.testReport;
fprintf([rep{:}]);

% Nested function for adding events
function addEvents(i, s, slicePositions, tridLabel)
    % TRID values:
    %   1 = receiver gain calibration TR  
    %   2 = disdaq / dummy TR
    %   3 = imaging TR

    ispislquant = (tridLabel == 1);
    isdda = (tridLabel == 2);

    if ispislquant || isdda
        pe = eps;
    else
        pe = peScales(i);
        if pe == 0
            pe = eps;
        end
    end

    % AK: multi-slice
    slicePos = slicePositions(s);
    rf.freqOffset = gz.amplitude * slicePos;

    if rfSpoil
        rf.phaseOffset = rf_phase/180*pi;
        adc.phaseOffset = rf_phase/180*pi;
        rf_inc = mod(rf_inc + rfSpoilingInc, 360.0);
        rf_phase = mod(rf_phase + rf_inc, 360.0);
    else
        rf.phaseOffset = 0;
        adc.phaseOffset = 0;
    end

    seq.addBlock(rf, gz, ...
        mr.makeLabel('SET', 'TRID', tridLabel));

    % Prephaser + PE + slice rephaser
    seq.addBlock(gxPre, mr.scaleGrad(gyPre, pe), gzReph);

    % TE delay
    seq.addBlock(mr.makeDelay(delayTE));

    if isdda
        seq.addBlock(gx);
    else
        seq.addBlock(gx, adc);
    end

    % Spoil + PE rewind + TR delay
    seq.addBlock(mr.makeDelay(delayTR), ...
                 gxSpoil, ...
                 mr.scaleGrad(gyPre, -pe), ...
                 gzSpoil);

end

end