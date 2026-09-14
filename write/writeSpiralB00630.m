% AK edited it so it works with the GUI
% Interleaved spiral sequence
%
% RESTRUCTURED VERSION
% -------------------------------------------------------------------------
% High-level structure:
%
%   1. Main function
%        - Creates the Pulseq object
%        - Builds a parameter structure
%        - Builds reusable events
%        - Writes trajectory files
%        - Assembles the scan loop
%        - Writes / checks the .seq file
%
%   2. Parameter helper
%        - All user-facing scan parameters are collected in one structure.
%
%   3. Event helper
%        - RF pulses, slice gradients, spiral gradients, ADCs, spoilers and
%          timing delays are created once and stored in an event structure.
%
%   4. Acquisition-module helpers
%        - These are the important "logical modules" that become repeated
%          Pulseq block patterns and, later, GE/TOPPE parent blocks:
%
%              addHighResExcitation()
%              addHighResReadout()
%              addHighResSpoilAndTRDelay()
%              addB0Excitation()
%              addB0TEReadout()
%              addB0SpoilAndTRDelay()
%
%   5. Trajectory helpers
%        - High-resolution and B0 spiral design are separated from sequence
%          assembly so the scan loop is easy to inspect.
%
% Notes on parent blocks and scan loop:
% -------------------------------------------------------------------------
% Pulseq itself only knows about seq.addBlock(...). The GE pulseg/TOPPE
% conversion layer later infers "parent blocks" by finding repeated block
% structures. The safest way to help it is to keep every logical module
% consistent:
%
%   - The high-resolution readout block always contains gx, gy, adc, TRID,
%     and LIN.
%   - The B0 readout block always contains gxB0, gyB0, adcB0, and TRID.
%   - RF, rephaser, TE delay, readout, spoiler, and TR delay are kept as
%     explicit, predictable modules.
%
% This avoids the situation where a repeated logical block sometimes has an
% ADC and sometimes does not, which is one common cause of:
%
%   "Expected ADC event not found in base block ..."
%
function [seq, rep, measured] = writeSpiralB00630(baseDir, seq_name, hw, sys, gui_params)

%% ========================================================================
%  1. INITIALISE SEQUENCE OBJECT
%  ========================================================================

seq = mr.Sequence(sys);
warning('OFF', 'mr:restoreShape');   % Arbitrary spiral waveforms can trigger this warning.

%% ========================================================================
%  2. COLLECT PARAMETERS
%  ========================================================================
%  All acquisition parameters live in p. This avoids having timing constants,
%  matrix sizes, TE/TR settings, and reconstruction-file settings
%  scattered
%  throughout the sequence assembly code.

p = makeSpiralB0Params(baseDir, seq_name, gui_params, hw, sys);

%% ========================================================================
%  3. BUILD REUSABLE EVENTS
%  ========================================================================
%  e contains all Pulseq events used by the scan loop. This is where the
%  waveform design happens. The scan-loop section below should not need to
%  know how the spiral was designed.

e = buildSpiralB0Events(p, sys);

%% ========================================================================
%  4. WRITE RECONSTRUCTION TRAJECTORY FILES
%  ========================================================================
%  The sequence and the reconstruction must agree on the gradient scaling.
%  Therefore the k-space trajectories are written after scaling has been
%  applied to the gradients.
measured = writeTrajectoryFiles(p, e);

%% ========================================================================
%  5. ASSEMBLE SCAN LOOP
%  ========================================================================
%  This is the high-level sequence definition.
%
%  For one slice, the logical loop is:
%
%       high-res interleaf 1
%       high-res interleaf 2
%       ...
%       high-res interleaf Nint
%       B0 TE1 shot      optional
%       B0 TE2 shot      optional
%
%  For GE/TOPPE conversion, this should become a simple loop over repeated
%  parent-block templates rather than a long, hard-to-debug list of blocks.

rfState.rf_phase = 0;
rfState.rf_inc   = 0;

slicePositions = (p.slice_thickness + p.sliceGap) * ((1:p.NSlices) - (p.NSlices+1)/2);   % AK0805: implemented slice loop

