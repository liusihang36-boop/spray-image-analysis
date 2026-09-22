function out = spray_preprocess_trial(folder,bgNames,bgPath)
% 喷雾原始图像预处理试用版（不计算毫米贯穿距或锥角）
% 运行：spray_preprocess_trial；需要 Image Processing Toolbox。
% 选择直接包含 BMP 的文件夹，再选择确认无喷雾的背景帧。
% 原图不改动；每次新建结果目录，保存原尺寸二值图、叠加图和记录。
% 注意：新二值图坐标、比例与旧程序不同，不能直接沿用旧标定。
%
% 调参建议：漏掉浅边缘，先适当降低 lowAbs/lowRel；
% 背景误识别，先检查参考区域，再提高阈值；不要为曲线平滑删真实边缘。
% 这些默认值只是本批8位样图的试验起点，不是经验证的最佳阈值。
clc;
out='';
% 修订：自动确定有效区域，取消所有区域选择窗口。
p.windowDiameter_mm = 170; % 用户确认的通光直径；仅记录，尚未拟合像素直径
% 自动区域版不使用帧间亮度校正，避免喷雾污染参考区域。
p.lowAbs = 12;                 % 弱边缘最低绝对灰度差（统一0~255尺度）
p.highAbs = 20;               % 可靠主体最低绝对灰度差
p.lowRel = 0.12;              % 弱边缘相对背景衰减
p.highRel = 0.20;             % 可靠主体相对背景衰减
p.noiseLow = 3; p.noiseHigh = 5; % 根据背景变化估计的噪声倍数
p.graySigma = 0.8;           % 差分图轻度高斯去噪，设0关闭；不对二值图腐蚀
p.minArea = 8;                % 连通区域最小像素数；设1保留所有候选
p.viewMin = 30;               % 背景低于此值排除（遮挡/黑背景）
p.edgeMargin = 2;            % 有效视窗边界向内缩像素数
p.overlayEvery = 1;           % 每隔多少帧保存叠加图；大数据可设5或10
p.weakRecovery = true; % 试用：仅恢复主体6像素邻域内且本帧有灰度支撑的弱边缘
p.recoveryRadius_px=6; p.recoveryFactor=0.8; p.recoveryMinNeighbors=5;
p.saveDifference = true;    % 是否额外保存差分图
p.frameRate = 25000;          % 仅按原文件帧号计算相对首帧时间，不是ASOI
interactiveMode = nargin<1 || isempty(folder);
if interactiveMode
    folder = uigetdir(pwd,'选择直接包含原始 BMP 的文件夹');
    if isequal(folder,0), return; end
end
files = dir(fullfile(folder,'*.bmp'));
if isempty(files), error('该目录没有 BMP 图像。'); end
ids = nan(numel(files),1);
for k=1:numel(files)
    tok=regexp(files(k).name,'\d+','match');
    if isempty(tok), error('文件名缺少帧号：%s',files(k).name); end
    ids(k)=str2double(tok{end});
end
[ids,ord]=sort(ids); files=files(ord);
p.sourceFirstID=ids(1); p.zeroFrameID=ids(1)+1; p.analysisEnd_ms=5;
% 保留背景索引供旧测量代码兼容；背景不进入二值化循环。
keep=ids==p.sourceFirstID | (ids>=p.zeroFrameID & (ids-p.zeroFrameID)*1000/p.frameRate<=p.analysisEnd_ms+1e-9);
ids=ids(keep); files=files(keep);
if numel(unique(ids))~=numel(ids), error('文件末尾帧号重复，请先核对命名。'); end
if nargin<2 || isempty(bgNames)
    if interactiveMode
        [bgNames,bgPath]=uigetfile(fullfile(folder,'*.bmp'), ...
            '选择无喷雾背景帧（可多选；例如000000和000001）','MultiSelect','on');
        if isequal(bgNames,0), return; end
    else
        % 固定验证模式：用户已确认序列第一帧为背景帧。
        bgNames={files(1).name}; bgPath=folder;
    end
elseif nargin<3 || isempty(bgPath)
    bgPath=folder;
