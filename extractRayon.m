% Arthur Rubio, 04/2024
% GNU GENERAL PUBLIC LICENSE
% "Preprocessing of Iris Images for BSIF-Based Biometric Systems: Binary 
% detected edges and Iris Unwrapping", IPOL (Image Processing On Line), 2024, Paris, France.
%
% This code determines the inner and outer radius of the iris using edge detection
% The edge detection is performed using the Canny method
% Calculate the coordinates of the center of the image (which is considered for the moment as that of the eye)
%
% Input : I : image of the iris
% Output : r_ext : outer radius of the iris
%          r_int : inner radius of the iris
%          centre_oeil_x : x coordinate of the center of the image
%          centre_oeil_y : y coordinate of the center of the image

function [r_ext,r_int,centre_oeil_x,centre_oeil_y] = extractRayon(J)

s = size(J);
centreImageX = round(s(2)/2);
centreImageY = round(s(1)/2);
% Distance to the center tolerance (in px)
tolerance = 10;

[filteredPupilCenter, filteredPupilRadii, filteredPupilMetric] = deal([], [], []);
[filteredIrisCenter, filteredIrisRadii, filteredIrisMetric] = deal([], [], []);

% Smoothing of the image
G = fspecial("gaussian", 25, 7);
I_gauss = conv2(J, G, "same");
I_median = medfilt2(I_gauss, [3 3]);

% Histogram normalization of the smoothed image
I_adj = imadjust(I_median);

% Definition of the sobel masks
Mx = [-1 0 1; -2 0 2; -1 0 1];
My = [1 2 1; 0 0 0; -1 -2 -1];
Jx = filter2(Mx, I_adj);
Jy = filter2(My, I_adj);

eta = atan2(Jy, Jx);
Ggray = sqrt(Jx.^2 + Jy.^2);
% figure,imagesc(J),colormap(gray), title('Image grey');
% figure,imagesc(Ggray),colormap(gray), title('Gradient grey');
% figure,imagesc(eta),colormap(gray), title('Gradient direction');

[NMS] =  directionalNMS(Jx,Jy);
Gradient_max= Ggray .* NMS;
% figure,imagesc(NMS),colormap(gray), title('NMS');
% figure,imagesc(Gradient_max), colormap(gray), title('Gradient max');

% Adaptive thresholding
Icol_suppr_n = f_normalisation(Gradient_max);
level = adaptthresh(Icol_suppr_n, 'NeighborhoodSize', [25 25], 'ForegroundPolarity', 'dark');
level = level + 0.03;
Icol_bin = imbinarize(Icol_suppr_n, level);

% Deleting all non-circular components of the image
% Analysis of the circular components
circularityThreshold = 0.01;
CC = bwconncomp(Icol_bin);
numPixels = cellfun(@numel, CC.PixelIdxList);
circularities = zeros(CC.NumObjects, 1);

% Image to mark the circular components
Icol_circular = false(size(Icol_bin));

% Compute all circular components
for i = 1:CC.NumObjects
    singleComponent = false(size(Icol_bin));
    singleComponent(CC.PixelIdxList{i}) = true;

    % Compute the perimeter
    componentPerimeter = sum(bwperim(singleComponent, 8), 'all');

    % Compute the circularity
    area = numPixels(i);
    circularity = (4 * pi * area) / (componentPerimeter ^ 2);
    circularities(i) = circularity;

    % Circularity thresholding
    if circularity > circularityThreshold
        Icol_circular(CC.PixelIdxList{i}) = true;
    end
end

% Morphological closing to fill small gaps and connect disjointed regions
% Disk element to reinforce the circular outline of the pupil and iris
SE1 = strel('disk', 4);
Icol_close = imclose(Icol_circular, SE1);

% Dynamically detect the pupil on the image
[pupilCenter, pupilRadii, pupilMetric] = pupilDetectionDynamicSensitivity(Icol_close, centreImageX, centreImageY);
% Calculate distances between the centers of the circles and the image center
distances = sqrt((pupilCenter(:,1) - centreImageX).^2 + (pupilCenter(:,2) - centreImageY).^2);

% Find the index of the circle closest to the image center
[~, minIndex] = min(distances);

% Select the characteristics of this circle
filteredPupilCenter = pupilCenter(minIndex, :);
filteredPupilRadii = pupilRadii(minIndex);
filteredPupilMetric = pupilMetric(minIndex);

% Dynamic cropping of the image based on the dilatation of the pupil
scale = round(filteredPupilRadii)/60;
Icol_close(1 : round((filteredPupilCenter(2) - (1.3/scale)*filteredPupilRadii)),:) = 0;
Icol_close(round((filteredPupilCenter(2) + (2/scale)*filteredPupilRadii)) : s(1),:) = 0;
Icol_close(:,1 : round((filteredPupilCenter(1) - (3/scale)*filteredPupilRadii))) = 0;
Icol_close(:,round((filteredPupilCenter(1) + (3/scale)*filteredPupilRadii)) : s(2)) = 0;