for slice = 1:p.NSlices
    slicePos = slicePositions(slice);
    % --------------------------------------------------------------------
    % 5A. High-resolution multishot spiral imaging
    % --------------------------------------------------------------------
    %
    % Parent-block pattern expected by converter:
    %
    %   RF excitation + slice-select gradient
    %   RF ringdown wait
    %   slice rephaser
    %   high-resolution spiral readout + ADC + labels
    %   spoiler + TR delay
    %
    % The actual interleaf rotation is expected to be handled by the scanner
    % / sequence interpreter. Therefore the same gx/gy waveform is played
    % for each interleaf, while LIN is incremented.
    %

    % AK0803: add pislquant only for the first slice
    if slice > 1
        p.pislquant = 0;
    end

    for i = (-p.dda - p.pislquant + 1):p.Nint
        isdda = 0;
        ispislquant = 0;
        interleaf = 0;
        if i <= -p.pislquant
            isdda = 1;
            tridNo = 1;
        elseif i <= 0 
            ispislquant = 1;
            tridNo = 2;
        else
            interleaf = i;
            tridNo = 3;
        end

        [e, rfState] = updateHighResRfSpoiling(e, rfState, p);

        tridLabel = mr.makeLabel('SET', 'TRID', tridNo);
        linLabel  = mr.makeLabel('SET', 'LIN', interleaf-1);

        addHighResExcitation(seq, e, p, slicePos, tridLabel, linLabel);
        if isdda
            addHighResDummyReadout(seq, e, p);
        else
            addHighResReadout(seq, e, p, interleaf);
        end

        addHighResSpoilAndTRDelay(seq, e);

        % -------------------------------------------------------------------------
        % High-resolution TE (added 08/27)
        % TE is measured from the centre of the excitation RF pulse
        % to the start of the ADC.
        % -------------------------------------------------------------------------
        
        rfCenter = mr.calcRfCenter(e.rf);
        rephaserDuration = mr.calcDuration(e.gzReph);
        adcStart = e.high.adcDelay;
        
        TE_high = rfCenter + rephaserDuration + adcStart;
        
        fprintf('--- High-resolution TE ---\n');
        fprintf('RF centre       = %.3f ms\n', rfCenter*1e3);
        fprintf('Rephaser        = %.3f ms\n', rephaserDuration*1e3);
        fprintf('ADC delay       = %.3f ms\n', adcStart*1e3);
        fprintf('High-res TE     = %.3f ms\n', TE_high*1e3);


    end

    % --------------------------------------------------------------------
    % 5B. Low-resolution B0 map
    % --------------------------------------------------------------------
    %
    % Optional two-echo low-resolution single-shot B0 map.
    %
    % The two B0 shots use the same low-resolution spiral and ADC but have
    % different TE delays and different TRID labels.
    %
    % Logical parent-block pattern:
    %
    %   B0 RF excitation + slice-select gradient
    %   B0 slice rephaser
    %   B0 TE delay
    %   B0 spiral readout + ADC + TRID
    %   B0 spoiler + TR delay
    %
    if p.doB0Map

        addB0Excitation(seq, e, p, slicePos, 4);
        addB0TEReadout(seq, e, e.delayTE1_B0);
        addB0SpoilAndTRDelay(seq, e, e.delayTR_B0_1);

        addB0Excitation(seq, e, p, slicePos, 5);
        addB0TEReadout(seq, e, e.delayTE2_B0);
        addB0SpoilAndTRDelay(seq, e, e.delayTR_B0_2);

    end

end

%% ========================================================================
%  6. OUTPUT AND BASIC BLOCK INSPECTION
%  ========================================================================

seq.setDefinition('FOV', [p.fov_x p.fov_y p.slice_thickness]);
seq.setDefinition('Name', seq_name);

seq_path = fullfile(baseDir, seq_name);
seq.write([seq_path '.seq']);

% Re-read the written sequence and print a compact block summary. This is a
% useful sanity check for Pulseq block contents before running pulseg.fromSeq.
seq2 = mr.Sequence(sys);
seq2.read([seq_path '.seq']);

nBlocksToPrint = min(12, numel(seq2.blockEvents));
fprintf('\n--- First %d Pulseq blocks after writing/re-reading ---\n', nBlocksToPrint);
for b = 1:nBlocksToPrint
    block = seq2.getBlock(b);
    fprintf('Block %3d: ADC=%d RF=%d GX=%d GY=%d GZ=%d\n', b, ...
        hasEvent(block,'adc'), ...
        hasEvent(block,'rf'), ...
        hasEvent(block,'gx'), ...
        hasEvent(block,'gy'), ...
        hasEvent(block,'gz'));
end

seq.plot('timeRange', [0 3]*p.TR);
rep = seq.testReport;

end

%% ########################################################################
%  PARAMETER SETUP
%  ########################################################################

function p = makeSpiralB0Params(baseDir, seq_name, gui_params, hw, sys)

% Keep file/path inputs.
p.baseDir  = baseDir;
p.seq_name = seq_name;
p.hw       = hw;

% -------------------------------------------------------------------------
% Main imaging parameters
% -------------------------------------------------------------------------
p.fov = gui_params.fov_x;
p.fov_x = p.fov;
p.fov_y = p.fov;

p.Nx = gui_params.Nx;
p.Ny = gui_params.Nx; %#ok<NASGU>

p.Nint    = gui_params.Nint;             % Number of high-resolution interleaves.
p.NSlices = gui_params.NSlices;

p.alpha = gui_params.alpha;               % degrees
p.slice_thickness = gui_params.slice_thickness;
p.sliceGap = gui_params.sliceGap;

p.minTR = gui_params.minTR;
p.TR    = gui_params.TR;

p.dwell = gui_params.dwell; %#ok<NASGU>
p.rfSpoil       = gui_params.rfSpoil;
p.rfSpoilingInc = gui_params.rfSpoilingInc; 

p.BW = gui_params.BW; %#ok<NASGU>

