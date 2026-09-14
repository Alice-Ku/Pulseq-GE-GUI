function [kGrad,g,s,tGrad,kADC,tADC,info] = ...
    vds2(smax,gmax,Tgrad,N,Fcoeff,rmax,desiredADCSamples,Tadc)
% VDS  Variable-density spiral generator.
%
% Generates:
%   kGrad : k-space trajectory on gradient raster
%   g     : gradient waveform on gradient raster
%   s     : slew waveform on gradient raster
%   kADC  : ADC/reconstruction trajectory on ADC raster
%
% Units:
%   smax   G/cm/s
%   gmax   G/cm
%   Tgrad  s
%   Tadc   s
%   FOV    cm
%   k      cm^-1
%   rmax   cm^-1

fprintf('vds.m\n');

gamma   = 4258;      % Hz/G
oversamp = 4;        % internal integration oversampling
Tos     = Tgrad/oversamp;

if nargin < 7
    desiredADCSamples = [];
end

if nargin < 8 || isempty(Tadc)
    Tadc = Tgrad;
end

if Tadc <= 0 || Tgrad <= 0
    error('vds:BadRaster','Tgrad and Tadc must be positive.');
end

if ~isempty(desiredADCSamples)

    validateattributes(desiredADCSamples,{'numeric'}, ...
        {'scalar','integer','positive'},mfilename,'desiredADCSamples');

    readoutDuration = (desiredADCSamples - 1) * Tadc;

    desiredGradSamples = floor(readoutDuration / Tgrad) + 1;

else

    desiredGradSamples = [];

end


%% Choose design gmax
gDesign = gmax;

% if isempty(desiredGradSamples)
% 
%     gDesign = gmax;
% 
% else
% 
%     validateattributes(desiredGradSamples,{'numeric'}, ...
%         {'scalar','integer','positive'},mfilename,'desiredGradSamples');
% 
%     % Test whether full gmax can reach rmax in the requested time.
%     rawTest = integrateSpiral( ...
%         smax,gmax,Tgrad,Tos,N,Fcoeff,rmax,oversamp,desiredGradSamples);
% 
%     if rawTest.rGrad(end) < rmax
%         error('vds:CannotReachRmax', ...
%             ['Cannot reach rmax within %d gradient samples.\n' ...
%              'Final radius = %.6f cm^-1, target = %.6f cm^-1.\n' ...
%              'Increase desiredGradSamples, increase gmax/smax, or reduce rmax.'], ...
%              desiredGradSamples,rawTest.rGrad(end),rmax);
%     end
% 
%     % Bisection on effective gmax so final k-space radius lands on rmax.
%     % Binary search to find the gradient limit
%     gLow  = 0;
%     gHigh = gmax;
% 
%     tol     = max(1e-6*rmax,1e-9);
%     maxIter = 60;
% 
%     for iter = 1:maxIter
% 
%         gMid = 0.5*(gLow + gHigh);
% 
%         rawMid = integrateSpiral( ...
%             smax,gMid,Tgrad,Tos,N,Fcoeff,rmax,oversamp,desiredGradSamples);
% 
%         if rawMid.rGrad(end) < rmax
%             gLow = gMid;
%         else
%             gHigh = gMid;
%         end
% 
%         if abs(rawMid.rGrad(end) - rmax) < tol
%             break
%         end
%     end
% 
%     gDesign = gHigh;
% 
% end

%% Final integration

raw = integrateSpiral( ...
    smax,gDesign,Tgrad,Tos,N,Fcoeff,rmax,oversamp,desiredGradSamples);


kGrad = raw.kGrad;
tGrad = raw.tGrad;

%% Gradient and slew on gradient raster

g = gradientFromK(kGrad,Tgrad,gamma);
s = slewFromG(g,Tgrad);

%% ADC trajectory

[kADC,tADC] = adcTrajectoryFromOversampled(raw.kOS,raw.tOS,Tadc,desiredADCSamples);

%% Resolution

kmaxGrad = max(abs(kGrad));
kmaxADC  = max(abs(kADC));

nominalResolution_cm = 1/(2*rmax);
nominalResolution_mm = 10*nominalResolution_cm;

actualResolutionGrad_cm = 1/(2*kmaxGrad);
actualResolutionGrad_mm = 10*actualResolutionGrad_cm;

actualResolutionADC_cm = 1/(2*kmaxADC);
actualResolutionADC_mm = 10*actualResolutionADC_cm;

%% Info structure

info = struct();

info.gamma = gamma;
info.oversamp = oversamp;

