function S = rds_recon_core(prep_path,data_path,prescan_lines,nx_arg,ny_arg, isProduct)
% RDS_RECON  MATLAB version of rds_recon.py
%
% Usage:
%   rds_recon('--prep', 'out.txt.prep', '--data', 'out.txt.data')
%   rds_recon('--prep', 'out.txt.prep', '--data', 'out.txt.data', ...
%             '--prescan', '10', '--nx', '256', '--ny', '256')

    fprintf('Parsed args: nx_arg=%g ny_arg=%g prescan=%g\n', nx_arg, ny_arg, prescan_lines);

    cplx = load_complex_iq_int16(data_path);
    scan = read_scan_setup_from_prep(prep_path);

    nchan = scan.numChannels;

    if ~isempty(nx_arg) && ~isempty(ny_arg) && isfinite(nx_arg) && isfinite(ny_arg) ...
            && nx_arg > 0 && ny_arg > 0
        nx = nx_arg;
        ny = ny_arg;
    elseif scan.xres > 0 && scan.yres > 0
        nx = scan.xres;
        ny = scan.yres;
    else
        error('Could not determine matrix from PREP file. Supply --nx and --ny explicitly.');
    end

    fprintf('Matrix: %d x %d\n', nx, ny);
    fprintf('Channels: %d\n', nchan);
    fprintf('Prescan lines removed: %d\n', prescan_lines);

    [k, img] = reconstruct_image(cplx, nx, ny, prescan_lines, isProduct);

    klog  = single(log1p(abs(k)));
    mag   = single(abs(img));
    phase = single(angle(img));
    blank = zeros(size(mag), 'single');

    S = struct();
    S.prep_path = prep_path;
    S.data_path = data_path;
    S.nchan = nchan;
    S.nx = nx;
    S.ny = ny;
    S.klog = klog;
    S.mag = mag;
    S.phase = phase;
    S.blank = blank;
    S.current_images = {klog, mag, phase, blank};
    S.current_titles = {'log|k-space|', 'Magnitude', 'Phase', 'Blank'};
end


function [prep_path, data_path, prescan_lines, nx, ny] = parse_args(varargin)
    prep_path = '';
    data_path = '';
    prescan_lines = 10;
    nx = [];
    ny = [];

    i = 1;
    while i <= numel(varargin)
        arg = varargin{i};
        if isstring(arg)
            arg = char(arg);
        end

        if strcmp(arg, '--prep') && i + 1 <= numel(varargin)
            prep_path = char(varargin{i+1});
            i = i + 2;

        elseif strcmp(arg, '--data') && i + 1 <= numel(varargin)
            data_path = char(varargin{i+1});
            i = i + 2;

        elseif strcmp(arg, '--prescan') && i + 1 <= numel(varargin)
            prescan_lines = str2double(char(varargin{i+1}));
            i = i + 2;

        elseif strcmp(arg, '--nx') && i + 1 <= numel(varargin)
            nx = str2double(char(varargin{i+1}));
            i = i + 2;

        elseif strcmp(arg, '--ny') && i + 1 <= numel(varargin)
            ny = str2double(char(varargin{i+1}));
            i = i + 2;

        else
            error('Unknown or incomplete argument: %s', arg);
        end
    end

    if isempty(prep_path) || isempty(data_path)
        error(['Usage: rds_recon(''--prep'', ''out.txt.prep'', ''--data'', ''out.txt.data'', ' ...
               '''--prescan'', ''10'', ''--nx'', ''256'', ''--ny'', ''256'')']);
    end

    if ~isempty(nx) && (~isfinite(nx) || nx <= 0 || floor(nx) ~= nx)
        error('Invalid --nx value');
    end

    if ~isempty(ny) && (~isfinite(ny) || ny <= 0 || floor(ny) ~= ny)
        error('Invalid --ny value');
    end

    if ~isfinite(prescan_lines) || prescan_lines < 0 || floor(prescan_lines) ~= prescan_lines
        error('Invalid --prescan value');
    end
end


function scan = read_scan_setup_from_prep(prep_path)
    fid = fopen(prep_path, 'rb');
    if fid < 0
        error('Could not open prep file: %s', prep_path);
    end
    c = onCleanup(@() fclose(fid));

    buf = fread(fid, inf, 'uint8=>uint8');

    if numel(buf) < 56
        error('Prep file too small to contain RDS_SCAN_SETUP');
    end

    scan = struct();
    scan.edr         = double(typecast(buf(1:4),   'int32'));
    scan.numChannels = double(typecast(buf(5:8),   'int32'));
    scan.xres        = double(typecast(buf(9:12),  'int32'));
    scan.yres        = double(typecast(buf(13:16), 'int32'));

    if ~(scan.numChannels >= 1 && scan.numChannels <= 64)
        error('Invalid numChannels in prep: %d', scan.numChannels);
    end

    if scan.xres <= 0 || scan.yres <= 0
        warning('Prep file contains invalid xres/yres (%d x %d). Matrix will need fallback handling.', ...
            scan.xres, scan.yres);
    end
end


function cplx = load_complex_iq_int16(path)
    fid = fopen(path, 'rb');
    if fid < 0
        error('Could not open data file: %s', path);
    end
    c = onCleanup(@() fclose(fid));

    raw = fread(fid, inf, 'int16=>int16', 0, 'ieee-le');
    raw = raw(1:2*floor(numel(raw)/2));

    iq = reshape(single(raw), 2, []).';
    cplx = complex(iq(:,1), iq(:,2));
end


function [k, img] = reconstruct_image(cplx, nx, ny, prescan_lines, isProduct)
    samples_per_line = nx;
    total_lines = floor(numel(cplx) / samples_per_line);

    if total_lines <= prescan_lines
        error('Not enough lines to remove prescan');
    end

    usable = total_lines * samples_per_line;
    raw = reshape(cplx(1:usable), samples_per_line, total_lines).';

    raw = raw(prescan_lines+1:end, :);

    if size(raw, 1) < ny
        error('Not enough imaging lines: %d < %d', size(raw,1), ny);
    end

    k = raw(1:ny, :);

    % Alternate column polarity correction
    % k(:, 2:2:end) = -k(:, 2:2:end);
    
    if isProduct
        k(:, 2:2:end) = -k(:, 2:2:end);
        img = ifft2(ifftshift(k));
    else
        k = flipud(k);
        img = ifft2(ifftshift(k));
        img = fftshift(img);
    end
    
end