% Already in sys
sys.rfWait = hw.psd_rf_wait_s;                   % 500e-6;
sys.rfRingdownTime = hw.rfRingdownTime_s;        % 148e-6;
sys.rfDeadTime     = hw.rfDeadTime_s;            % 100e-6;   % or whatever your config requires

% Dummy/discarded acquisition support was present in the original code but
% inactive. The modular structure below keeps the imaging loop clean. If DDA
% shots are reintroduced later, add a dedicated addHighResDummyReadout()
% module rather than making the same readout block sometimes omit ADC.
p.dda = gui_params.dda; %#ok<NASGU>       % Was 0
p.pislquant = gui_params.pislquant;       % Was 0

p.deltak = 1/p.fov;

p.dtDelay = 0;
p.dtDelay = round(p.dtDelay/sys.gradRasterTime) * sys.gradRasterTime;

% -------------------------------------------------------------------------
% B0 prescan parameters
% -------------------------------------------------------------------------
p.doB0Map = gui_params.doB0Map;

p.NxB0    = gui_params.NB0;
p.NintB0  = gui_params.NintB0;
p.alphaB0 = gui_params.alphaB0;

p.TE1_B0 = gui_params.TE1B0;
p.TE2_B0 = gui_params.TE2B0;
p.TR_B0  = gui_params.TRB0; %#ok<NASGU> % Preserved, although current logic uses p.TR.

% -------------------------------------------------------------------------
% Fat saturation parameters
% -------------------------------------------------------------------------
p.B0_T     = 3.0;
p.sat_ppm  = -3.45;
p.sat_freq = p.sat_ppm*1e-6*p.B0_T*sys.gamma;

% -------------------------------------------------------------------------
% Spiral design parameters
% -------------------------------------------------------------------------
p.Gmax = hw.maxGrad_mTm;     % mT/m
p.Smax = hw.maxSlew_Tms;     % T/m/s
p.res  = p.fov/p.Nx;         % m

% vds2 expects G/cm and G/cm/s.
p.GmaxVds = p.Gmax/10;       % G/cm
p.SmaxVds = p.Smax*100;      % G/cm/s

p.TadcHigh = 2e-6;   
p.desiredADCSamplesHigh = gui_params.ADCSamples;

p.dtSpiral = sys.gradRasterTime;

% B0 spiral design.
p.TadcB0 = 2e-6;
p.desiredADCSamplesB0 = gui_params.ADCSamplesB0;
p.resB0 = p.fov/p.NxB0; % AK: adjust B0 size, was 2.5e-3

end

%% ########################################################################
%  EVENT CONSTRUCTION
%  ########################################################################

function e = buildSpiralB0Events(p, sys)

e = struct();

%% ------------------------------------------------------------------------
%  Fat saturation and high-resolution RF events
%  ------------------------------------------------------------------------

e.rf_fs = mr.makeGaussPulse(110*pi/180, ...
    'system', sys, ...
    'Duration', 8e-3, ...
    'bandwidth', 200, ...
    'freqOffset', p.sat_freq, ...
    'use', 'saturation');

e.gz_fs_spoil = mr.makeTrapezoid('z', sys, ...
    'Area', p.deltak*p.Nx*2);

[e.rf, e.gz] = mr.makeSincPulse(p.alpha*pi/180, ...
    'Duration', 3e-3, ...
    'SliceThickness', p.slice_thickness, ...
    'apodization', 0.42, ...
    'use', 'excitation', ...
    'timeBwProduct', 4, ...
    'system', sys);

e.gzReph = mr.makeTrapezoid('z', ...
    'Area', -e.gz.area/2, ...
    'system', sys);

e.gz_spoil = mr.makeTrapezoid('z', sys, ...
    'Area', p.deltak*p.Nx*4);

%% ------------------------------------------------------------------------
%  High-resolution spiral gradient, ADC, and k-space trajectory
%  ------------------------------------------------------------------------

fprintf('--- Calculating high-resolution vds trajectory ---\n');
[e.high, e.gx, e.gy, e.adc] = buildHighResSpiralEvents(p, sys);

%% ------------------------------------------------------------------------
%  High-resolution TR timing
%  ------------------------------------------------------------------------

e.delayTR = calculateHighResTRDelay(p, e, sys);

%% ------------------------------------------------------------------------
%  Optional B0-map events
%  ------------------------------------------------------------------------

if p.doB0Map
    fprintf('--- Calculating B0 vds trajectory ---\n');
    e = buildB0Events(p, e, sys);
end

end

%% ########################################################################
%  HIGH-RESOLUTION SPIRAL DESIGN
%  ########################################################################

function [high, gx, gy, adc] = buildHighResSpiralEvents(p, sys)

high = struct();

% AK: scale the Smax to smaller
[kGrad, g, ~, ~, kADC, ~, info] = vds2( ...
    p.SmaxVds, ...
    p.GmaxVds, ...
    p.dtSpiral, ...
    p.Nint, ...
    [p.fov*1e2, 0], ...
    1/(2*p.res*1e2), ...
    p.desiredADCSamplesHigh, ...
    p.TadcHigh);

