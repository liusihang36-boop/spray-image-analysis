function batchResult = run_validation_batch(batchRoot)
%RUN_VALIDATION_BATCH 批量处理代表性工况子文件夹（MATLAB R2023a）。
% 每个直接子文件夹应直接包含原始BMP。复用config/measurement_settings.mat。
% 单个工况失败会记录错误并继续，最终在batchRoot生成批量验证总表.xlsx。

repoRoot=fileparts(mfilename('fullpath'));
if nargin<1 || isempty(batchRoot)
    batchRoot=uigetdir(pwd,'选择包含多个代表性工况文件夹的上级目录');
    if isequal(batchRoot,0), batchResult=table; return; end
end
if ~isfolder(batchRoot), error('批量数据根目录不存在：%s',batchRoot); end
settingsFile=fullfile(repoRoot,'config','measurement_settings.mat');
if ~isfile(settingsFile)
    error('批量处理前必须先完成单工况标定，并保留config/measurement_settings.mat。');
end

d=dir(batchRoot); d=d([d.isdir]);
names=string({d.name});
keep=names~="." & names~=".." & ~startsWith(names,".") & ~startsWith(names,"spray_trial_");
d=d(keep);
valid=false(size(d)); bmpCount=zeros(size(d));
for k=1:numel(d)
    files=dir(fullfile(d(k).folder,d(k).name)); fileNames=string({files.name});
    bmpCount(k)=nnz(~[files.isdir] & endsWith(lower(fileNames),'.bmp'));
    valid(k)=bmpCount(k)>=2;
end
d=d(valid); bmpCount=bmpCount(valid);
if isempty(d), error('所选目录下没有直接包含至少2张BMP的工况子文件夹。'); end

Condition=strings(0,1); Jet=strings(0,1); BMPCount=[]; Status=strings(0,1); Error=strings(0,1);
PenetrationRate=[]; FormalConeRate=[]; CoreConeRate=[]; DownstreamRate=[]; CoreDownRate=[];
CoreReliableRate=[]; AxisCoverage=[]; AxisSupport=[]; BoundaryJump=[]; ValleyConfidence=[]; UnclearRate=[];
MeasurementRoot=strings(0,1);
labels=["Left","Middle","Right"]; zh=["左束","中束","右束"];

fprintf('发现%d个代表性工况，开始批量验证。\n',numel(d));
for k=1:numel(d)
    condition=string(d(k).name); rawDir=fullfile(d(k).folder,d(k).name);
    fprintf('\n========== 工况 %d/%d：%s ==========\n',k,numel(d),condition);
    try
        one=run_validation(rawDir);
        s=load(fullfile(one.measurementRoot,'measurements.mat'),'T'); T=s.T;
        for j=1:3
            q=T.Jet==labels(j); n=nnz(q);
            Condition(end+1,1)=condition; Jet(end+1,1)=zh(j); BMPCount(end+1,1)=bmpCount(k); %#ok<AGROW>
            Status(end+1,1)="完成"; Error(end+1,1)=""; MeasurementRoot(end+1,1)=string(one.measurementRoot);
            PenetrationRate(end+1,1)=rate(T.Penetration_mm(q),n); FormalConeRate(end+1,1)=rate(T.ConeAngle_deg(q),n);
            CoreConeRate(end+1,1)=rate(T.CoreCone_deg(q),n); DownstreamRate(end+1,1)=rate(T.DownstreamAngle_deg(q),n);
            CoreDownRate(end+1,1)=rate(T.CoreDown_deg(q),n);
            CoreReliableRate(end+1,1)=100*mean(double(T.CoreReliable(q)),'omitnan');
            AxisCoverage(end+1,1)=finiteMedian(T.CoreAxisCoverage(q)); AxisSupport(end+1,1)=finiteMedian(T.CoreAxisSupportFraction(q));
            BoundaryJump(end+1,1)=finiteMedian(T.CoreBoundaryJumpFraction(q)); ValleyConfidence(end+1,1)=finiteMedian(T.CoreValleyConfidence(q));
            UnclearRate(end+1,1)=100*mean(double(T.CoreMergeCandidate(q)),'omitnan');
        end
    catch ME
        Condition(end+1,1)=condition; Jet(end+1,1)="全部"; BMPCount(end+1,1)=bmpCount(k); %#ok<AGROW>
        Status(end+1,1)="失败"; Error(end+1,1)=string(ME.message); MeasurementRoot(end+1,1)="";
        PenetrationRate(end+1,1)=NaN; FormalConeRate(end+1,1)=NaN; CoreConeRate(end+1,1)=NaN;
        DownstreamRate(end+1,1)=NaN; CoreDownRate(end+1,1)=NaN; CoreReliableRate(end+1,1)=NaN;
        AxisCoverage(end+1,1)=NaN; AxisSupport(end+1,1)=NaN; BoundaryJump(end+1,1)=NaN;
        ValleyConfidence(end+1,1)=NaN; UnclearRate(end+1,1)=NaN;
        warning('工况%s失败，已继续下一个：%s',condition,ME.message);
    end
end

batchResult=table(Condition,Jet,BMPCount,Status,PenetrationRate,FormalConeRate,CoreConeRate, ...
    DownstreamRate,CoreDownRate,CoreReliableRate,AxisCoverage,AxisSupport,BoundaryJump, ...
    ValleyConfidence,UnclearRate,MeasurementRoot,Error, ...
    'VariableNames',{'工况','喷束','BMP数量','状态','贯穿距有效率_pct','正式锥角有效率_pct', ...
    '灰度主体锥角有效率_pct','下游可见角有效率_pct','灰度主体下游角有效率_pct', ...
    '灰度主体可靠率_pct','轴向覆盖率中位数','轴线支撑比例中位数','边界跳变比例中位数', ...
    '灰度谷置信度中位数','分界不清率_pct','测量结果目录','错误信息'});
reportFile=fullfile(batchRoot,'批量验证总表.xlsx');
writetable(batchResult,reportFile,'Sheet','全部工况');
save(fullfile(batchRoot,'batch_validation_result.mat'),'batchResult','batchRoot');
fprintf('\n批量验证完成：%s\n',reportFile);
end

function value=rate(x,n)
if n<=0, value=NaN; else, value=100*nnz(isfinite(x))/n; end
end

function value=finiteMedian(x)
x=x(isfinite(x));
if isempty(x), value=NaN; else, value=median(x); end
end
