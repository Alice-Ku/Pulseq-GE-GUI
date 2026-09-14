function lines = showScannerConfigToFile(hw, filename)
% =========================================================================
% showScannerConfigToFile
% =========================================================================
% Writes scanner configuration summary to a text file
% AND returns lines for GUI display
% AK asked ChatGPT to convert showSCannerConfig to this for the GUI
% =========================================================================

    % Open file
    fid = fopen(filename, 'w');
    if fid == -1
        error('Could not open file: %s', filename);
    end

    % NEW: storage for GUI
    lines = strings(0);

    % UPDATED helper: write + store
    function writeLine(fmt, varargin)
        line = sprintf(fmt, varargin{:});   % create formatted string
        fprintf(fid, '%s\n', line);         % write to file
        lines(end+1,1) = string(line);      % store for GUI
    end

    % ---------------------------------------------------------------------
    writeLine('============================================================');
    writeLine('Scanner configuration summary');
    writeLine('============================================================');

    % ---------------------------------------------------------------------
    % Source information
    % ---------------------------------------------------------------------
    if isfield(hw, 'sourceFile')
        writeLine('Source file           : %s', hw.sourceFile);
    end
    if isfield(hw, 'sourceType')
        writeLine('Source type           : %s', hw.sourceType);
    end
    if isfield(hw, 'configName')
        writeLine('Config name           : %s', hw.configName);
    end
    if isfield(hw, 'name')
        writeLine('Display name          : %s', hw.name);
    end
    if isfield(hw, 'vendor')
        writeLine('Vendor                : %s', hw.vendor);
    end

    writeLine('------------------------------------------------------------');

    % ---------------------------------------------------------------------
    % Metadata
    % ---------------------------------------------------------------------
    if isfield(hw, 'fieldStrengthLabel')
        writeLine('Field strength label  : %s', hw.fieldStrengthLabel);
    end
    if isfield(hw, 'B0_T')
        writeLine('Field strength        : %.3f T', hw.B0_T);
    end
    if isfield(hw, 'slewModeLabel')
        writeLine('Slew mode label       : %s', hw.slewModeLabel);
    end
    if isfield(hw, 'gradCoilTypeLabel')
        writeLine('Gradient coil label   : %s', hw.gradCoilTypeLabel);
    end
    if isfield(hw, 'gradAmpTypeLabel')
        writeLine('Gradient amp label    : %s', hw.gradAmpTypeLabel);
    end
    if isfield(hw, 'coil')
        writeLine('pge2 coil name        : %s', hw.coil);
    end

    writeLine('------------------------------------------------------------');

    % ---------------------------------------------------------------------
    % Gradient capability
    % ---------------------------------------------------------------------
    if isfield(hw, 'gradFullScale_Gpcm')
        vals = hw.gradFullScale_Gpcm;
        writeLine('Gradient full scale   : X=%.3f  Y=%.3f  Z=%.3f G/cm', ...
            vals(1), vals(2), vals(3));
    end
    if isfield(hw, 'maxGrad_Gpcm')
        writeLine('Max gradient          : %.3f G/cm', hw.maxGrad_Gpcm);
    end
    if isfield(hw, 'maxGrad_mTm')
        writeLine('Max gradient          : %.3f mT/m', hw.maxGrad_mTm);
    end
    if isfield(hw, 'maxSlew_Tms')
        writeLine('Max slew              : %.3f T/m/s', hw.maxSlew_Tms);
        writeLine('Max slew              : %.3f G/cm/ms', hw.maxSlew_Tms/10);
    end

    writeLine('------------------------------------------------------------');

    % ---------------------------------------------------------------------
    % Timing rasters
    % ---------------------------------------------------------------------
    if isfield(hw, 'gradRasterTime_s')
        writeLine('Gradient raster       : %.1f us', hw.gradRasterTime_s * 1e6);
    end
    if isfield(hw, 'adcRasterTime_s')
        writeLine('ADC raster            : %.1f us', hw.adcRasterTime_s * 1e6);
    end
    if isfield(hw, 'rfRasterTime_s')
        writeLine('RF raster             : %.1f us', hw.rfRasterTime_s * 1e6);
    end
    if isfield(hw, 'blockDurationRaster_s')
        writeLine('Block raster          : %.1f us', hw.blockDurationRaster_s * 1e6);
    end

    writeLine('------------------------------------------------------------');

    % ---------------------------------------------------------------------
    % Backend timing offsets
    % ---------------------------------------------------------------------
    if isfield(hw, 'psd_rf_wait_us')
        writeLine('psd_rf_wait           : %.1f us', hw.psd_rf_wait_us);
    elseif isfield(hw, 'psd_rf_wait_s')
        writeLine('psd_rf_wait           : %.1f us', hw.psd_rf_wait_s * 1e6);
    end

    if isfield(hw, 'psd_grd_wait_us')
        writeLine('psd_grd_wait          : %.1f us', hw.psd_grd_wait_us);
    elseif isfield(hw, 'psd_grd_wait_s')
        writeLine('psd_grd_wait          : %.1f us', hw.psd_grd_wait_s * 1e6);
    end

    if isfield(hw, 'gradDelay_x_us')
        writeLine('Gradient delay X      : %.1f us', hw.gradDelay_x_us);
    end
    if isfield(hw, 'gradDelay_y_us')
        writeLine('Gradient delay Y      : %.1f us', hw.gradDelay_y_us);
    end
    if isfield(hw, 'gradDelay_z_us')
        writeLine('Gradient delay Z      : %.1f us', hw.gradDelay_z_us);
    end

    writeLine('------------------------------------------------------------');

    % ---------------------------------------------------------------------
    % RF / ADC timings
    % ---------------------------------------------------------------------
    if isfield(hw, 'rfDeadTime_s')
        writeLine('RF dead time          : %.1f us', hw.rfDeadTime_s * 1e6);
    end
    if isfield(hw, 'rfRingdownTime_s')
        writeLine('RF ringdown time      : %.1f us', hw.rfRingdownTime_s * 1e6);
    end
    if isfield(hw, 'adcDeadTime_s')
        writeLine('ADC dead time         : %.1f us', hw.adcDeadTime_s * 1e6);
    end
    if isfield(hw, 'adcRingdownTime_s')
        writeLine('ADC ringdown time     : %.1f us', hw.adcRingdownTime_s * 1e6);
    end

    writeLine('------------------------------------------------------------');

    % ---------------------------------------------------------------------
    % RF / safety
    % ---------------------------------------------------------------------
    if isfield(hw, 'b1_max_G')
        writeLine('b1_max (for pge2)     : %.3f G', hw.b1_max_G);
    end
    if isfield(hw, 'maxB1RMS_head_uT') && ~isnan(hw.maxB1RMS_head_uT)
        writeLine('Max B1+rms head       : %.3f uT', hw.maxB1RMS_head_uT);
    end

    writeLine('============================================================');

    % Close file
    fclose(fid);

end