fprintf('HR SmaxVDS = %.4f\n', p.SmaxVds);
fprintf('HR GmaxVDS = %.4f\n', p.GmaxVds);

high.info = info;

% Raw vds gradient in G/cm.
gCore = g(:).';

% Add explicit ramp-up/ramp-down so the arbitrary gradient starts and ends
% at zero. This is important for interpreter robustness.
[gFull, nUp, nCore, nDown] = addComplexGradientRamps( ...
    gCore, p.SmaxVds, sys.gradRasterTime);

% Convert from G/cm to Hz/m for Pulseq.
gSpiralC = gFull / 1e2 * sys.gamma;

% Scale to hardware limits.
[scale, gSpiralC_s] = scaleComplexGradientToSystem(gSpiralC, sys);

% Scale k-space trajectories consistently with gradient scaling.
kGrad_s = scale * kGrad;
kADC_s  = scale * kADC;

% ADC starts at the beginning of the core, not during ramp-up.
adcDelay = p.dtDelay + nUp * sys.gradRasterTime;

nADC = floor(p.desiredADCSamplesHigh / sys.adcSamplesDivisor) ...
    * sys.adcSamplesDivisor;

adcDuration = nADC * sys.adcRasterTime;

adc = mr.makeAdc(nADC, ...
    'Duration', adcDuration, ...
    'Delay', adcDelay, ...
    'system', sys);

gxw = real(gSpiralC_s(:));
gyw = imag(gSpiralC_s(:));

gx = mr.makeArbitraryGrad('x', gxw, ...
    'Delay', p.dtDelay, ...
    'system', sys, ...
    'first', 0, ...
    'last', 0);

gy = mr.makeArbitraryGrad('y', gyw, ...
    'Delay', p.dtDelay, ...
    'system', sys, ...
    'first', 0, ...
    'last', 0);

% Store metadata needed by trajectory writer and diagnostics.
high.kGrad_s = kGrad_s;
high.kADC_s  = kADC_s;
high.nADC    = nADC;
high.nUp     = nUp;
high.nCore   = nCore;
high.nDown   = nDown;
high.scale   = scale;
high.gSpiralC_unscaled = gSpiralC;
high.gSpiralC_s        = gSpiralC_s;
high.adcDelay          = adcDelay;
high.adcDuration       = adcDuration;

kmaxADC_s = max(abs(kADC_s));
resolutionADC_s_mm = 10 / (2*kmaxADC_s);

gamma_hz = 42.576e6;
dt = sys.gradRasterTime;

fprintf('Gradient scaling factor = %.4f\n', scale);
fprintf('--- High-resolution spiral after scaling ---\n');
fprintf('Samples total = %d\n', numel(gSpiralC_s));
fprintf('Ramp up       = %d samples\n', nUp);
fprintf('Core          = %d samples\n', nCore);
fprintf('Ramp down     = %d samples\n', nDown);
fprintf('Max |G|       = %.2f mT/m\n', max(abs(gSpiralC_s))/gamma_hz*1e3);
fprintf('Max slew      = %.2f T/m/s\n', max(abs(diff(gSpiralC_s)/dt))/gamma_hz);
fprintf('Scaled ADC kmax = %.6f cm^-1\n', kmaxADC_s);
fprintf('Scaled ADC resolution = %.3f mm\n', resolutionADC_s_mm);
fprintf('ADC samples requested = %d\n', p.desiredADCSamplesHigh);
fprintf('ADC samples used      = %d\n', nADC);
fprintf('ADC starts at %.3f ms\n', adcDelay*1e3);
fprintf('ADC ends   at %.3f ms\n', (adcDelay + adcDuration)*1e3);
fprintf('Spiral core ends at %.3f ms\n', ...
    (p.dtDelay + (nUp + nCore)*sys.gradRasterTime)*1e3);


end

%% ########################################################################
%  B0 SPIRAL DESIGN
%  ########################################################################

function e = buildB0Events(p, e, sys)

% Low-resolution B0 spiral trajectory.
NintB0 = p.NintB0;
rmaxB0 = 1/(2*p.resB0*1e2);

Fcentre_cm = p.fov*1e2;
Fedge_cm   = 0.5*Fcentre_cm;
Fcoeff     = [Fcentre_cm, Fedge_cm - Fcentre_cm];

% AK: scale SmaxVds
[kGradB0, gB0, ~, ~, kADCB0, ~, infoB0] = vds2( ...
    p.SmaxVds, ...
    p.GmaxVds, ...
    p.dtSpiral, ...
    NintB0, ...
    Fcoeff, ...
    rmaxB0, ...
    p.desiredADCSamplesB0, ...
    p.TadcB0);

gCoreB0 = gB0(:).';

[gFullB0, nUpB0, nCoreB0, nDownB0] = addComplexGradientRamps( ...
    gCoreB0, p.SmaxVds, sys.gradRasterTime);

gSpiralCB0 = gFullB0 / 1e2 * sys.gamma;

