function sys = buildPulseqSystem(hw, varargin)
% =========================================================================
% buildPulseqSystem
% =========================================================================
%
% PURPOSE
% -------
% Build the Pulseq design system object (mr.opts) from a central scanner
% configuration struct.
%
% This function decides what to pass into mr.opts(...).
%
% It is deliberately separate from getScannerConfig(...) because:
%   - the scanner has raw physical limits
%   - the sequence designer may choose a design policy
%
% For example:
%   - use full gradient capability
%   - use a 1/sqrt(3) oblique safety margin
%   - use real dead times
%   - force dead times to zero for cleaner sequence design
%
% INPUTS
% ------
% hw : struct
%   Scanner configuration returned by getScannerConfig(...)
%
% Name-value options:
%   'UseObliqueMargin' : true/false
%       If true, apply 1/sqrt(3) scaling to maxGrad and maxSlew.
%       Default = true
%
%   'UseRealDeadTimes' : true/false
%       If true, use the dead/ringdown times from hw.
%       If false, set RF/ADC dead and ringdown times to zero.
%       Default = false
%
% OUTPUT
% ------
% sys : Pulseq system object created by mr.opts(...)
%
% =========================================================================

% Defaults
opt.UseObliqueMargin = true;
opt.UseRealDeadTimes = false;

% Parse varargin manually
if mod(numel(varargin),2) ~= 0
    error('Options must be supplied as name-value pairs.');
end

for k = 1:2:numel(varargin)
    name = varargin{k};
    value = varargin{k+1};

    switch lower(name)
        case 'useobliquemargin'
            opt.UseObliqueMargin = logical(value);
        case 'userealdeadtimes'
            opt.UseRealDeadTimes = logical(value);
        otherwise
            error('Unknown option: %s', name);
    end
end

% -------------------------------------------------------------------------
% Design policy: optionally reduce gradient capability for oblique use
% -------------------------------------------------------------------------
scale = 1;
if opt.UseObliqueMargin
    scale = 1/sqrt(3);
end

maxGrad_mTm = hw.maxGrad_mTm * scale;
maxSlew_Tms = hw.maxSlew_Tms * scale;

% -------------------------------------------------------------------------
% Decide whether to use real dead/ringdown times or zero them
% -------------------------------------------------------------------------
if opt.UseRealDeadTimes
    rfDeadTime      = hw.rfDeadTime_s;
    rfRingdownTime  = hw.rfRingdownTime_s;
    adcDeadTime     = hw.adcDeadTime_s;
else
    rfDeadTime      = 0;
    rfRingdownTime  = 0;
    adcDeadTime     = 0;
end

% -------------------------------------------------------------------------
% Build Pulseq system object
% -------------------------------------------------------------------------
sys = mr.opts( ...
    'maxGrad', maxGrad_mTm, 'gradUnit', 'mT/m', ...
    'maxSlew', maxSlew_Tms, 'slewUnit', 'T/m/s', ...
    'rfDeadTime', rfDeadTime, ...
    'rfRingdownTime', rfRingdownTime, ...
    'adcDeadTime', adcDeadTime, ...
    'adcRasterTime', hw.adcRasterTime_s, ...
    'rfRasterTime', hw.rfRasterTime_s, ...
    'gradRasterTime', hw.gradRasterTime_s, ...
    'blockDurationRaster', hw.blockDurationRaster_s, ...
    'B0', hw.B0_T);
end