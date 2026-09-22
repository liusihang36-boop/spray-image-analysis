function batchResult=run_validation_batch(batchRoot)
%RUN_VALIDATION_BATCH 两类喷雾混合批量验证（MATLAB R2023a）。
% analysis_mode.txt可写three_jets或merged_spray；不存在时首次确认。
if nargin<1||isempty(batchRoot)
 batchRoot=uigetdir(pwd,'选择包含多个代表性工况文件夹的上级目录');
 if isequal(batchRoot,0), batchResult=table; return; end
end
d=dir(batchRoot); d=d([d.isdir]); names=string({d.name});
d=d(names~="."&names~=".."&~startsWith(names,".")&~startsWith(names,"spray_trial_"));
valid=false(size(d)); count=zeros(size(d));
for k=1:numel(d)
 f=dir(fullfile(d(k).folder,d(k).name,'*.bmp')); count(k)=numel(f); valid(k)=count(k)>=2;
end
d=d(valid); count=count(valid); if isempty(d), error('未找到直接包含BMP的工况子文件夹。'); end
Condition=strings(0,1); AnalysisMode=strings(0,1); Object=strings(0,1); BMPCount=[]; Status=strings(0,1);
PenetrationRate=[]; ConeRate=[]; DownstreamRate=[]; AreaRate=[]; ReliableRate=[];
ValleyConfidence=[]; UnclearRate=[]; MeasurementRoot=strings(0,1); Error=strings(0,1);
for k=1:numel(d)
 condition=string(d(k).name); rawDir=fullfile(d(k).folder,d(k).name);
 fprintf('\n========== 工况 %d/%d：%s ==========\n',k,numel(d),condition);
 try
  mode=resolveMode(rawDir,condition);
  if mode~="three_jets", settingName='measurement_settings_merged.mat'; else, settingName='measurement_settings.mat'; end
  one=run_validation(rawDir,fullfile(rawDir,settingName),mode);
  s=load(fullfile(one.measurementRoot,'measurements.mat'),'T'); T=s.T;
  if mode=="three_jets"
   labels=["Left","Middle","Right"]; zh=["左束","中束","右束"];
   for j=1:3
    q=T.Jet==labels(j); n=nnz(q);
    appendRow(zh(j),rate(T.Penetration_mm(q),n),rate(T.CoreCone_deg(q),n), ...
     rate(T.CoreDown_deg(q),n),rate(T.Area_mm2(q),n),100*mean(double(T.CoreReliable(q)),'omitnan'), ...
     finiteMedian(T.CoreValleyConfidence(q)),100*mean(double(T.CoreMergeCandidate(q)),'omitnan'));
   end
  else
   n=height(T); appendRow("整体喷雾",rate(T.Penetration_mm,n),rate(T.ConeAngle_deg,n), ...
    rate(T.DownstreamAngle_deg,n),rate(T.Area_mm2,n),100*mean(double(T.Reliable),'omitnan'),NaN,NaN);
  end
 catch ME
  Condition(end+1,1)=condition; AnalysisMode(end+1,1)="未知"; Object(end+1,1)="全部"; BMPCount(end+1,1)=count(k); %#ok<AGROW>
  if strcmp(ME.identifier,'spray:Cancelled'), rethrow(ME); end
  Status(end+1,1)="失败"; PenetrationRate(end+1,1)=NaN; ConeRate(end+1,1)=NaN; DownstreamRate(end+1,1)=NaN;
  AreaRate(end+1,1)=NaN; ReliableRate(end+1,1)=NaN; ValleyConfidence(end+1,1)=NaN; UnclearRate(end+1,1)=NaN;
  MeasurementRoot(end+1,1)=""; Error(end+1,1)=string(ME.message); warning('工况%s失败：%s',condition,ME.message);
 end
end
batchResult=table(Condition,AnalysisMode,Object,BMPCount,Status,PenetrationRate,ConeRate, ...
 DownstreamRate,AreaRate,ReliableRate,ValleyConfidence,UnclearRate,MeasurementRoot,Error, ...
 'VariableNames',{'工况','分析模式','对象','BMP数量','状态','贯穿距有效率_pct','主要锥角有效率_pct', ...
 '下游角有效率_pct','面积有效率_pct','自动可靠率_pct','灰度谷置信度中位数','分界不清率_pct','测量结果目录','错误信息'});
writetable(batchResult,fullfile(batchRoot,'批量验证总表.xlsx'),'Sheet','全部工况');
save(fullfile(batchRoot,'batch_validation_result.mat'),'batchResult','batchRoot');

 function appendRow(object,pr,cr,dr,ar,rr,vc,ur)
  Condition(end+1,1)=condition; AnalysisMode(end+1,1)=mode; Object(end+1,1)=object; BMPCount(end+1,1)=count(k); %#ok<AGROW>
  Status(end+1,1)="完成"; PenetrationRate(end+1,1)=pr; ConeRate(end+1,1)=cr; DownstreamRate(end+1,1)=dr;
  AreaRate(end+1,1)=ar; ReliableRate(end+1,1)=rr; ValleyConfidence(end+1,1)=vc; UnclearRate(end+1,1)=ur;
  MeasurementRoot(end+1,1)=string(one.measurementRoot); Error(end+1,1)="";
 end
end

function mode=resolveMode(rawDir,condition)
marker=fullfile(rawDir,'analysis_mode.txt');
% 本版必须重审旧three_jets配置，不能按旧分束设置静默处理。
q=questdlg(sprintf('%s\n选择形态；多束模式支持人工确认2至8束。',condition), ...
 '重新确认喷雾模式','多束参考分析','整体喷雾','保留旧三束','多束参考分析');
if strcmp(q,'多束参考分析'),mode="multi_plume";
elseif strcmp(q,'整体喷雾'),mode="merged_spray";
elseif strcmp(q,'保留旧三束'),mode="three_jets";
else,error('spray:Cancelled','取消模式确认。');end
fid=fopen(marker,'w');if fid>=0,fprintf(fid,'%s\n',mode);fclose(fid);end
end

function v=modeLabel(mode)
if mode=="merged_spray", v="整体合并"; else, v="三束独立"; end
end
function v=rate(x,n), if n<=0, v=NaN; else, v=100*nnz(isfinite(x))/n; end, end
function v=finiteMedian(x), x=x(isfinite(x)); if isempty(x), v=NaN; else, v=median(x); end, end