[scaleB0, gSpiralCB0_s] = scaleComplexGradientToSystem(gSpiralCB0, sys);

% IMPORTANT: use scaleB0 here, not the high-resolution scale.
kGradB0_s = scaleB0 * kGradB0;
kADCB0_s  = scaleB0 * kADCB0;

gxwB0 = real(gSpiralCB0_s(:));
gywB0 = imag(gSpiralCB0_s(:));

e.gxB0 = mr.makeArbitraryGrad('x', gxwB0, ...
    'Delay', 0, ...
    'system', sys, ...
    'first', 0, ...
    'last', 0);

e.gyB0 = mr.makeArbitraryGrad('y', gywB0, ...
    'Delay', 0, ...
    'system', sys, ...
    'first', 0, ...
    'last', 0);

adcDelayB0 = nUpB0 * sys.gradRasterTime;

nADCB0 = floor((nCoreB0 * sys.gradRasterTime) / sys.adcRasterTime / sys.adcSamplesDivisor) ...
    * sys.adcSamplesDivisor;

tADCB0 = nADCB0 * sys.adcRasterTime;

e.adcB0 = mr.makeAdc(nADCB0, ...
    'Duration', tADCB0, ...
    'Delay', adcDelayB0, ...
    'system', sys);

[e.rfB0, e.gzB0] = mr.makeSincPulse(p.alphaB0*pi/180, ...
    'Duration', 3e-3, ...
    'SliceThickness', p.slice_thickness, ...
    'apodization', 0.42, ...
    'use', 'excitation', ...
    'timeBwProduct', 4, ...
    'system', sys);

e.gzRephB0 = mr.makeTrapezoid('z', ...
    'Area', -e.gzB0.area/2, ...
    'system', sys);

e.gzSpoilB0 = mr.makeTrapezoid('z', sys, ...
    'Area', p.deltak*p.NxB0*4);

% TE calculation. The TE is measured from the RF centre to the start of ADC.
rfCenterB0 = mr.calcRfCenter(e.rfB0);
tFixedB0 = rfCenterB0 + mr.calcDuration(e.gzRephB0) + e.adcB0.delay;

e.delayTE1_B0 = ceil((p.TE1_B0 - tFixedB0) / sys.gradRasterTime) * sys.gradRasterTime;
e.delayTE2_B0 = ceil((p.TE2_B0 - tFixedB0) / sys.gradRasterTime) * sys.gradRasterTime;

if e.delayTE1_B0 < 0
    error('TE1_B0 is too short. Increase TE1_B0.');
end
if e.delayTE2_B0 < 0
    error('TE2_B0 is too short. Increase TE2_B0.');
end

e.delayTR_B0_1 = calculateB0TRDelay(p, e, e.delayTE1_B0, sys);
e.delayTR_B0_2 = calculateB0TRDelay(p, e, e.delayTE2_B0, sys);

e.b0.info      = infoB0;
e.b0.kGrad_s   = kGradB0_s;
e.b0.kADC_s    = kADCB0_s;
e.b0.nADC      = nADCB0;
e.b0.nUp       = nUpB0;
e.b0.nCore     = nCoreB0;
e.b0.nDown     = nDownB0;
e.b0.scale     = scaleB0;
e.b0.adcDelay  = adcDelayB0;
e.b0.tADC      = tADCB0;

kmaxADCB0_s = max(abs(kADCB0_s));
resolutionADCB0_s_mm = 10 / (2*kmaxADCB0_s);

gamma_hz = 42.576e6;
dt = sys.gradRasterTime;

fprintf('B0 Gradient scaling factor = %.4f\n', scaleB0);
fprintf('--- B0 spiral after scaling ---\n');
fprintf('Samples total = %d\n', numel(gSpiralCB0_s));
fprintf('Ramp up       = %d samples\n', nUpB0);
fprintf('Core          = %d samples\n', nCoreB0);
fprintf('Ramp down     = %d samples\n', nDownB0);
fprintf('Max |G| B0    = %.2f mT/m\n', max(abs(gSpiralCB0_s))/gamma_hz*1e3);
fprintf('Max slew B0   = %.2f T/m/s\n', max(abs(diff(gSpiralCB0_s)/dt))/gamma_hz);
fprintf('Scaled B0 ADC kmax = %.6f cm^-1\n', kmaxADCB0_s);
fprintf('Scaled B0 ADC resolution = %.3f mm\n', resolutionADCB0_s_mm);
fprintf('B0 ADC samples requested = %d\n', p.desiredADCSamplesB0);
fprintf('B0 ADC samples used      = %d\n', nADCB0);
fprintf('B0 ADC starts at %.3f ms\n', adcDelayB0*1e3);
fprintf('B0 ADC ends   at %.3f ms\n', (adcDelayB0 + tADCB0)*1e3);
fprintf('TE1_B0 = %.3f ms, extra delay = %.3f ms\n', p.TE1_B0*1e3, e.delayTE1_B0*1e3);
fprintf('TE2_B0 = %.3f ms, extra delay = %.3f ms\n', p.TE2_B0*1e3, e.delayTE2_B0*1e3);

