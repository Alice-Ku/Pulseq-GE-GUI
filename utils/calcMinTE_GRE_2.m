function [TEmin, TEmin_quantised, breakdown] = calcMinTE_GRE_2( ...
    tRFcentre, gz, gzReph, gxPre, gx, seq, tDead)

% =========================================================================
% calcMinTE_GRE_2
% =========================================================================
%
% PURPOSE
% -------
% Calculate the minimum TE for a Cartesian GRE sequence from the timing of
% the sequence building blocks.
%
% This function assumes TE is measured from the RF centre to the centre of
% the readout, with the readout centre defined as:
%
%   gx.riseTime + gx.flatTime/2
%
% That is more accurate for Cartesian GRE than using half the total
% readout trapezoid duration.
%
% INPUTS
% ------
% tRFcentre  : time from RF start to RF centre (s)
% gz         : slice-select gradient
% gzReph     : slice rephasing gradient
% gxPre      : readout prephaser
% gx         : readout gradient
% seq        : Pulseq sequence object (used for raster quantisation)
% tDead      : optional extra timing offset (s)
%
% OUTPUTS
% -------
% TEmin             : continuous minimum TE before quantisation
% TEmin_quantised   : TE snapped upward to seq.gradRasterTime
% breakdown         : struct containing individual timing contributions
%
% NOTE
% ----
% In the ideal Pulseq design workflow, use:
%   tDead = 0
%
% If you later want to estimate a GE-effective TE, you may choose to use a
% backend timing offset such as:
%   tDead = sys_ge.psd_grd_wait
%
% =========================================================================

if nargin < 7
    tDead = 0;
end

% Slice-select gradient fall time after RF excitation
t_gz_fall = gz.fallTime;

% Duration of slice rephasing gradient
t_gzReph  = mr.calcDuration(gzReph);

% Duration of readout prephasing gradient
t_gxPre   = mr.calcDuration(gxPre);

% Time from start of readout block to k-space centre
t_read_centre = gx.riseTime + gx.flatTime/2;

% In the prephasing block, gzReph and gxPre run in parallel, so the true
% block duration is the longer of the two.
t_pre = max(t_gzReph, t_gxPre);

% Continuous minimum TE
TEmin = tRFcentre ...
      + t_gz_fall ...
      + t_pre ...
      + t_read_centre ...
      + tDead;

% Quantise upward to the gradient raster
TEmin_quantised = ceil(TEmin / seq.gradRasterTime) ...
                * seq.gradRasterTime;

% Return detailed breakdown for debugging / teaching
breakdown = struct( ...
    'tRFcentre',      tRFcentre, ...
    'gz_fall',        t_gz_fall, ...
    'gzReph',         t_gzReph, ...
    'gxPre',          t_gxPre, ...
    'pre_block',      t_pre, ...
    'readout_centre', t_read_centre, ...
    'tDead',          tDead);

end