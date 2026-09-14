function recon_outputs = recon_nufft_guiV2(spiral2DScanArchiveFile, SpiralRecon_params, kspfile, b0kspfile)

% High-res specs
nleaf = SpiralRecon_params.nleaf;
nx = SpiralRecon_params.HRNx; 
nt = 1;
nz = 1;
fov = SpiralRecon_params.fovcm; % cm
pred_kmax = SpiralRecon_params.pred_kmax;
pislquant = SpiralRecon_params.pislquant;
dwell = SpiralRecon_params.dwell;

% B0 specs
useB0 = SpiralRecon_params.useB0;
fovb0 = fov;
nxb0 = SpiralRecon_params.nxb0;
TE1b0 = SpiralRecon_params.TE1b0;
TE2b0 = SpiralRecon_params.TE2b0;

% Reconstruction start
archive = GERecon('Archive.Load', spiral2DScanArchiveFile);
shot = GERecon('Archive.Next', archive);
[nADC, ~] = size(shot.Data);

d_all = zeros(nADC, pislquant+nleaf, nz, nt, 1); 

d_all(:,1,1,1,1) = shot.Data;

for l = 2:(nleaf+pislquant+useB0)
    shot = GERecon('Archive.Next', archive);
    d_all(:,l,1,1,1) = shot.Data;
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

% High-res data
d = d_all(:, (pislquant+1):(pislquant+nleaf));

[imsos ims dcf] = toppe.utils.spiral.reconSoS(d, kx, ky, [fov fov], [nx nx], ...
                    'useParallel', false );

% Use B0 correction
if useB0 ~= 0
    % B0 data
    dB0 = d_all(:, (pislquant+nleaf+1):end);
    
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

    % Exclude the noisy background
    % mask = abs(b0ims1) > 0.01 * max(abs(b0ims1(:)));
    
    threshold = 0.06;
    magSmooth = imgaussfilt(abs(imsos), 1);
    mask = magSmooth > threshold * max(magSmooth(:));
    mask = bwareafilt(mask, 1);
    mask = imfill(mask, "holes");
    mask = imopen(mask, strel("disk", 2));
    mask = imclose(mask, strel("disk", 3));   % AK0821
    figure; imagesc(mask); axis image off; colormap gray; title('Evaluation Mask');

    % Compute field map
    phase = angle(b0ims2(:, :, 1, 1, 1) .* conj(b0ims1(:, :, 1, 1, 1)));
    % phase(~mask) = NaN;
    zmap = phase / (2*pi*(TE2b0 - TE1b0));
    % Require the zmap to be the same size, interpolate
    zmap_hr = imresize(zmap, [nx nx], 'bicubic');
    zmap_hr(~mask) = 0;   % AK0821
    zmap_hr = zmap_hr.*(-1);

end

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

    b0img1 = fliplr(b0img1);
    b0img2 = fliplr(b0img2);
    b0ims1 = fliplr(b0ims1);
    b0ims2 = fliplr(b0ims2);
end



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