end

%% ########################################################################
%  SCAN-LOOP MODULES
%  ########################################################################

function addHighResExcitation(seq, e, p, slicePos, tridLabel, linLabel) %#ok<INUSD>

% HIGH-RESOLUTION EXCITATION MODULE
% -------------------------------------------------------------------------
% Pulseq blocks created:
%
%   1. RF + slice-select gradient
%   2. explicit RF ringdown wait
%   3. slice rephasing gradient
%
% This module is intentionally separate from the readout. In the GE/TOPPE
% conversion this tends to produce cleaner parent-block structure.
e.rf.freqOffset = e.gz.amplitude * slicePos;           % AK0805: added rf offset for multi-slice
seq.addBlock(e.rf, e.gz, tridLabel, linLabel);

% Explicit RF ringdown wait. This was 200 us in the working/debug version.
% If pge2.check reports that RF ringdown extends beyond the segment, this
% block is the first thing to review together with psd_rf_wait.
% seq.addBlock(mr.makeDelay(200e-6));

seq.addBlock(e.gzReph);

end

function addHighResReadout(seq, e, p, interleaf)

% HIGH-RESOLUTION READOUT MODULE
% -------------------------------------------------------------------------
% Pulseq block created:
%
%   spiral gx + spiral gy + ADC + TRID + LIN
%
% This block ALWAYS contains ADC. Do not use this same module for dummy
% scans without ADC; create a separate dummy module if needed.
% GE/pulseg note:
%   TRID/LIN labels are deliberately NOT placed here.
%   They are placed on the RF excitation block at the start of the TR.


seq.addBlock(e.gx, e.gy, e.adc);

end

function addHighResSpoilAndTRDelay(seq, e)

% HIGH-RESOLUTION SPOILER/TR MODULE
% -------------------------------------------------------------------------
% Pulseq block created:
%
%   z spoiler + delay to complete TR
%
% This keeps the readout block simple and makes the scan loop easier to
% inspect. It also avoids hiding readout timing inside a combined block.

seq.addBlock(e.gz_spoil, mr.makeDelay(e.delayTR));

end

% AK: 0713 for dummy readout
function addHighResDummyReadout(seq, e, p)
    % No adc for dummies
    seq.addBlock(e.gx, e.gy);

end

function addB0Excitation(seq, e, p, slicePos, trid) %#ok<INUSD>

% B0 EXCITATION MODULE
% -------------------------------------------------------------------------
% Pulseq blocks created:
%
%   1. B0 RF + B0 slice-select gradient
%   2. B0 slice rephaser
%
% This mirrors the high-resolution excitation module but uses the lower flip
% angle B0 RF event.
e.rf.freqOffset = e.gz.amplitude * slicePos;           % AK0805: added rf offset for multi-slice
tridLabelB0_1 = mr.makeLabel('SET', 'TRID', trid);
seq.addBlock(e.rfB0, e.gzB0, tridLabelB0_1);
seq.addBlock(e.gzRephB0);

end

function addB0TEReadout(seq, e, delayTE, trid)

% B0 TE DELAY + READOUT MODULE
% -------------------------------------------------------------------------
% Pulseq blocks created:
%
%   1. TE delay, if non-zero
%   2. B0 spiral gx + gy + ADC + TRID
%
% This block ALWAYS contains ADC. The only difference between TE1 and TE2 is
% the delay before the readout and the TRID label.

if delayTE > 0
    seq.addBlock(mr.makeDelay(delayTE));
end

% tridLabel = mr.makeLabel('SET', 'TRID', trid);
% seq.addBlock(e.gxB0, e.gyB0, e.adcB0, tridLabel);
seq.addBlock(e.gxB0, e.gyB0, e.adcB0);

end

function addB0SpoilAndTRDelay(seq, e, delayTR_B0)

% B0 SPOILER/TR MODULE
% -------------------------------------------------------------------------
% Pulseq block created:
%
%   B0 spoiler + delay to complete B0 TR
%
% The two B0 echoes can have different TE delays, so their remaining TR
% delays are calculated separately.

seq.addBlock(e.gzSpoilB0, mr.makeDelay(delayTR_B0));

end

%% ########################################################################
%  RF SPOILING
%  ########################################################################

function [e, rfState] = updateHighResRfSpoiling(e, rfState, p)

% RF spoiling is kept as a small state update so the scan-loop assembly
% remains readable. With p.rfSpoil=false, both RF and ADC phase offsets are
% reset to zero on every shot, matching the original code.

if p.rfSpoil
    e.rf.phaseOffset  = rfState.rf_phase/180*pi;
    e.adc.phaseOffset = rfState.rf_phase/180*pi;

    rfState.rf_inc   = mod(rfState.rf_inc + p.rfSpoilingInc, 360.0);
    rfState.rf_phase = mod(rfState.rf_phase + rfState.rf_inc, 360.0);
else
    e.rf.phaseOffset  = 0;
    e.adc.phaseOffset = 0;
