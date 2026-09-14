function recon_outputs = recon_nufft_greb0(spiral2DScanArchiveFile, SpiralRecon_params, kspfile, grefile)
% Use dual echo GRE to correct for B0-inhomogeneity

% High-res specs
nleaf = SpiralRecon_params.nleaf;
nx = SpiralRecon_params.HRNx; 
nt = 1;
nz = 1;
fov = SpiralRecon_params.fovcm; % cm
pred_kmax = SpiralRecon_params.pred_kmax;
pislquant = SpiralRecon_params.pislquant;
dwell = SpiralRecon_params.dwell;
deltaTE = SpiralRecon_params.deltaTE;

[zmap, zmap_hr] = dualEchoZmap(grefile, nx, deltaTE);

% Reconstruction start
archive = GERecon('Archive.Load', spiral2DScanArchiveFile);
shot = GERecon('Archive.Next', archive);
[nADC, ~] = size(shot.Data);

d_all = zeros(nADC, pislquant+nleaf, nz, nt, 1); 

d_all(:,1,1,1,1) = shot.Data;

for l = 2:(nleaf+pislquant)
    shot = GERecon('Archive.Next', archive);
    d_all(:,l,1,1,1) = shot.Data;
end

% High-res data
d = d_all(:, (pislquant+1):(pislquant+nleaf));

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

zmap_hr_flip = fliplr(zmap_hr);
[imsoswb0 imswb0 dcfwb0] = toppe.utils.spiral.reconSoS(d, kx, ky, [fov fov], [nx nx], ...
                    'zmap', zmap_hr_flip, ...
                    'ti', ti, ...
                    'useParallel', false);

imsoswb0 = fliplr(imsoswb0);
imswb0 = fliplr(imswb0);
dcfwb0 = fliplr(dcfwb0);


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


recon_outputs.imsoswb0 = imsoswb0;
recon_outputs.zmap = zmap;
recon_outputs.zmap_hr = zmap_hr;

end

function [zmap, zmap_hr] = dualEchoZmap(gre_filename, nx, deltaTE)

archive = GERecon('Archive.Load', gre_filename);

% Scan parameters

xRes = 128;
yRes = 128;
stop = archive.DownloadData.rdb_hdr_rec.rdb_hdr_dab.stop_rcv;
start = archive.DownloadData.rdb_hdr_rec.rdb_hdr_dab.start_rcv;
nChannels = stop - start + 1;

% Keep track of the current pass
pass = 1;
zRes = archive.SlicesPerPass(pass);

% Allocate K-space
kspace1 = complex(zeros(xRes, yRes, nChannels, zRes));
kspace2 = complex(zeros(xRes, yRes, nChannels, zRes));
viewLine = 1;

for i = 1:archive.ControlCount
    control = GERecon('Archive.Next', archive);
    if(control.opcode == 1 && ...
       control.viewNum > 0)

        if control.echoNum == 0
            kspace1(:,viewLine,:,control.sliceNum + 1) = squeeze(control.Data);
        else
            kspace2(:,viewLine,:,control.sliceNum + 1) = squeeze(control.Data);
            viewLine = viewLine + 1;
        end
        
    elseif(control.opcode == 0) % end of pass and/or scan
        % Reconstruct this pass
        for slice = 1:zRes
            kspace2 = flipud(kspace2);

            for channel = 1:nChannels
                channelImages1(:,:,channel) = GERecon('Transform', kspace1(:,:,channel,slice));
                channelImages2(:,:,channel) = GERecon('Transform', kspace2(:,:,channel,slice));
            end

            % Apply Channel Combination
            combinedImage1 = GERecon('SumOfSquares', channelImages1);
            combinedImage2 = GERecon('SumOfSquares', channelImages2);

            % Create Magnitude Image
            magnitudeImage1 = abs(combinedImage1);
            phaseImage1 = angle(channelImages1);

            magnitudeImage2 = abs(combinedImage2);
            phaseImage2 = angle(channelImages2);

            % Get Info
            info = GERecon('Archive.Info', archive, pass, slice);

            % Orient the image
            % AK removed this since it resulted in unknown runtime
            % exception
            % finalImage = GERecon('Orient', magnitudeImage, info.Orientation);
            finalImage1 = magnitudeImage1;
            finalImage2 = magnitudeImage2;

            % Display
            figure;
            subplot(3, 2, 1);
            imagesc(finalImage1);
            axis image off;
            colormap(gray);
            title('2DGRE multi-echo: echo 1');

            subplot(3, 2, 2);
            imagesc(finalImage2);
            axis image off;
            colormap(gray);
            title('2DGRE multi-echo: echo 2');

            subplot(3, 2, 3);
            imagesc(phaseImage1);
            axis image;
            colormap jet;
            title('Phase 1');
            colorbar;

            subplot(3, 2, 4);
            imagesc(phaseImage2);
            axis image;
            colormap jet;
            title('Phase 2');
            colorbar;

            subplot(3, 2, 5);
            imagesc(log(abs(kspace1))); 
            axis image; 
            colormap(gray);
            title('kspace 1');

            subplot(3, 2, 6);
            imagesc(log(abs(kspace2))); 
            axis image; 
            colormap(gray);
            title('kspace 2');

        end

        if(pass < archive.Passes)
            pass = pass + 1;
            zRes = archive.SlicesPerPass(pass);
            kspace1 = complex(zeros(xRes, yRes, nChannels, zRes));
            kspace2 = complex(zeros(xRes, yRes, nChannels, zRes));
            
        end

    end
end

% Close the archive to release it from memory
GERecon('Archive.Close', archive);

%% Calculate field map
phase_map = angle(channelImages2.*conj(channelImages1));
mask = abs(channelImages1) > 0.1 * max(abs(channelImages1(:)));
phase_map(~mask) = NaN;
zmap = phase_map / (2 * pi * deltaTE);
zmap_hr = imresize(zmap, [nx nx], 'bicubic');

figure; 
subplot(1, 2, 1);
imagesc(zmap);
axis image;
colormap jet;
title('zmap');
colorbar;

subplot(1, 2, 2);
imagesc(zmap_hr);
axis image;
colormap jet;
title('zmap hr');
colorbar;

%%
save('gre_2echo_zmap', 'zmap');
end