info.Tgrad = Tgrad;
info.Tadc  = Tadc;
info.Tos   = Tos;

info.smax = smax;
info.gmaxInput  = gmax;
info.gmaxDesign = gDesign;

info.Fcoeff = Fcoeff;
info.Ninterleaves = N;

info.rmaxTarget = rmax;
info.kmaxGrad = kmaxGrad;
info.kmaxADC  = kmaxADC;

info.nominalResolution_cm = nominalResolution_cm;
info.nominalResolution_mm = nominalResolution_mm;

info.actualResolutionGrad_cm = actualResolutionGrad_cm;
info.actualResolutionGrad_mm = actualResolutionGrad_mm;

info.actualResolutionADC_cm = actualResolutionADC_cm;
info.actualResolutionADC_mm = actualResolutionADC_mm;

info.nGradSamples = numel(kGrad);
info.nADCSamples  = numel(kADC);

info.readoutDuration_s  = tGrad(end);
info.readoutDuration_ms = 1e3*tGrad(end);

info.maxGradient_G_per_cm = max(abs(g));
info.maxSlew_G_per_cm_per_s = max(abs(s));

%% Print summary

fprintf('\n--- Spiral summary ---\n');
fprintf('Gradient raster              %.3f us\n',1e6*Tgrad);
fprintf('ADC/recon raster             %.3f us\n',1e6*Tadc);
fprintf('Internal integration raster  %.3f us\n',1e6*Tos);
fprintf('Gradient samples             %d\n',numel(kGrad));
fprintf('ADC/recon samples            %d\n',numel(kADC));
fprintf('Readout duration             %.3f ms\n',1e3*tGrad(end));
fprintf('Target rmax                  %.6f cm^-1\n',rmax);
fprintf('Achieved kmax grad           %.6f cm^-1\n',kmaxGrad);
fprintf('Achieved kmax ADC            %.6f cm^-1\n',kmaxADC);
fprintf('Nominal resolution           %.3f mm\n',nominalResolution_mm);
fprintf('Actual resolution grad       %.3f mm\n',actualResolutionGrad_mm);
fprintf('Actual resolution ADC        %.3f mm\n',actualResolutionADC_mm);
fprintf('Input gmax                   %.6f G/cm\n',gmax);
fprintf('Design gmax                  %.6f G/cm\n',gDesign);
fprintf('Actual max |G|               %.6f G/cm\n',max(abs(g)));
fprintf('Actual max |S|               %.6f G/cm/s\n',max(abs(s)));
fprintf('----------------------\n\n');

end

%% ========================================================================
% Internal spiral integration
% ========================================================================

function raw = integrateSpiral( ...
    smax,gmax,Tgrad,Tos,N,Fcoeff,rmax,oversamp,desiredGradSamples)

q0 = 0;
q1 = 0;
r0 = 0;
r1 = 0;
t  = 0;

if isempty(desiredGradSamples)
    maxInternalPoints = 1000000;
else
    maxInternalPoints = desiredGradSamples * oversamp + oversamp;
end

thetaOS = zeros(1,maxInternalPoints);
rOS     = zeros(1,maxInternalPoints);
tOS     = zeros(1,maxInternalPoints);

thetaOS(1) = q0;
rOS(1)     = r0;
tOS(1)     = t;

count = 1;

while true

    [q2,r2] = findq2r2(smax,gmax,r0,r1,Tos,Tgrad,N,Fcoeff,rmax);

    q1 = q1 + q2*Tos;
    q0 = q0 + q1*Tos;

    r1 = r1 + r2*Tos;
    r0 = r0 + r1*Tos;

    t = t + Tos;

    count = count + 1;

    if count > maxInternalPoints
        error('vds:InternalArrayExceeded', ...
            'Internal trajectory exceeded allocated length.');
    end

    thetaOS(count) = q0;
    rOS(count)     = r0;
    tOS(count)     = t;

    if isempty(desiredGradSamples)
        if r0 >= rmax
            break
        end
    else
        if count >= desiredGradSamples*oversamp
            break
        end
    end
end

thetaOS = thetaOS(1:count);
rOS     = rOS(1:count);
tOS     = tOS(1:count);

kOS = rOS .* exp(1i*thetaOS);

% Gradient raster samples are taken from the oversampled integrated spiral.
idxGrad = oversamp/2:oversamp:count;

rGrad     = rOS(idxGrad);
thetaGrad = thetaOS(idxGrad);
tGrad     = tOS(idxGrad);
kGrad     = kOS(idxGrad);

