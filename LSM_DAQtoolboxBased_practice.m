% Data Acquisition interface based(MATLAB 2020a)
% continuous 2D scanning and corresponding Analog acquisition
%
% Closing the figure closes the DAQ connection 
%
% Highly inspired from the SimpleMScanner
% https://github.com/tenss/SimpleMScanner
%
% Yong Guk Kang. 2021.02.24
% kygwow@korea.ac.kr

try
    clear param
    clear hFp
    clear hFd
    stop(D)
    clear D
catch
end
%% input configuration

param.DAQDevice = 'Dev1';
param.AOChans = 0:1;
param.AIChans = 0;
param.SampleRate = 250000; %corresponds to 4 microsecond
param.ImgSize = 500;
param.backScanRate = 0.2; % Back scan ratio for generating sawtooth beam
param.desiredFOV = 0.6; %mm scale
param.fObj = 18; %mm scale % [36 18 9]=[5x 10x 20x]
param.mag = 100/250; %scan/tube focal length
param.vDeg = 0.8; %0.8V/deg
param.isRunning=0;

%dependent configuration
%maximum voltage area for rasterscan : determines field of view
param.MaxV=(param.vDeg)*(1/param.mag).*atand(param.desiredFOV/(2*param.fObj));
%number of pixels for x-axis, including backScan
param.xScanSize=ceil(param.ImgSize*(1+param.backScanRate));

%% Generate sawtooth Waveform
%This will be modularized for the pattern scanning in future

%forward scan + backward scan
xTemplate = [linspace(-param.MaxV,param.MaxV,param.ImgSize),linspace(param.MaxV,-param.MaxV,param.xScanSize-param.ImgSize)];
%forward scan
yTemplate = linspace(-param.MaxV,param.MaxV,param.ImgSize);

%predefine waveform
xWaveform = zeros(1,param.ImgSize*param.xScanSize);
yWaveform = zeros(1,param.ImgSize*param.xScanSize);

for iy = 1:param.ImgSize
    for ix = 1:param.xScanSize
        %generate x voltage 
        xWaveform(ix+(iy-1)*param.xScanSize) = xTemplate(ix);
       
        %generate y voltage 
        yWaveform(ix+(iy-1)*param.xScanSize) = yTemplate(iy);
    end
end

param.waveforms = [xWaveform(:),yWaveform(:)];

%% Create DataAcquisition Object
% Create a DataAcquisition object 
D = daq("ni");
flush(D)
% Add channels and set channel properties, if any.
%galvanometer
addoutput(D,param.DAQDevice,param.AOChans,"Voltage");
%Analog Photodetector, or else
addinput(D,param.DAQDevice,param.AIChans,"Voltage");

% Set DataAcquisition Rate
% Set scan rate.
D.Rate = param.SampleRate;


%% generate parameter and draw figures
%parameter window, will be used future
hFp=uifigure;
hFp.Position(3:4) = [1400,160];
t=(struct2table(param,'AsArray',true));
uit = uitable(hFp,'Data',t,'ColumnEditable',true);
uit.Position= [10,hFp.Position(4)/2, hFp.Position(3)-100, hFp.Position(4)-100];
txl = uilabel(hFp);
txl.Text='Imaging Parameters';
txl.Position=[hFp.Position(3)/2,0,200,50];

%image display figure
hFd=figure;
imagesc(ones(param.ImgSize)); axis image;

% Use a callback to stop the acquisition gracefully when the user closes the plot window
% from SimpleMScanner
set(hFd,'CloseRequestFcn', @(~,~) figCloseAndStopScan(D,hFd));

set(hFp,'CloseRequestFcn', @(~,~) figCloseAndStopScan(D,hFp));


%% start in background 

%buffer for AO channel, required for background scanning
preload(D,param.waveforms);

%define number of points per one scan : full single resonant scan
D.ScansAvailableFcnCount=length(param.waveforms);
% draw image when number of points acquired exceeds full single resonant
% scan, from SimpleMScanner
D.ScansAvailableFcn=@(src, evt) plotCurrentImage(src, evt, hFd, param);

% start DAQ task
start(D,"Continuous");
param.isRunning=1;


%% built-in callback functions

function plotCurrentImage(src, ~, hFig, param)
    [data, ~, ~] = read(src, src.ScansAvailableFcnCount, "OutputFormat", "Matrix");
    curFrame=reshape(data,param.xScanSize,[]);
    curFrame(param.ImgSize+1:end,:)=[];
    %select figure window without focusing
    set(groot,'CurrentFigure',hFig);
    imagesc(curFrame); axis image;
    title(string(datetime));
end

function figCloseAndStopScan(src, hFig)
    %Runs on scan figure window close
    fprintf('Shutting down DAQ connection\n')
    stop(src); % Stop the acquisition
    clear src
    delete(hFig);
    fprintf('Success\n')
end %close figCloseAndStopScan