end
if ischar(bgNames), bgNames={bgNames}; end
first=readGray(fullfile(folder,files(1).name));
[h,w]=size(first); stack=zeros(h,w,numel(bgNames),'single');
for k=1:numel(bgNames)
    a=readGray(fullfile(bgPath,bgNames{k}));
    if ~isequal(size(a),[h w]), error('背景图像尺寸不一致。'); end
    stack(:,:,k)=a;
end
B=median(stack,3);
valid=B>p.viewMin;
valid=bwareafilt(valid,1); % 仅选背景主视窗，不填充内部遮挡
[excluded,obstructionMeta]=spray_obstruction_mask(folder,B);
valid=valid & ~excluded;
valid=imerode(valid,strel('disk',p.edgeMargin,0));
if nnz(valid)<100, error('自动有效区域过小，请检查背景帧或viewMin参数。'); end
% 只对已确认无喷雾的背景帧估计噪声；无需人工参考区域。
% 用背景各帧经亮度校正后的残差估计一个稳健噪声尺度。
noise=[];
for k=1:size(stack,3)
    a=stack(:,:,k); off=median(a(valid)-B(valid));
    r=a-B-off; vals=r(valid); noise=[noise; vals(1:20:end)]; %#ok<AGROW>
end
sigma=max(1,1.4826*median(abs(noise-median(noise))));
if size(stack,3)<5
    p.noiseEstimateQuality='single_or_few_background_frames';
    fprintf('背景信息：%d张确认背景；使用固定灰度门限，帧间噪声未充分估计。\n',size(stack,3));
else
    p.noiseEstimateQuality='multi_background_frames';
end
p.backgroundFrameCount=size(stack,3);
low=max(max(p.lowAbs,p.noiseLow*sigma),p.lowRel*B);
high=max(max(p.highAbs,p.noiseHigh*sigma),p.highRel*B);
out=fullfile(folder,['spray_trial_' datestr(now,'yyyymmdd_HHMMSS')]);
while exist(out,'dir'), out=[out '_new']; end %#ok<AGROW>
mkdir(out); mkdir(fullfile(out,'6')); mkdir(fullfile(out,'overlay'));
if p.saveDifference, mkdir(fullfile(out,'difference')); end
mkdir(fullfile(out,'baseline_mask')); mkdir(fullfile(out,'recovered_pixels'));
imwrite(valid,fullfile(out,'valid_mask.png'));
imwrite(uint8(B),fullfile(out,'background.png'));
save(fullfile(out,'settings.mat'),'p','B','valid','sigma','low','high','bgNames','bgPath','excluded','obstructionMeta');
n=numel(files); names={files.name}'; status=repmat({'not_processed'},n,1);
area=nan(n,1); offsets=nan(n,1); referenceP95=nan(n,1);
appliedOffsets=nan(n,1); correctionRejected=false(n,1);
touch=false(n,1); removed=nan(n,1); errors=repmat({''},n,1);
edge=valid & ~imerode(valid,strel('disk',2,0));
bar=waitbar(0,'处理中；关闭进度窗口可停止');
clean=onCleanup(@()closeIfValid(bar)); %#ok<NASGU>
for k=1:n
    if ~ishghandle(bar), break; end
    if ids(k)<p.zeroFrameID, status{k}='background_only'; area(k)=0; continue; end
    try
        I=readGray(fullfile(folder,files(k).name));
        if ~isequal(size(I),[h w]), error('图像尺寸不同'); end
        residual=B-I; D=max(residual,0);
        appliedOffsets(k)=0;
        % 在有效区域内归一化滤波，避免黑色遮挡污染附近的差分值。
        if p.graySigma>0
            weights=imgaussfilt(single(valid),p.graySigma,'FilterSize',7,'Padding','replicate');
            filtered=imgaussfilt(residual.*single(valid),p.graySigma, ...
                'FilterSize',7,'Padding','replicate');
            D=max(filtered./max(weights,single(1e-6)),0);
        end
        weak=(D>=low)&valid; strong=(D>=high)&weak;
        candidate=imreconstruct(strong,weak,8);
        baseline=bwareaopen(candidate,p.minArea,8);
        candidate=baseline;
        if p.weakRecovery && any(baseline(:))
            near=imdilate(baseline,strel('disk',p.recoveryRadius_px,0));
            evidence=valid & D>=max(p.recoveryFactor*low,p.noiseLow*sigma);
            supported=conv2(single(evidence),ones(3),'same')>=p.recoveryMinNeighbors;
            allowed=baseline | (near & evidence & supported);
            candidate=imreconstruct(baseline,allowed,8);
        end
        mask=bwareaopen(candidate,p.minArea,8);
        removed(k)=nnz(candidate)-nnz(mask);
        area(k)=nnz(mask);
        touch(k)=any(mask(edge)); status{k}='ok';
        if area(k)==0, status{k}='empty'; end
        % 触边包括喷嘴附近触边，作为人工复核提示，不能自动认定前端截断。
        [~,stem]=fileparts(files(k).name);
        imwrite(mask,fullfile(out,'6',[stem '.bmp']));
        imwrite(baseline,fullfile(out,'baseline_mask',[stem '.bmp']));
        imwrite(mask & ~baseline,fullfile(out,'recovered_pixels',[stem '.png']));
        if p.saveDifference
            imwrite(uint8(D),fullfile(out,'difference',[stem '.png']));
            save(fullfile(out,'difference',[stem '.mat']),'D'); % 保留浮点精度
        end
        if mod(k-1,p.overlayEvery)==0 || k==n
            rgb=repmat(uint8(I),1,1,3);
            rgb=paint(rgb,bwperim(valid),[0 180 255]);
            rgb=paint(rgb,candidate & ~mask,[255 180 0]);
            rgb=paint(rgb,bwperim(mask),[255 0 0]);
            imwrite(rgb,fullfile(out,'overlay',[stem '.png']));
        end
    catch ME
        status{k}='failed'; errors{k}=ME.message;
        warning('处理失败 %s：%s',names{k},ME.message);
    end
    waitbar(k/n,bar,sprintf('%d / %d',k,n));
