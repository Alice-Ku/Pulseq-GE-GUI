function sys_ge = buildGESystem(hw)
% =========================================================================
% buildGESystem
% =========================================================================
%
% PURPOSE
% -------
% Build the GE backend system struct used by pge2 from a central scanner
% configuration struct returned by getScannerConfig(...).
%
% This converts the scanner facts into the units expected by:
%
%   pge2.opts(psd_rf_wait, psd_grd_wait, b1_max, g_max, slew_max, coil)
%
% INPUT
% -----
% hw : struct
%   Scanner configuration struct from getScannerConfig(...)
%
% OUTPUT
% ------
% sys_ge : struct
%   GE backend system struct returned by pge2.opts(...)
%
% UNIT CONVERSIONS
% ----------------
% Gradient amplitude:
%   1 G/cm = 10 mT/m
%   therefore:
%       g_max [G/cm] = maxGrad_mTm / 10
%
% Slew rate:
%   1 T/m/s = 0.1 G/cm/ms
%   therefore:
%       slew_max [G/cm/ms] = maxSlew_Tms / 10
%
% NOTES
% -----
% - This function uses the raw scanner capability values from hw.
% - It does NOT apply any Pulseq design policy such as oblique derating.
% - GE backend timing offsets such as psd_grd_wait and psd_rf_wait are
%   taken directly from hw.
%
% =========================================================================

% -------------------------------------------------------------------------
% Basic input checks
% -------------------------------------------------------------------------
requiredFields = { ...
    'psd_rf_wait_s', ...
    'psd_grd_wait_s', ...
    'b1_max_G', ...
    'maxGrad_mTm', ...
    'maxSlew_Tms', ...
    'coil'};

for k = 1:numel(requiredFields)
    if ~isfield(hw, requiredFields{k})
        error('buildGESystem:MissingField', ...
            'Input struct hw is missing required field: %s', requiredFields{k});
    end
end

% -------------------------------------------------------------------------
% Convert units for pge2.opts(...)
% -------------------------------------------------------------------------
g_max_Gpcm = hw.maxGrad_mTm / 10;
% Convert gradient amplitude from mT/m to G/cm.

slew_max_Gpcpms = hw.maxSlew_Tms / 10;
% Convert slew rate from T/m/s to G/cm/ms.

% -------------------------------------------------------------------------
% Build GE backend system struct
% -------------------------------------------------------------------------
sys_ge = pge2.opts( ...
    hw.psd_rf_wait_s, ...
    hw.psd_grd_wait_s, ...
    hw.b1_max_G, ...
    g_max_Gpcm, ...
    slew_max_Gpcpms, ...
    hw.coil);
% Build the GE backend system object used by pge2 for:
%   - timing checks
%   - amplitude/slew checks
%   - PNS calculations
%   - plotting
%   - validation
%
% The coil field must be a pge2-recognised coil name such as:
%   'xrm', 'xrmw', 'hrmw', 'whole', 'zoom', 'magnus', ...
%
% That mapping should already have been handled in getScannerConfig(...).

end