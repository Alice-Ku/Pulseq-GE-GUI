% RDS recon for spiral imaging 0803
function recon_outputs = rds_spiral(prep_path, data_path, SpiralRecon_params, kspfile, b0kspfile)
    cplx = load_complex_iq_int16(data_path);
    scan = read_scan_setup_from_prep(prep_path);
    
    recon_outputs = reconstruct_spiral_image(cplx, SpiralRecon_params, kspfile, b0kspfile);

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

function recon_outputs = reconstruct_spiral_image(cplx, SpiralRecon_params, kspfile, b0kspfile)
    % High-res specs
    nleaf = SpiralRecon_params.nleaf;
    nx = SpiralRecon_params.HRNx; 
    nt = 1;
    nz = 1;
    fov = SpiralRecon_params.fovcm; % cm
    pred_kmax = SpiralRecon_params.pred_kmax;
    pislquant = SpiralRecon_params.pislquant;
    dwell = SpiralRecon_params.dwell;
    nADC = SpiralRecon_params.nADC;
    
    % B0 specs
    useB0 = SpiralRecon_params.useB0;
    fovb0 = fov;
    nxb0 = SpiralRecon_params.nxb0;
    TE1b0 = SpiralRecon_params.TE1b0;
    TE2b0 = SpiralRecon_params.TE2b0;
    b0nADC = SpiralRecon_params.b0nADC;

    samples_per_line = nADC;
    total_lines = floor(numel(cplx) / samples_per_line);

    if total_lines <= pislquant
        error('Not enough lines to remove prescan');
    end

    usable = total_lines * samples_per_line;
%     raw = reshape(cplx(1:usable), samples_per_line, total_lines).'; 
    raw = reshape(cplx(1:usable), total_lines, samples_per_line); 

    k = raw(pislquant+1:end, :);
    k(:, 2:2:end) = -k(:, 2:2:end);

    % Use spiral recon
    k = k.';
    recon_outputs = spiral_recon_helper(k, SpiralRecon_params, kspfile, b0kspfile);
    
end

function recon_outputs = spiral_recon_helper(d_all, SpiralRecon_params, kspfile, b0kspfile)

    % High-res specs
    nleaf = SpiralRecon_params.nleaf;
    nx = SpiralRecon_params.HRNx; 
    nt = 1;
    nz = 1;
    fov = SpiralRecon_params.fovcm; % cm
    pred_kmax = SpiralRecon_params.pred_kmax;
    pislquant = SpiralRecon_params.pislquant;
    dwell = SpiralRecon_params.dwell;
    nADC = SpiralRecon_params.nADC;
    
    % B0 specs
    useB0 = SpiralRecon_params.useB0;
    fovb0 = fov;
    nxb0 = SpiralRecon_params.nxb0;
    TE1b0 = SpiralRecon_params.TE1b0;
    TE2b0 = SpiralRecon_params.TE2b0;
    b0nADC = SpiralRecon_params.b0nADC;
    
    % High-res data
    d = d_all(:, 1:nleaf);
    
    % Use B0 correction
    if useB0 ~= 0
        % B0 data
        dB0 = d_all(:, (nleaf+1):end);
        
        % B0 traj
        fid = fopen(b0kspfile, 'rb');
        b0traj = fread(fid, [2, nADC], 'double');
        fclose(fid);
       
        b0kx = b0traj(1, :)';
        b0ky = b0traj(2, :)';
    
        b0kmax = max(sqrt(b0kx.^2 + b0ky.^2), [], 'all');
        fprintf(['b0kmax = %.4f\n'], b0kmax);
    
        % Reconstruct low-res images, skip scaling for now
        % [img ims dcf]: img is magnitude only; ims is complex coil images
        [b0img1 b0ims1 b0dcf1] = toppe.utils.spiral.reconSoS(dB0(:, 1), b0kx, b0ky, [fovb0 fovb0], [nxb0 nxb0], ...
                      'useParallel', false );
        [b0img2 b0ims2 b0dcf2] = toppe.utils.spiral.reconSoS(dB0(:, 2), b0kx, b0ky, [fovb0 fovb0], [nxb0 nxb0], ...
                      'useParallel', false );
    
        b0img1 = fliplr(b0img1);
        b0img2 = fliplr(b0img2);
        b0ims1 = fliplr(b0ims1);
        b0ims2 = fliplr(b0ims2);
    
        % Exclude the noisy background
        % mask = abs(b0ims1) > 0.01 * max(abs(b0ims1(:)));
    
        % Compute field map
        phase = angle(b0ims2(:, :, 1, 1, 1) .* conj(b0ims1(:, :, 1, 1, 1)));
        % phase(~mask) = NaN;
        zmap = phase / (2*pi*(TE2b0 - TE1b0));
        % Require the zmap to be the same size, interpolate
        zmap_hr = imresize(zmap, [nx nx], 'bicubic');
    
    end
    
    % High-res traj
    fid = fopen(kspfile, 'rb');
    data = fread(fid, [2, nADC], 'double');
    fclose(fid);
    
    kx_single = data(1, :)';
    ky_single = data(2, :)';
    
    
    kx = zeros(nADC, nleaf);
    ky = zeros(nADC, nleaf);
    
    for i = 1:nleaf
        theta = 2 * pi * (i - 1) / nleaf;
        c = cos(theta);
        s = sin(theta);
        kx(:, i) = kx_single * c - ky_single * s;
        ky(:, i) = kx_single * s + ky_single * c;
    end
    
    % Scale kx and ky to [-2.5 2.5] (cycles/cm) 
    kmax = max(sqrt(kx.^2 + ky.^2), [], 'all');
    scale = pred_kmax / kmax;
    kx = kx * scale;
    ky = ky * scale;
    fprintf(['kmax = %.4f\n'], kmax);
    fprintf(['scale = %.4f\n'], scale);
    
    % Sample time: stack so each interleaf starts from 0
    ti_leaf = (0:(nADC - 1))' * dwell;
    ti = repmat(ti_leaf, nleaf, 1);
    if useB0 ~= 0
        [imsoswb0 imswb0 dcfwb0] = toppe.utils.spiral.reconSoS(d, kx, ky, [fov fov], [nx nx], ...
                            'zmap', zmap_hr, ...
                            'ti', ti, ...
                            'useParallel', false);
    
        imsoswb0 = fliplr(imsoswb0);
        imswb0 = fliplr(imswb0);
        dcfwb0 = fliplr(dcfwb0);
    end
    
    [imsos ims dcf] = toppe.utils.spiral.reconSoS(d, kx, ky, [fov fov], [nx nx], ...
                        'useParallel', false );
    
    imsos = fliplr(imsos);
    ims = fliplr(ims);
    dcf = fliplr(dcf);
    
    % Pack outputs
    recon_outputs = struct();
    recon_outputs.imsos = imsos;
    recon_outputs.imsoswb0 = [];
    recon_outputs.b0img1 = [];
    recon_outputs.b0img2 = [];
    recon_outputs.b0ims1 = [];
    recon_outputs.b0ims2 = [];
    recon_outputs.zmap = [];
    recon_outputs.zmap_hr = [];
    
    if useB0 ~= 0
        recon_outputs.imsoswb0 = imsoswb0;
        recon_outputs.b0img1 = b0img1;
        recon_outputs.b0img2 = b0img2;
        recon_outputs.b0ims1 = b0ims1;
        recon_outputs.b0ims2 = b0ims2;
        recon_outputs.zmap = zmap;
        recon_outputs.zmap_hr = zmap_hr;
    end

end


