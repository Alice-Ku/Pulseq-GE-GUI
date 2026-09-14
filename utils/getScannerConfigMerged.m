function hw = getScannerConfigMerged(configInput)
% =========================================================================
% getScannerConfigMerged
% =========================================================================
%
% Supports:
%
%   1) Single filename
%        hw = getScannerConfig_modified('scanner.cvs')
%
%   2) Cell array of filenames
%        hw = getScannerConfig_modified({'a.cfg','b.cfg'})
%
%   3) Merged struct of raw config values
%        hw = getScannerConfig_modified(app.MergedCV)
%
% Returns final scanner hardware struct `hw`
% =========================================================================

% -------------------------------------------------------------------------
% INPUT HANDLING
% -------------------------------------------------------------------------
    baseName = 'MergedConfig';
    cvsFile  = '';
    
    if isstruct(configInput)
    
        % Already merged raw config values
        cv = configInput;
    
    elseif ischar(configInput) || isstring(configInput)
    
        cvsFile = char(configInput);
    
        if ~isfile(cvsFile)
            error('getScannerConfig:FileNotFound', ...
                'File not found: %s', cvsFile);
        end
    
        [~, baseName] = fileparts(cvsFile);
    
        cv = parseCvsKeyValueFileFlexible(cvsFile);
    
    elseif iscell(configInput)
    
        if isempty(configInput)
            error('getScannerConfig:EmptyInput', ...
                'Filename list is empty.');
        end
    
        % Use first filename for metadata
        firstFile = char(configInput{1});
    
        if isfile(firstFile)
            [~, baseName] = fileparts(firstFile);
        end
    
        cv = struct();
    
        for k = 1:numel(configInput)
    
            thisFile = char(configInput{k});
    
            if ~isfile(thisFile)
                error('getScannerConfig:FileNotFound', ...
                    'File not found: %s', thisFile);
            end
    
            cvPart = parseCvsKeyValueFileFlexible(thisFile);
    
            % Later files override earlier files
            cv = mergeStructs(cv, cvPart);
    
        end
    
    else
    
        error('getScannerConfig:BadInput', ...
            'Unsupported input type.');
    
    end
    
    % -------------------------------------------------------------------------
    % FILENAME METADATA (optional)
    % -------------------------------------------------------------------------
    pat = ['^(?<fieldStrength>[0-9.]+T)\.SR(?<slewMode>[0-9]+)\.' ...
           '(?<gradCoil>[^._]+)_(?<gradAmp>[^._]+)$'];
    
    tok = regexp(baseName, pat, 'names');
    
    if isempty(tok)
        tok = struct( ...
            'fieldStrength','', ...
            'slewMode','', ...
            'gradCoil','UNKNOWN', ...
            'gradAmp','UNKNOWN');
    end    
    % -------------------------------------------------------------------------
    % INITIALISE OUTPUT
    % -------------------------------------------------------------------------
    hw = struct();
    
    hw.sourceFile     = cvsFile;
    hw.sourceBaseName = baseName;
    hw.sourceType     = 'GE scanner config';
    hw.rawCV          = cv;
    
    hw.fieldStrengthLabel = tok.fieldStrength;
    hw.slewModeLabel      = ['SR' tok.slewMode];
    hw.coil               = mapCvsCoilToPge2Coil(tok.gradCoil);
    hw.gradAmpTypeLabel   = tok.gradAmp;
    hw.gradCoilTypeLabel  = tok.gradCoil;

        % ---------------------------------------------------------
        % Recover coil type from config contents if filename failed
        % ---------------------------------------------------------
        if strcmpi(hw.coil,'UNKNOWN') || isempty(hw.coil)
        
            commentText = '';
        
            if isfield(cv,'comment_com')
                commentText = upper(cv.comment_com);
            end
        
            if contains(commentText,'HRMW')
                hw.coil = 'HRMW';
        
            elseif contains(commentText,'HRMB')
                hw.coil = 'HRMB';
        
            elseif contains(commentText,'XRMB')
                hw.coil = 'XRMB';
        
            elseif contains(commentText,'MAGNUS')
                hw.coil = 'MAGNUS';
        
            else
                % fallback from numeric type
                if isfield(cv,'GCoilType')
                    gtype = str2double(cv.GCoilType);
        
                    switch gtype
                        case 13
                            hw.coil = 'HRMW';
                        otherwise
                            hw.coil = 'HRMW'; % safe default
                    end
                end
            end
        end
    
    % -------------------------------------------------------------------------
    % FIELD STRENGTH
    % -------------------------------------------------------------------------
    defaultB0 = str2double(strrep(tok.fieldStrength,'T',''));
    
    if isnan(defaultB0)
        defaultB0 = NaN;
    end
    
    hw.B0_T = getNumericCVAny(cv, ...
        {'fieldStrength','FieldStrength','B0'}, ...
        defaultB0);
    if isnan(hw.B0_T) || hw.B0_T == 0
        if isfield(cv,'fieldStrength')
            hw.B0_T = str2double(cv.fieldStrength)/10000;
        end
    end
    % -------------------------------------------------------------------------
    % SLEW RATE
    % -------------------------------------------------------------------------
    defaultSlew = str2double(tok.slewMode);
    
    if isnan(defaultSlew)
        defaultSlew = NaN;
    end
    
    hw.maxSlew_Tms = getNumericCVAny(cv, ...
        {'cfsrmodeact','SRMode','peakSRMode'}, ...
        defaultSlew);
    
    % -------------------------------------------------------------------------
    % GRADIENT AMPLITUDE
    % -------------------------------------------------------------------------
    gx_fs_Gpcm = getNumericCVAny(cv, ...
        {'cfxfs','xFSAmp','peakFSAmp'}, NaN);
    
    gy_fs_Gpcm = getNumericCVAny(cv, ...
        {'cfyfs','yFSAmp','peakFSAmp'}, NaN);
    
    gz_fs_Gpcm = getNumericCVAny(cv, ...
        {'cfzfs','zFSAmp','peakFSAmp'}, NaN);
    
    hw.gradFullScale_Gpcm = [gx_fs_Gpcm gy_fs_Gpcm gz_fs_Gpcm];
    
    hw.maxGrad_Gpcm = max(hw.gradFullScale_Gpcm, [], 'omitnan');
    hw.maxGrad_mTm  = hw.maxGrad_Gpcm * 10;
    
    % -------------------------------------------------------------------------
    % TIMING
    % -------------------------------------------------------------------------
    hw.psd_grd_wait_us = getNumericCVAny(cv, ...
        {'psd_grd_wait','psdGradWait'}, NaN);
    
    hw.psd_rf_wait_us = getNumericCVAny(cv, ...
        {'psd_rf_wait','psdRfWait'}, NaN);
    
    hw.psd_grd_wait_s = hw.psd_grd_wait_us * 1e-6;
    hw.psd_rf_wait_s  = hw.psd_rf_wait_us  * 1e-6;
    
    % -------------------------------------------------------------------------
    % GRADIENT DELAYS
    % -------------------------------------------------------------------------
    hw.gradDelay_x_us = getNumericCVAny(cv, ...
        {'cfxrdelay','psdGradDelayX'}, NaN);
    
    hw.gradDelay_y_us = getNumericCVAny(cv, ...
        {'cfyrdelay','psdGradDelayY'}, NaN);
    
    hw.gradDelay_z_us = getNumericCVAny(cv, ...
        {'cfzrdelay','psdGradDelayZ'}, NaN);
    
    hw.gradDelay_x_s = hw.gradDelay_x_us * 1e-6;
    hw.gradDelay_y_s = hw.gradDelay_y_us * 1e-6;
    hw.gradDelay_z_s = hw.gradDelay_z_us * 1e-6;
    
    % -------------------------------------------------------------------------
    % dB/dt
    % -------------------------------------------------------------------------
    hw.dbdt_x = getNumericCVAny(cv, ...
        {'cfdbdtdx','dBdtDistx'}, NaN);
    
    hw.dbdt_y = getNumericCVAny(cv, ...
        {'cfdbdtdy','dBdtDisty'}, NaN);
    
    hw.dbdt_z = getNumericCVAny(cv, ...
        {'cfdbdtdz','dBdtDistz'}, NaN);
    
    % -------------------------------------------------------------------------
    % RF LIMITS
    % -------------------------------------------------------------------------
    hw.maxB1RMS_head_uT = getNumericCVAny(cv, ...
        {'cfmaxb1rmshead','maxB1RMS'}, NaN);
    
    % -------------------------------------------------------------------------
    % FIXED DEFAULTS
    % -------------------------------------------------------------------------
    hw.rfDeadTime_s      = 72e-6;
    hw.rfRingdownTime_s  = 56e-6;
    hw.adcDeadTime_s     = 40e-6;
    hw.adcRingdownTime_s = 0;
    
    hw.gradRasterTime_s = 4e-6;
    hw.adcRasterTime_s  = 2e-6;
    hw.rfRasterTime_s   = 4e-6;
    hw.blockDurationRaster_s = 4e-6;
    
    hw.segmentDeadTime_s     = 12e-6;
    hw.segmentRingdownTime_s = 105e-6;
    
    hw.b1_max_G = 0.25;
    
    % -------------------------------------------------------------------------
    % EXTRA VALUES
    % -------------------------------------------------------------------------
    hw.gCoilType = getNumericCVAny(cv, ...
        {'GCoilType'}, NaN);
    
    hw.peakSRMode_Tms = getNumericCVAny(cv, ...
        {'peakSRMode'}, NaN);
    
    hw.peakGrad_Gpcm = getNumericCVAny(cv, ...
        {'peakFSAmp'}, NaN);
    
    % -------------------------------------------------------------------------
    % NAME
    % -------------------------------------------------------------------------
    if ~isnan(hw.B0_T)
        b0Label = sprintf('%.1fT', hw.B0_T);
    else
        b0Label = 'UnknownField';
    end
    
    hw.name = sprintf('GE %s', b0Label);
    hw.vendor = 'GE';
    hw.configName = baseName;
    
    % -------------------------------------------------------------------------
    % WARNINGS
    % -------------------------------------------------------------------------
    if isnan(hw.maxGrad_mTm)
        warning('Missing max gradient amplitude.');
    end
    
    if isnan(hw.maxSlew_Tms)
        warning('Missing max slew.');
    end
    
    % =========================================================================
    % HELPERS
    % =========================================================================
    function cv = parseCvsKeyValueFileFlexible(cvsFile)
    
        fid = fopen(cvsFile,'rt');
        
        if fid < 0
            error('Could not open file.');
        end
        
        cleanupObj = onCleanup(@() fclose(fid));
        
        cv = struct();
        
        while true
        
            line = fgetl(fid);
        
            if ~ischar(line)
                break;
            end
        
            line = strtrim(line);
        
            if isempty(line)
                continue;
            end
        
            if startsWith(line,'#') || ...
               startsWith(line,'%') || ...
               startsWith(line,'//')
                continue;
            end
        
            tok = regexp(line, ...
                '^(?<key>[A-Za-z0-9_\.]+)\s*=\s*"?(?<val>.*?)"?$', ...
                'names');
        
            if ~isempty(tok)
        
                key = matlab.lang.makeValidName(tok.key);
                cv.(key) = strtrim(tok.val);
                continue;
        
            end
        
            parts = regexp(line,'\s+','split');
        
            if numel(parts) >= 2
        
                key = matlab.lang.makeValidName(parts{1});
                cv.(key) = parts{2};
        
            end
        
        end
    
    end
    
    function val = getNumericCVAny(cv, keys, defaultVal)
    
        val = defaultVal;
        
        for i = 1:numel(keys)
        
            key = matlab.lang.makeValidName(keys{i});
        
            if isfield(cv,key)
        
                raw = cv.(key);
        
                if isnumeric(raw)
                    num = raw;
                else
                    num = str2double(raw);
                end
        
                if ~isnan(num)
                    val = num;
                    return;
                end
        
            end
        
        end
    
    end
    
    function out = mergeStructs(a,b)
    
        out = a;
        
        fn = fieldnames(b);
        
        for i = 1:numel(fn)
            out.(fn{i}) = b.(fn{i});
        end
        
    end
        
    function coil = mapCvsCoilToPge2Coil(label)
        
        label = char(label);
        
        if isempty(label)
            coil = 'UNKNOWN';
        else
            coil = upper(label);
        end
    
    end

end