end
% 不压缩缺帧的时间；未处理/失败帧同样保留记录。
timeMs=(ids-ids(1))*1000/p.frameRate;
T=table(names,ids,timeMs,area,offsets,referenceP95,touch,removed,status,errors, ...
    'VariableNames',{'File','FrameID','TimeFromFirst_ms','Area_px', ...
    'BrightnessOffset','ReferenceResidualP95','TouchesValidBoundary', ...
    'RemovedPixels','Status','Error'});
T.Time_ms=(ids-p.zeroFrameID)*1000/p.frameRate; % 与测量表统一：第二帧为零
T.AppliedBrightnessOffset=appliedOffsets;
T.CorrectionRejected=correctionRejected;
writetable(T,fullfile(out,'processing_log.csv'));
fid=fopen(fullfile(out,'README.txt'),'w','n','UTF-8');
if fid>=0
 fprintf(fid,['试用版预处理结果\n6：原尺寸二值图。overlay：红色喷雾边界，蓝色有效视窗，橙色被删像素。\n' ...
 'settings.mat：全部参数与背景、掩膜。processing_log.csv：每个输入帧的状态。\n' ...
 '时间由文件末尾原始帧号和配置帧率计算，相对第一张输入图，不代表喷射开始时间。\n' ...
 '有效区触边包括喷嘴附近；需要人工判断是否真正截断。\n' ...
 '自动识别有效视窗，无需圈选。不使用亮度校正；旧日志参考区字段为NaN。\n' ...
 '不得直接沿用旧程序的喷嘴坐标或170/960标定。面积仅为像素面积。\n']);
 fclose(fid);
end
fprintf('结果已保存：%s\n',out);
msgbox(sprintf('处理结束。\n结果：%s\n先检查 overlay，再调整文件顶部参数。',out),'完成');
end

function a=readGray(path)
[a,map]=imread(path);
if ~isempty(map), a=ind2gray(a,map); end
if ndims(a)==3, a=rgb2gray(a); end
a=single(im2double(a)*255);
end

function rgb=paint(rgb,mask,color)
for c=1:3
    a=rgb(:,:,c); a(mask)=color(c); rgb(:,:,c)=a;
end
end

function closeIfValid(h)
if ishghandle(h), close(h); end
end