if isempty(desiredGradSamples)

    % Preserve Brian's original multiple-of-four convention.
    nKeep = 4*floor(numel(kGrad)/4);

    rGrad     = rGrad(1:nKeep);
    thetaGrad = thetaGrad(1:nKeep);
    tGrad     = tGrad(1:nKeep);
    kGrad     = kGrad(1:nKeep);

else

    rGrad     = rGrad(1:desiredGradSamples);
    thetaGrad = thetaGrad(1:desiredGradSamples);
    tGrad     = tGrad(1:desiredGradSamples);
    kGrad     = kGrad(1:desiredGradSamples);

end

raw = struct();
raw.rOS = rOS;
raw.thetaOS = thetaOS;
raw.tOS = tOS;
raw.kOS = kOS;

raw.rGrad = rGrad;
raw.thetaGrad = thetaGrad;
raw.tGrad = tGrad;
raw.kGrad = kGrad;

end

%% ========================================================================
% Derive gradient waveform from k-space
% ========================================================================

function g = gradientFromK(k,T,gamma)

% Forward difference, same length as k.
dk = diff(k);

g = zeros(size(k));
g(1:end-1) = dk/(gamma*T);
g(end) = g(end-1);

end


%% ========================================================================
% Derive slew waveform from gradient
% ========================================================================

function s = slewFromG(g,T)

dg = diff(g);

s = zeros(size(g));
s(1:end-1) = dg/T;
s(end) = s(end-1);

end

%% ========================================================================
% ADC trajectory from oversampled trajectory
% ========================================================================

function [kADC,tADC] = adcTrajectoryFromOversampled(kOS,tOS,Tadc,desiredADCSamples)

if isempty(desiredADCSamples)
    tADC = 0:Tadc:tOS(end);
else
    tADC = (0:desiredADCSamples-1) * Tadc;
end

dtOS = tOS(2)-tOS(1);

kADC = interp1(tOS,kOS,tADC,'pchip','extrap');

end

%% ========================================================================
% Brian Hargreaves variable-density update
% ========================================================================

function [q2,r2] = findq2r2(smax,gmax,r,r1,T,Ts,N,Fcoeff,rmax)

gamma = 4258;  % Hz/G

F = 0;
dFdr = 0;

for rind = 1:length(Fcoeff)

    F = F + Fcoeff(rind)*(r/rmax)^(rind-1);

    if rind > 1
        dFdr = dFdr + ...
            (rind-1)*Fcoeff(rind)*(r/rmax)^(rind-2)/rmax;
    end
end

if F <= 0
    error('vds:BadFOV', ...
        'FOV polynomial became non-positive: F = %.6f cm at r = %.6f.', ...
        F,r);
end

GmaxFOV = 1/gamma/F/Ts;
Gmax = min(GmaxFOV,gmax);

maxr1 = sqrt((gamma*Gmax)^2 / (1+(2*pi*F*r/N)^2));

if r1 > maxr1

    % Gradient amplitude limited.
    r2 = (maxr1-r1)/T;

else

    twopiFoN  = 2*pi*F/N;
    twopiFoN2 = twopiFoN^2;

    A = 1 + twopiFoN2*r*r;

    B = 2*twopiFoN2*r*r1*r1 + ...
        2*twopiFoN2/F*dFdr*r*r*r1*r1;

    C = twopiFoN2^2*r*r*r1^4 + ...
        4*twopiFoN2*r1^4 + ...
        (2*pi/N*dFdr)^2*r*r*r1^4 + ...
        4*twopiFoN2/F*dFdr*r*r1^4 - ...
        gamma^2*smax^2;

    rts = qdf(A,B,C);

    r2 = real(rts(1));

    slew = 1/gamma*( ...
        r2 - twopiFoN2*r*r1^2 + ...
        1i*twopiFoN*(2*r1^2 + r*r2 + dFdr/F*r*r1^2));

    sr = abs(slew)/smax;

    if sr > 1.01
        fprintf(['Slew violation: slew = %.3f G/cm/s, ' ...
                 'smax = %.3f G/cm/s, ratio = %.3f, ' ...
                 'r = %.6f, r1 = %.6f\n'], ...
                 abs(slew),smax,sr,r,r1);
    end

end

q2 = 2*pi/N*dFdr*r1^2 + 2*pi*F/N*r2;

end

%% ========================================================================
% Quadratic formula
% ========================================================================

function rootsOut = qdf(a,b,c)

d = b^2 - 4*a*c;

if d < 0 && abs(d) < 1e-10
    d = 0;
end

rootsOut(1) = (-b + sqrt(d))/(2*a);
rootsOut(2) = (-b - sqrt(d))/(2*a);

end