end

end

%% ########################################################################
%  TIMING HELPERS
%  ########################################################################

function delayTR = calculateHighResTRDelay(p, e, sys)

TRmin = mr.calcDuration(e.rf_fs) ...
    + mr.calcDuration(mr.makeDelay(1e-4)) ...
    + mr.calcDuration(e.gz_fs_spoil) ...
    + mr.calcDuration(e.rf, e.gz) ...
    %+ mr.calcDuration(mr.makeDelay(200e-6)) ...
    + mr.calcDuration(e.gzReph) ...
    + mr.calcDuration(e.gx, e.gy, e.adc) ...
    + mr.calcDuration(e.gz_spoil);

TRmin = ceil(TRmin/sys.gradRasterTime) * sys.gradRasterTime;

if p.minTR
    delayTR = 0;
    fprintf('Minimum high-resolution TR = %.3f ms\n', TRmin*1e3);
else
    delayTR = p.TR - TRmin;
    fprintf('Selected high-resolution TR = %.3f ms\n', p.TR*1e3);
    fprintf('High-resolution TR delay = %.3f ms\n', delayTR*1e3);
end

if delayTR < 0
    error('High-resolution TR is too short by %.3f ms', -delayTR*1e3);
end

end

function delayTR_B0 = calculateB0TRDelay(p, e, delayTE_B0, sys)

TRminB0 = mr.calcDuration(e.rfB0, e.gzB0) ...
    + mr.calcDuration(e.gzRephB0) ...
    + delayTE_B0 ...
    + mr.calcDuration(e.gxB0, e.gyB0, e.adcB0) ...
    + mr.calcDuration(e.gzSpoilB0);

TRminB0 = ceil(TRminB0 / sys.gradRasterTime) * sys.gradRasterTime;

% The original code used the main sequence TR rather than TR_B0. That is
% preserved here for behavioural consistency.
delayTR_B0 = p.TR - TRminB0;

if delayTR_B0 < 0
    error('TR is too short for B0 shot by %.3f ms.', -delayTR_B0*1e3);
end

end

%% ########################################################################
%  TRAJECTORY FILE OUTPUT
%  ########################################################################

function measured = writeTrajectoryFiles(p, e)

measured = {};
% High-resolution reconstruction trajectory.
kADC_recon = e.high.kADC_s(1:e.high.nADC);
save('spiral_recon', 'kADC_recon');
kspace_file = fullfile(p.baseDir, [p.seq_name '.ksp']);

fid = fopen(kspace_file, 'wb');
if fid < 0
    error('Could not open k-space file for writing: %s', kspace_file);
end
cleanupObj = onCleanup(@() fclose(fid));
data = [real(kADC_recon);
    imag(kADC_recon)];          
fwrite(fid, data, 'double');
fclose(fid);
clear cleanupObj

fprintf('Wrote %d scaled high-resolution k-space samples to:\n%s\n', ...
    numel(kADC_recon), kspace_file);

kx = real(kADC_recon);
ky = imag(kADC_recon);
matrixPresc = p.Nx;
fov_mm = p.fov * 1000;
kx_cyc_per_mm = kx / 10;
ky_cyc_per_mm = ky / 10;
kabs_cyc_per_mm = sqrt(kx_cyc_per_mm.^2 + ky_cyc_per_mm.^2);

kmax_cyc_per_mm = max(kabs_cyc_per_mm);
kmax_expected_cyc_per_mm = matrixPresc / (2*fov_mm);
if kmax_cyc_per_mm > 0
    pixelSize_mm = 1/(2*kmax_cyc_per_mm);
    matrixMeasured = round(fov_mm/pixelSize_mm);
else
    pixelSize_mm = NaN;
    matrixMeasured = NaN;
end

fprintf([         'HR: Measured matrix equiv= %d x %d\n' ...
                  'Measured pixel       = %.2f mm\n' ...
                  'kmax measured        = %.4f cycles/mm\n' ...
                  'kmax expected        = %.4f cycles/mm'], ...
                  matrixMeasured, matrixMeasured, pixelSize_mm, ...
                  kmax_cyc_per_mm, kmax_expected_cyc_per_mm);

measured{end+1} = sprintf( ...
    'HR: Measured matrix equiv = %d x %d', ...
    matrixMeasured, matrixMeasured);

measured{end+1} = sprintf( ...
    'Measured pixel = %.2f mm', ...
    pixelSize_mm);

measured{end+1} = sprintf( ...
    'kmax measured = %.4f cycles/mm', ...
    kmax_cyc_per_mm);

measured{end+1} = sprintf( ...
    'kmax expected = %.4f cycles/mm', ...
    kmax_expected_cyc_per_mm);

