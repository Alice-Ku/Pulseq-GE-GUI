% AK modified on 01/30/2026 for Pulseq data, based on RunCartesianScanArchive_og.m
% directory = fileparts(mfilename('fullpath'));
% filename = fullfile(directory, '\Data\CartesianScanArchive\Series4\ScanArchive_70001MRS11_20260128_203318804.h5');
% filename = fullfile(directory, '\Data\CartesianScanArchive\Series1\ScanArchive_70001MRS11_20251204_171513227.h5');
% filename = char("C:\Users\yhk38\OneDrive - University of Cambridge\Desktop\Scanner\0206_scanner\Exam9303\Series3\ScanArchive_70001MRS11_20260206_163743721.h5");
% filename = char("C:\Users\yhk38\OneDrive - University of Cambridge\Desktop\0806\dual_echo.h5");
function [zmap, zmap_hr] = dualEchoZmap(gre_filename)

archive = GERecon('Archive.Load', gre_filename);

% Scan parameters
% AK hardcoded these params for test (since xRes alternates between 192/48)
% xRes = 48;
xRes = 128;
yRes = 128;
% xRes = archive.DownloadData.rdb_hdr_rec.rdb_hdr_da_xres;
% yRes = archive.DownloadData.rdb_hdr_rec.rdb_hdr_da_yres - 1;
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

% Loop through each control, sorting frames if applicable
% AK started from 12 since the first 11 controls are not actual data
for i = 1:archive.ControlCount
    % Retrieve the next control packet along with its associated data (if
    % applicable) from the archive. Frame data is returned in the
    % control.Data field and is organized as: ReadoutSize x NumChannels x
    % NumFrames where NumFrames is the number of frames corresponding to
    % this control packet. Each programmable packet corresponds to a single
    % frame. Thus, for this example, the frames dimension of control.Data
    % will always have a size of 1
    control = GERecon('Archive.Next', archive);

    % Sort only programmable packets in range
    % AK removed the last condition, otherwise the kspace was never loaded
    % if(control.opcode == 1 && ...
    %    control.viewNum > 0 && ...
    %    control.viewNum <= yRes && ...
    %    size(control.Data, 1) == 192)
   
    % AK added the viewNum condition to select one of the echoes for every
    % reconstruction; also skip the first 10 for pislquant
    if(control.opcode == 1 && ...
       control.viewNum > 0)
        % Each programmable packet contains a single frame of data. Squeeze
        % off the singular frames dimension and copy the data into the
        % kSpace matrix.
        % AK changed the last dimension since Pulseq has control.sliceNum
        % starting from 1
        % kspace(:,control.viewNum,:,control.sliceNum) = squeeze(control.Data);
        % AK changed the ky count since arrays that were 48 were skipped
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

            % AK added this to remove all-zero columns
            % kspace = kspace(:, any(kspace, 1), :, :); % Remove all-zero columns
            
            % AK added this since the first few control is not actual
            % kspace data
            % kspace = kspace(:, 6:197);
                
            % AK added this to shift the kspace to center
            % kspace = fftshift(kspace);
            for channel = 1:nChannels
                channelImages1(:,:,channel) = GERecon('Transform', kspace1(:,:,channel,slice));
                channelImages2(:,:,channel) = GERecon('Transform', kspace2(:,:,channel,slice));
                
                % AK added this to try normal reconstruction, img is right
%                 img = ifftshift(ifft2(fftshift(kspace(:,:,channel,1))));
%                 channelImages(:,:,channel) = img;

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
                
            % Save DICOMs
%             filename = ['DICOMs/image' num2str(info.Number) '.dcm'];
%             GERecon('Dicom.Write', filename, finalImage, info.Number, info.Orientation, info.Corners);
        end

%         file_save = sprintf("kspace_orch_%d.mat", pass);
%         save(file_save, "kspace")

        % Move the next pass and clear out kspace if not last pass
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
nx = 256;
deltaTE = 2.4e-3;
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