% Dynamically detect the iris on the image
[irisCenter, irisRadii, irisMetric] = irisDetectionDynamicSensitivity(Icol_close, filteredPupilCenter);
[filteredIrisCenter, filteredIrisRadii, filteredIrisMetric] = filterCircles(irisCenter, irisRadii, irisMetric, centreImageX, centreImageY, tolerance);

% Creation of inversed figure for the paper
Icol_close_inverted = ~Icol_close;
taille_marge = 5;
[dimy, dimx] = size(Icol_close_inverted);

% Calculer les dimensions de la nouvelle image avec la marge
nouvelle_dimy = dimy + 2 * taille_marge;
nouvelle_dimx = dimx + 2 * taille_marge;
image_avec_marge = zeros(nouvelle_dimy, nouvelle_dimx);
image_avec_marge(taille_marge + 1:taille_marge + dimy, taille_marge + 1:taille_marge + dimx) = Icol_close_inverted;
% figure,imagesc(image_avec_marge),colormap(gray),title("Inverted binarized image with margin");

% Function to detect dynamically the pupil
    function [pupilCenter, pupilRadii, pupilMetric] = pupilDetectionDynamicSensitivity(Icol_close, centreImageX, centreImageY)
        % Sensitivity starting at 0.859 and going up to 0.999
        sensitivity = 0.859;
        maxSensitivity = 1;
        sensitivityStep = 0.02;
        radiusRange = [20 80];
        objectPolarity = 'bright';
        % Distance (in px) from the center of the image tolerated
        tolerance = 50;

        while sensitivity <= maxSensitivity
            % Detect circles close to the center of the image with the given sensibility
            [centers, radii, metric] = imfindcircles(Icol_close, radiusRange, 'ObjectPolarity', objectPolarity, 'Sensitivity', sensitivity);
            [pupilCenter, pupilRadii, pupilMetric, found] = filterCircles(centers, radii, metric, centreImageX, centreImageY, tolerance);
            if found
                break;
            else
                sensitivity = sensitivity + sensitivityStep;
            end
        end
    end

% Function to detect dynamically the pupil
    function [irisCenter, irisRadii, irisMetric] = irisDetectionDynamicSensitivity(Icol_close, pupilCenter)
        sensitivity = 0.859;
        maxSensitivity = 1;
        sensitivityStep = 0.02;
        radiusRange = [100 180];
        objectPolarity = 'bright';
        % Distance (in px) from the center of the pupil tolerated
        tolerance = 20;

        % Increase the sensitivity if a circle is not found
        while sensitivity <= maxSensitivity
            [centers, radii, metric] = imfindcircles(Icol_close, radiusRange, 'ObjectPolarity', objectPolarity, 'Sensitivity', sensitivity);
            [irisCenter, irisRadii, irisMetric, found] = filterCircles(centers, radii, metric, pupilCenter(1), pupilCenter(2), tolerance);
            if found
                break;
            else
                sensitivity = sensitivity + sensitivityStep;
            end
        end
    end

% Filter the circles if multiples are detected
    function [filteredCenters, filteredRadii, filteredMetric, found] = filterCircles(centers, radii, metric, centerX, centerY, tolerance)
        filteredCenters = [];
        filteredRadii = [];
        filteredMetric = [];

        found = false;
        if isempty(centers)
            return;
        end

        for i = 1:size(centers, 1)
            if abs(centers(i,1) - centerX) <= tolerance && abs(centers(i,2) - centerY) <= tolerance
                filteredCenters = [filteredCenters; centers(i,:)];
                filteredRadii = [filteredRadii; radii(i)];
                filteredMetric = [filteredMetric; metric(i)];
            end
        end

        if ~isempty(filteredCenters)
            distances = sqrt((filteredCenters(:,1) - centerX).^2 + (filteredCenters(:,2) - centerY).^2);
            [~, closestIndex] = min(distances);
            filteredCenters = filteredCenters(closestIndex, :);
            filteredRadii = filteredRadii(closestIndex);
            filteredMetric = filteredMetric(closestIndex);
            found = true;
        end
    end
% figure,imagesc(Icol_close),colormap(gray),title("found circles");

% Verification and display of pupil and iris circles
hold on;
if ~isempty(filteredPupilCenter)
    viscircles(filteredPupilCenter, filteredPupilRadii, 'EdgeColor', 'b');
end
if ~isempty(filteredIrisCenter)
    viscircles(filteredIrisCenter, filteredIrisRadii, 'EdgeColor', 'r');
end
hold off;

centre_oeil_x = round(filteredPupilCenter(1));
centre_oeil_y = round(filteredPupilCenter(2));

% Diameter calculation of the iris
if isempty(filteredIrisCenter)
    % If the iris is not detected, generate an iris circle with a radius proportionate to the degree of pupil dilation
    fprintf('No iris detected.\n');
    filteredIrisRadii = filteredPupilRadii * (2.3/scale);
end

r_int = round(filteredPupilRadii);  % Outer radius of the iris
r_ext = round(filteredIrisRadii);  % Inner radius of the iris
end