% Optional B0 trajectory file.
if p.doB0Map
    % IMPORTANT: use the B0 ADC count, not the high-resolution ADC count.
    kADCB0_recon = e.b0.kADC_s(1:e.b0.nADC);

    B0kspace_file = fullfile(p.baseDir, [p.seq_name '.B0ksp']);

    fid = fopen(B0kspace_file, 'wb');
    if fid < 0
        error('Could not open B0 k-space file for writing: %s', B0kspace_file);
    end
    cleanupObj = onCleanup(@() fclose(fid));
    dataB0 = [real(kADCB0_recon);
    imag(kADCB0_recon)];          
    fwrite(fid, dataB0, 'double');
    clear cleanupObj

    fprintf('Wrote %d scaled B0 k-space samples to:\n%s\n', ...
        numel(kADCB0_recon), B0kspace_file);
    % AK: debug correctness
    kx = real(kADCB0_recon);
    ky = imag(kADCB0_recon);
    matrixPresc = p.Nx;
    fov_mm = p.fov * 1000;
    kx_cyc_per_mm = kx / 10;
    ky_cyc_per_mm = ky / 10;
    kabs_cyc_per_mm = sqrt(kx_cyc_per_mm.^2 + ky_cyc_per_mm.^2);
    
    kmax_cyc_per_mm = max(kabs_cyc_per_mm);
    kmax_expected_cyc_per_mm = matrixPresc / (2*fov_mm);
    if kmax_cyc_per_mm > 0
        pixelSize_mm = 1/(2*kmax_cyc_per_mm);
        matrixMeasured = round(fov_mm/pixelSize_mm);
    else
        pixelSize_mm = NaN;
        matrixMeasured = NaN;
    end
    
    fprintf([         'B0: Measured matrix equiv= %d x %d\n' ...
                      'Measured pixel       = %.2f mm\n' ...
                      'kmax measured        = %.4f cycles/mm\n' ...
                      'kmax expected        = %.4f cycles/mm'], ...
                      matrixMeasured, matrixMeasured, pixelSize_mm, ...
                      kmax_cyc_per_mm, kmax_expected_cyc_per_mm);

    measured{end+1} = sprintf( ...
    'B0: Measured matrix equiv = %d x %d', ...
    matrixMeasured, matrixMeasured);

    measured{end+1} = sprintf( ...
        'Measured pixel = %.2f mm', ...
        pixelSize_mm);
    
    measured{end+1} = sprintf( ...
        'kmax measured = %.4f cycles/mm', ...
        kmax_cyc_per_mm);
    
    measured{end+1} = sprintf( ...
        'kmax expected = %.4f cycles/mm', ...
        kmax_expected_cyc_per_mm);

end

end

%% ########################################################################
%  LOW-LEVEL NUMERICAL HELPERS
%  ########################################################################

function [gFull, nUp, nCore, nDown] = addComplexGradientRamps(gCore, SmaxVds, gradRasterTime)

% Add ramp-up and ramp-down sections to a complex spiral gradient in G/cm.
% The vds2 core waveform may not start/end at zero, so these sections make
% the arbitrary gradient event well behaved.

gStart = gCore(1);
gEnd   = gCore(end);

nRampUpTarget   = max(2, ceil(abs(gStart) / (SmaxVds * gradRasterTime)));
nRampDownTarget = max(2, ceil(abs(gEnd)   / (SmaxVds * gradRasterTime)));

rampUp = (0:(nRampUpTarget-1)) / nRampUpTarget * gStart;
rampUp = rampUp(2:end);  

rampDown = (nRampDownTarget-1:-1:0) / nRampDownTarget * gEnd;
rampDown = rampDown(1:end);       % AK: 2 to 1

nUp   = numel(rampUp);
nCore = numel(gCore);
nDown = numel(rampDown);

gFull = [rampUp, gCore, rampDown];

end

function [scale, gScaled] = scaleComplexGradientToSystem(gComplexHzPerM, sys)

% Scale a complex gx+i*gy waveform so both gradient amplitude and slew rate
% remain within the Pulseq system limits. The 0.99 factor gives a small
% safety margin against floating-point/raster rounding issues.

dt = sys.gradRasterTime;

scaleG = sys.maxGrad / max(abs(gComplexHzPerM));
scaleS = sys.maxSlew / max(abs(diff(gComplexHzPerM)/dt));

scale = 0.99 * min([scaleG, scaleS, 1]);

gScaled = scale * gComplexHzPerM;

fprintf('scaleG = %.4f\n', scaleG);
fprintf('scaleS = %.4f\n', scaleS);

end

function tf = hasEvent(block, fieldName)

tf = isfield(block, fieldName) && ~isempty(block.(fieldName));

end

function rf = padRfWithZeros(rf, padTime)

%pge2.check() is probably using the RF waveform duration, not the slice-select gradient duration. So extending gz is not enough.
% Pad the RF pulse itself with trailing zeros.

    if padTime <= 0
        return
    end

    dt = rf.t(2) - rf.t(1);
    nPad = ceil(padTime / dt);

    rf.signal = [rf.signal(:); zeros(nPad,1)];

    tExtra = rf.t(end) + dt*(1:nPad);
    rf.t = [rf.t(:); tExtra(:)];

    if isfield(rf,'shape_dur')
        rf.shape_dur = rf.shape_dur + nPad*dt;
    end

end