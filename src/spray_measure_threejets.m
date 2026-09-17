function out = spray_measure_threejets(root,settingsFile,rawOverride)
% 三束喷雾参数测量首版。MATLAB + Image Processing Toolbox。
% 将本文件放入当前文件夹，运行 spray_measure_threejets。
% 输入：预处理结果目录（内含6、settings.mat、processing_log.csv）。
% 每次输入喷嘴X/Y；第一张背景排除，第二张记0 ms；25000 fps，无抽帧。
% 标定：170 mm通光直径；自动拟合外缘后必须确认，不能把图宽当直径。
% 分束：在清晰参考帧点击左/中/右方向，固定角度扇区贯穿全序列。
% 结果是二维投影测量；无法自动保证重叠喷雾的真实喷束归属。
% 不拟合/补全被遮挡部分，不平滑原始测量，不计算卷吸量。
% 锥角定义：在各束轴向坐标z=0.5*S处取两侧边界，S为最大径向贯穿距。
% 横截面以有限像素带近似，宽度由带内逐截面宽度的中位数得到。
% 未连接喷嘴、触边、接触分区边界、截面缺失等均记录，不强制造出角度。

out='';
p.codeVersion="20260917_core_sweep_3";
p.requireRawOverlay=true; % 当前验证阶段必须叠加原图；正式仅二值测量可改false
p.coreContrast=0.45; % 本验证集敏感性扫描后采用；候选阈值仍全部保留用于监控
p.coreContrastCandidates=[0.30 0.35 0.40 0.45];
p.coreMinArea=8; % 去除孤立噪点，不填充束间空隙
p.fps=25000;
p.fitRange=[0.60 0.85]; % 新增边界拟合角的固定轴向区间，不代替原半贯穿距角
p.fitMinRows=15; p.fitMinCoverage=0.60;
p.fitMaxRMSE_px=3; % 试用门限，不能视为精度保证
p.jumpAbs_mm=3; p.jumpRel=0.15; % 相邻帧突变复核阈值，不改写长度
p.tipSupportRadius_px=5; % 前端半径5像素内的同束像素支撑
p.tipSmallComponent_px=20; % 局部圆内支撑不足时标记，不直接删除
p.analysisEnd_ms=5; % 仅输出0~5ms，包含两端
p.windowDiameter_mm=170;
p.minPixels=60;              % 少于此值，该束标记too_small，数值保持NaN
p.halfBand_px=2;             % 半贯穿距截面半带宽，最少需有2个有效截面
p.minSections=2;
p.nozzleCheckRadius_px=25;   % 喷雾近喷嘴检查半径；用于锥角有效性检查
p.sectorGuard_deg=1;         % 分区边界附近像素比例，用于提示可能交叠
p.sectorContactFraction=0.02;
p.overlayEvery=1;           % 每5个输入帧保存一张叠加图，可改1
p.outerEdges_deg=[-90 90];   % 相对图像竖直向下方向，分析下半平面
if nargin<1 || isempty(root)
 root=uigetdir(pwd,'选择预处理结果目录（包含6和settings.mat）');
 if isequal(root,0), return; end
end
sf=fullfile(root,'settings.mat');
if ~isfile(sf)||~isfolder(fullfile(root,'6'))
 error('请选择包含 settings.mat 和 6 子文件夹的预处理结果目录。');
end
s=load(sf,'B','valid','p'); B=s.B; valid=logical(s.valid); [h,w]=size(B);
if ~isequal(size(valid),[h w]), error('背景与有效区域尺寸不一致。'); end
% 从处理日志保留完整输入顺序，避免失败/取消造成时间轴压缩。
lf=fullfile(root,'processing_log.csv');
if ~isfile(lf), error('需要processing_log.csv确定原始帧号及缺失帧。'); end
L=readtable(lf,'TextType','string');
[ids,order]=sort(double(L.FrameID)); L=L(order,:); names=cellstr(L.File);
if numel(ids)<2||numel(unique(ids))~=numel(ids), error('至少需要2帧且帧号不能重复。'); end
if ids(2)~=ids(1)+1, error('日志首两帧不连续，不能确定第二原始帧时间零点。'); end
zeroID=ids(2);
if isfield(s,'p') && isfield(s.p,'zeroFrameID'), zeroID=s.p.zeroFrameID; end
keep=(ids==ids(1)) | ((ids-zeroID)*1000/p.fps>=0 & (ids-zeroID)*1000/p.fps<=p.analysisEnd_ms+1e-9);
ids=ids(keep); names=names(keep);

savedMode=nargin>=2 && ~isempty(settingsFile) && isfile(settingsFile);
colors=[0 .6 1;0 .85 .25;1 .5 0];
if savedMode
 cfg=load(settingsFile,'calibration','x0','y0','angles','edges','rf','autoXY','nozzleInfo');
 required={'calibration','x0','y0','angles','edges'};
 if ~all(isfield(cfg,required)), error('固定测量配置缺少必要字段，请重新进行首次标定。'); end
 calibration=cfg.calibration; x0=double(cfg.x0); y0=double(cfg.y0);
 angles=double(cfg.angles(:)); edges=double(cfg.edges(:)');
 if numel(angles)~=3||numel(edges)~=4||any(~isfinite([x0;y0;angles;edges(:)]))|| ...
   any(diff(angles)<=0)||any(diff(edges)<=0)||any(angles<=edges(1:3)')||any(angles>=edges(2:4)')
  error('固定配置中的喷嘴、束轴或分界参数无效。');
 end
 if ~isfield(calibration,'mm_per_pixel')||~isfinite(calibration.mm_per_pixel)||calibration.mm_per_pixel<=0
  error('固定配置中的长度标定无效。');
 end
 scale=double(calibration.mm_per_pixel);
 if isfield(cfg,'rf'), rf=cfg.rf; else, rf='saved_configuration'; end
 rp=fullfile(root,'6');
 if isfield(cfg,'autoXY'), autoXY=cfg.autoXY; else, autoXY=[nan nan]; end
 if isfield(cfg,'nozzleInfo'), nozzleInfo=cfg.nozzleInfo; else, nozzleInfo=struct; end
 if nargin>=3 && ~isempty(rawOverride), raw=rawOverride; else, raw=fileparts(root); end
 useRaw=isfolder(raw);
 if ~useRaw, error('固定验证的原始BMP目录不存在：%s',raw); end

 % 自动模式仍保存三张检查图，供每次运行后追溯固定配置。
 f=figure('Visible','off','Color','w'); imshow(B,[0 255]); hold on;
 t=linspace(0,2*pi,500); cr=calibration.diameter_px/2; cc=calibration.center_xy;
 plot(cc(1)+cr*cos(t),cc(2)+cr*sin(t),'g-','LineWidth',1.5);
 title(sprintf('复用标定：%.6f mm/px',calibration.mm_per_pixel));
 nf=figure('Visible','off','Color','w'); imshow(B,[0 255]); hold on;
 plot(x0,y0,'g+','MarkerSize',18,'LineWidth',1.5); plot(x0,y0,'go','MarkerSize',10);
 title(sprintf('复用喷嘴坐标：X=%.2f，Y=%.2f',x0,y0));
 g=figure('Visible','off','Color','w'); imshow(B,[0 255]); hold on;
 for jj=1:3
  plot([x0 x0+h*sind(angles(jj))],[y0 y0+h*cosd(angles(jj))],'-','Color',colors(jj,:));
 end
 for jj=2:3
  plot([x0 x0+h*sind(edges(jj))],[y0 y0+h*cosd(edges(jj))],'m--','LineWidth',1.5);
 end
 title(sprintf('复用分界：%.1f / %.1f 度',edges(2),edges(3)));
else

% 自动拟合视窗外轮廓：凸包顶点减少风扇等向内遮挡的干扰。
% 自动结果仅为候选；视窗是椭圆/外圆弧不足时，请取消并核对拍摄几何。
% 标定使用未向内腐蚀的背景亮区；与喷雾有效掩膜分开。
calMask=bwareafilt(B>30,1);
[cyx,r,fitRMSE]=fitWindow(calMask);
calMethod='automatic_uneroded_hull'; selectedPoints=[];
f=figure('Name','170 mm视窗标定检查','Color','w');
imshow(B,[0 255]); hold on;
t=linspace(0,2*pi,500);
plot(cyx(1)+r*cos(t),cyx(2)+r*sin(t),'g-','LineWidth',1.5);
title(sprintf('拟合直径 %.2f px；外包络残差 %.2f px；请检查绿色圆',2*r,fitRMSE));
choice=questdlg('检查真实外圆弧；遮挡内部边界不应贴合绿色圆。', ...
 '标定方式','采用自动圆','手选外圆弧点','取消','采用自动圆');
if isempty(choice)||strcmp(choice,'取消'), close(f); return; end
if strcmp(choice,'手选外圆弧点')
 figure(f); cla; imshow(B,[0 255]); hold on;
 title({'在真实外圆弧上点击6点，分布于上/下/左/右；第6点后自动拟合', ...
 '避开风扇轮廓、局部凸起及喷嘴遮挡；不要只点一侧'});
 px=zeros(6,1); py=zeros(6,1);
 for pointIndex=1:6
  if ~ishghandle(f), return; end
  title(sprintf('点击第 %d / 6 个外圆弧点；选满6点自动拟合，回车可取消',pointIndex));
  drawnow;
  try
   [pointX,pointY,button]=ginput(1);
  catch ME
   if ~ishghandle(f), return; end
   rethrow(ME);
  end
  if isempty(pointX), safeClose(f); return; end
  if button~=1, safeClose(f); return; end
  px(pointIndex)=pointX; py(pointIndex)=pointY;
  plot(pointX,pointY,'y+','MarkerSize',10,'LineWidth',1.5);
  text(pointX+5,pointY,sprintf('%d',pointIndex),'Color','y');
  drawnow;
 end
 A=[2*px,2*py,ones(size(px))];
 if rank(A)<3, close(f); error('选点退化，无法拟合圆。'); end
 c=A\(px.^2+py.^2); cyx=c(1:2)'; r=sqrt(c(3)+sum(cyx.^2));
 if ~isreal(r)||~isfinite(r)||r<=0, close(f); error('拟合失败，请重新选点。'); end
 a=sort(mod(atan2(py-cyx(2),px-cyx(1)),2*pi));
 if max(diff([a;a(1)+2*pi]))>pi
  close(f); error('选点覆盖不足，请让点分布于视窗四周。');
 end
 fitRMSE=sqrt(mean((hypot(px-cyx(1),py-cyx(2))-r).^2));
 selectedPoints=[px py]; calMethod='manual_arc_points';
 plot(px,py,'y+','MarkerSize',9);
 plot(cyx(1)+r*cos(t),cyx(2)+r*sin(t),'g-','LineWidth',1.5);
 title(sprintf('外圆弧点拟合直径 %.2f px；点残差 %.2f px；不吻合请取消',2*r,fitRMSE));
 drawnow;
end
answer=inputdlg({'视窗直径(mm)：','对应像素直径(px)，可修正候选值：'}, ...
 '确认圆形视窗标定；不吻合请取消',1,{num2str(p.windowDiameter_mm),sprintf('%.4f',2*r)});
if isempty(answer), close(f); return; end
physical=str2double(answer{1}); diam=str2double(answer{2});
if ~isfinite(physical)||~isfinite(diam)||physical<=0||diam<=0
 close(f); error('标定长度和像素直径必须为有限正数。');
end
figure(f); plot(cyx(1)+(diam/2)*cos(t),cyx(2)+(diam/2)*sin(t),'b--');
title(sprintf('绿色：拟合圆；蓝色：采用直径 %.2f px；%.6f mm/px',diam,physical/diam));
scale=physical/diam;
calibration=struct('diameter_mm',physical,'diameter_px',diam,'mm_per_pixel',scale, ...
 'center_xy',cyx,'fitted_radius_px',r,'fit_rmse_px',fitRMSE, ...
 'method',calMethod,'selected_points_xy',selectedPoints, ...
 'basis','window_plane_not_spray_plane','user_confirmed',true);
% 早期喷雾近端估计：候选不是被遮挡的真实出口测量值。
[autoXY,nozzleInfo]=estimateNozzle(root,names,[h w],cyx,r);
nf=figure('Name','喷嘴候选坐标检查','Color','w');
imshow(B,[0 255]); hold on;
if all(isfinite(autoXY))
 plot(autoXY(1),autoXY(2),'r+','MarkerSize',16,'LineWidth',2);
 title(sprintf('红十字：自动近端候选 X=%.1f Y=%.1f；遮挡时请修正',autoXY));
 defaults={sprintf('%.2f',autoXY(1)),sprintf('%.2f',autoXY(2))};
else
 title('未找到稳定近端候选，请输入原图喷嘴坐标');
 defaults={'',''};
end
% 输入后必须预览并明确确认；修改时保留上次输入。
while true
 answer=inputdlg({'喷嘴X（列；自动值可修改）：','喷嘴Y（行；自动值可修改）：'}, ...
  '输入喷嘴出口坐标，左上角为(1,1)',1,defaults);
 if isempty(answer), safeClose(f); safeClose(nf); return; end
 x0=str2double(answer{1}); y0=str2double(answer{2});
 defaults=answer;
 if any(~isfinite([x0 y0]))||x0<1||x0>w||y0<1||y0>h
  uiwait(errordlg('喷嘴坐标必须为图像范围内的有限数值，请重新输入。','坐标错误'));
  continue;
 end
 if ~ishghandle(nf)
  nf=figure('Name','喷嘴坐标预览','Color','w');
 end
 figure(nf); clf(nf); set(nf,'Position',[100 150 1200 620]);
 for panel=1:2
  subplot(1,2,panel); imshow(B,[0 255]); hold on;
  if all(isfinite(autoXY))
   plot(autoXY(1),autoXY(2),'r+','MarkerSize',14,'LineWidth',1.5);
  end
  plot(x0,y0,'g+','MarkerSize',18,'LineWidth',1.5);
  plot(x0,y0,'go','MarkerSize',10,'LineWidth',1);
  if panel==1
   title('全图：红色为自动候选，绿色为本次输入');
  else
   xlim([max(.5,x0-60),min(w+.5,x0+60)]);
   ylim([max(.5,y0-60),min(h+.5,y0+60)]);
   axis on; grid on; xlabel('X / 列'); ylabel('Y / 行');
   title(sprintf('局部放大：X=%.2f，Y=%.2f',x0,y0));
  end
 end
 drawnow;
 confirmNozzle=questdlg('请检查绿色标记是否位于喷嘴出口。', ...
  '喷嘴坐标预览确认','确认使用','重新修改','取消','重新修改');
 if strcmp(confirmNozzle,'确认使用') && ishghandle(nf)
  break;
 elseif strcmp(confirmNozzle,'重新修改')
  continue;
 else
  safeClose(f); safeClose(nf); return;
 end
end
[rf,rp]=uigetfile(fullfile(root,'6','*.bmp'),'选择三束清晰的参考二值图（例如Img000074）');
if isequal(rf,0), close(f); return; end
R=readMask(fullfile(rp,rf),[h w]);
g=figure('Name','设置三个喷束方向','Color','w');
reselect=true;
reuse=questdlg('同一批图像复核时建议复用上次束轴和分界，避免重复点击改变测量条件。', ...
 '分区参数','读取上次设置','重新选点','读取上次设置');
if strcmp(reuse,'读取上次设置')
 [cfgName,cfgDir]=uigetfile('*.mat','选择上次 measurement_settings.mat');
 if ~isequal(cfgName,0)
  cfg=load(fullfile(cfgDir,cfgName),'angles','edges','x0','y0');
  if ~all(isfield(cfg,{'angles','edges','x0','y0'}))
   error('设置文件缺少束轴、分界或喷嘴坐标。');
  end
  angles=double(cfg.angles(:)); edges=double(cfg.edges(:)');
  if numel(angles)~=3||numel(edges)~=4||any(~isfinite([angles;edges(:)]))|| ...
    any(diff(angles)<=0)||any(diff(edges)<=0)||any(angles<=edges(1:3)')||any(angles>=edges(2:4)')
   error('设置中的束轴或分区范围无效。');
  end
  if hypot(cfg.x0-x0,cfg.y0-y0)>1
   uiwait(warndlg('本次喷嘴与上次相差超过1像素，请在分区预览中核对。'));
  end
  reselect=false;
 end
end
while true
 if ~ishghandle(g), safeClose(f); safeClose(nf); return; end
 figure(g);
 if reselect
  clf(g); imshow(R); hold on;
  plot(x0,y0,'ro'); title('依次点击左、中、右束中心方向上的点；共3点');
  try
   [xc,yc]=ginput(3);
  catch ME
   if ~ishghandle(g), safeClose(f); safeClose(nf); return; end
   rethrow(ME);
  end
  if numel(xc)~=3, safeClose(f); safeClose(nf); safeClose(g); return; end
  candidateAngles=atan2d(xc-x0,yc-y0);
  if any(yc<=y0)||any(hypot(xc-x0,yc-y0)<10)||any(diff(candidateAngles)<=3)
   uiwait(errordlg('方向点应在喷嘴下方，按左中右顺序至少间隔3度，请重新选择。'));
   continue;
  end
  angles=candidateAngles;
  edges=[p.outerEdges_deg(1),mean(angles(1:2)),mean(angles(2:3)),p.outerEdges_deg(2)];
  reselect=false;
 end
 clf(g); imshow(R); hold on;
 for j=1:3
  plot([x0 x0+h*sind(angles(j))],[y0 y0+h*cosd(angles(j))],'-','Color',colors(j,:));
 end
 for j=2:3
  plot([x0 x0+h*sind(edges(j))],[y0 y0+h*cosd(edges(j))],'m--','LineWidth',1.5);
 end
 plot(x0,y0,'ro');
 title(sprintf('彩色：束轴；紫色：分界 %.1f / %.1f 度；确认后用于全序列',edges(2),edges(3)));
 drawnow;
 q=questdlg('分界是否落在三束之间？','分束预览', ...
  '确认使用','重新修改','取消','重新修改');
 if strcmp(q,'确认使用') && ishghandle(g)
  break;
 elseif strcmp(q,'重新修改')
  mode=questdlg('选择修改方式。','修改分束','重选三束方向','只改分界角度','返回预览','只改分界角度');
  if strcmp(mode,'重选三束方向')
   reselect=true;
  elseif strcmp(mode,'只改分界角度')
   v=inputdlg({'左束与中束分界角度（度）：','中束与右束分界角度（度）：'}, ...
    '相对竖直向下方向：向左为负，向右为正',1, ...
    {sprintf('%.3f',edges(2)),sprintf('%.3f',edges(3))});
   if ~isempty(v)
    bounds=[str2double(v{1}),str2double(v{2})];
    if any(~isfinite(bounds)) || ~(angles(1)<bounds(1) && bounds(1)<angles(2) && ...
      angles(2)<bounds(2) && bounds(2)<angles(3))
     uiwait(errordlg('每条分界必须位于对应的两条喷束参考轴之间；未应用修改。'));
    else
     edges(2:3)=bounds;
    end
   end
  end
 else
  safeClose(f); safeClose(nf); safeClose(g); return;
 end
end
% 原图目录必须确实含当前序列原图，不能静默将错误目录当二值底图。
raw=''; useRaw=false;
while true
 candidateRaw=uigetdir(fileparts(root),'选择原始BMP目录；取消可明确选择二值预览');
 if isequal(candidateRaw,0)
  if p.requireRawOverlay
   safeClose(f); safeClose(nf); safeClose(g);
   msgbox('本次为原图核查模式，取消原图选择后停止测量。请重新运行并选择原始BMP目录。'); return;
  end
  choice=questdlg('二值底图不能核查真实灰度边界。是否仍仅测量二值图？','预览底图', ...
   '仅二值测量','重新选择','重新选择');
  if strcmp(choice,'仅二值测量'), break; else, continue; end
 end
 checkName=names{min(numel(names),52)};
 checkPath=fullfile(candidateRaw,checkName);
 if ~isfile(checkPath)
  uiwait(errordlg(['该目录缺少代表帧：' checkName '。请选直接包含原始BMP的目录。'])); continue;
 end
 preview=imread(checkPath);
 if size(preview,1)~=h||size(preview,2)~=w||numel(unique(preview(:)))<=3
  uiwait(errordlg('图像尺寸不符或像二值图，请选择原始灰度BMP目录。')); continue;
 end
 raw=candidateRaw; useRaw=true; break;
end
if useRaw
 missingRaw=names(~cellfun(@(name)isfile(fullfile(raw,name)),names));
 if ~isempty(missingRaw), error('原图目录缺少文件，例如 %s。未开始测量。',missingRaw{1}); end
end
end
% 自动复用模式同样必须逐帧核对原图完整性。
if savedMode
 missingRaw=names(~cellfun(@(name)isfile(fullfile(raw,name)),names));
 if ~isempty(missingRaw), error('原图目录缺少文件，例如 %s。未开始测量。',missingRaw{1}); end
end
out=fullfile(root,['measure_threejets_' datestr(now,'yyyymmdd_HHMMSS')]);
while isfolder(out), out=[out '_new']; end %#ok<AGROW>
mkdir(out); mkdir(fullfile(out,'overlay')); mkdir(fullfile(out,'section_samples'));
sourcePath=[mfilename('fullpath') '.m'];
copyfile(sourcePath,fullfile(out,'executed_spray_measure_threejets.m'));
manifest={'项目','值';'代码版本',char(p.codeVersion);'执行源文件',sourcePath; ...
 '原图叠加',double(useRaw);'原图目录',raw;'输入目录',root; ...
 '零时刻帧号',zeroID;'帧率',p.fps;'终止时间_ms',p.analysisEnd_ms; ...
 '束轴_deg',mat2str(angles,12);'分界_deg',mat2str(edges,12); ...
 '喷嘴XY_px',mat2str([x0 y0],12);'最大宽度定义','轴交连续段宽度最大值；原包络宽度另存诊断'};
writeUtf8Csv(manifest,fullfile(out,'运行记录.csv'));
saveas(f,fullfile(out,'calibration_check.png')); close(f);
saveas(nf,fullfile(out,'nozzle_check.png')); close(nf);
saveas(g,fullfile(out,'partition_check.png')); close(g);
save(fullfile(out,'measurement_settings.mat'),'p','calibration','x0','y0','angles','edges','rf','rp','zeroID','names','ids','autoXY','nozzleInfo','raw','useRaw');

N=numel(ids)-1; K=N*3;
File=repelem(string(names(2:end)),3,1); FrameID=repelem(ids(2:end),3,1);
Time_ms=(FrameID-zeroID)*1000/p.fps;
Jet=repmat(["Left";"Middle";"Right"],N,1);
S=nan(K,1); Z=S; Area=S; Angle=S; Width=S; MaxWidth=S;
DownstreamAngle=S; DownstreamCandidate=S; FitAngle=S; FitCandidate=S; FitRMSE=S; FitCoverage=S;
FitStatus=repmat("未计算",K,1); TipComponent=S; BaselineS=S; DownRange=S; EnvelopeWidth=S; MaxWidthBlocked=false(K,1);
CoreCone=S; CoreDown=S; CoreLength=S; CoreStatus=repmat("未计算",K,1);
CoreLeftHalf=S; CoreRightHalf=S;
CoreThresholds=p.coreContrastCandidates(:)'; Q=numel(CoreThresholds);
[~,CoreSelectedIndex]=min(abs(CoreThresholds-p.coreContrast));
CoreSweepCone=nan(K,Q); CoreSweepDown=nan(K,Q); CoreSweepLength=nan(K,Q);
CoreSweepLeftHalf=nan(K,Q); CoreSweepRightHalf=nan(K,Q);
AngleCandidate=S; TipTouch=false(K,1); TipSector=false(K,1);
SectionTouch=false(K,1); SectionSector=false(K,1);
Touch=false(K,1); SectorContact=false(K,1); Detached=false(K,1);
Usable=false(K,1); Status=repmat("not_processed",K,1); Error=repmat("",K,1);
IgnoredPixels=nan(N,1);
physicalEdge=valid & ~imerode(valid,strel('disk',2,0));
bar=waitbar(0,'三束测量；关闭进度窗口停止');
clean=onCleanup(@()safeClose(bar)); %#ok<NASGU>
fig=figure('Visible','off','Color','w','Position',[100 100 900 900]);
cleanFig=onCleanup(@()safeClose(fig)); %#ok<NASGU>
for i=1:N
 if ~ishghandle(bar), break; end
 fi=i+1; rr=(i-1)*3+(1:3);
 try
  path=fullfile(root,'6',names{fi});
  if ~isfile(path)
   Status(rr)="missing_mask"; Error(rr)="预处理输出缺失";
   waitbar(i/N,bar); continue;
  end
  M=readMask(path,[h w]); M=M & valid;
  coreMasks=cell(1,Q);
  if useRaw
   sourceImage=imread(fullfile(raw,names{fi}));
   if size(sourceImage,3)==3, sourceImage=rgb2gray(sourceImage); end
   if ~isa(sourceImage,'uint8'), error('灰度主体模块当前要求8位原图，不能自动改变灰度尺度。'); end
   sourceImage=single(sourceImage);
   weights=imgaussfilt(single(valid),0.8,'FilterSize',7,'Padding','replicate');
   residual=imgaussfilt((single(B)-sourceImage).*single(valid),0.8,'FilterSize',7,'Padding','replicate')./max(weights,1e-6);
   contrast=max(residual,0)./max(single(B),1);
   for qc=1:Q
    coreMasks{qc}=bwareaopen(valid & contrast>=CoreThresholds(qc),p.coreMinArea,8);
   end
  end
  [yy,xx]=find(M); dx=double(xx)-x0; dy=double(yy)-y0;
  theta=atan2d(dx,dy); rad=hypot(dx,dy);
  labels=zeros(numel(xx),1); tips=nan(3,2); ends=nan(3,4); fitLines=cell(3,1); edgeSamples=cell(3,1);
  baselinePath=fullfile(root,'baseline_mask',names{fi});
  baseline=[];
  if isfile(baselinePath), baseline=readMask(baselinePath,[h w]) & valid; end
  for j=1:3
   m=theta>=edges(j)&theta<edges(j+1)&dy>0;
   if j==3, m=theta>=edges(j)&theta<=edges(j+1)&dy>0; end
   labels(m)=j; row=rr(j);
   if ~any(m), Status(row)="no_foreground"; continue; end
   if nnz(m)<p.minPixels, Status(row)="too_small"; continue; end
   Status(row)="ok";
   xxj=xx(m); yyj=yy(m); dxj=dx(m); dyj=dy(m); rj=rad(m);
   [rmax,it]=max(rj); tips(j,:)=[xxj(it),yyj(it)];
   ax=[sind(angles(j)),cosd(angles(j))]; normal=[cosd(angles(j)),-sind(angles(j))];
   z=dxj*ax(1)+dyj*ax(2); u=dxj*normal(1)+dyj*normal(2);
   if ~isempty(baseline)
    bm=baseline(sub2ind([h w],yyj,xxj));
    if any(bm), BaselineS(row)=max(rj(bm))*scale; end
   end
   S(row)=rmax*scale; Z(row)=max(z)*scale; Area(row)=nnz(m)*scale^2;
   % 近喷嘴触边通常为正常遮挡，仍记录，但只用远离喷嘴的触边影响有效性。
   ind=sub2ind([h w],yyj,xxj);
   Touch(row)=any(physicalEdge(ind)&rj>p.nozzleCheckRadius_px);
   internal=edges(2:3); dtheta=min(abs(theta(m)-internal),[],2);
   SectorContact(row)=mean(dtheta(rj>p.nozzleCheckRadius_px)<p.sectorGuard_deg)>p.sectorContactFraction;
   Detached(row)=~any(rj<=p.nozzleCheckRadius_px);
   TipComponent(row)=nnz(hypot(xxj-xxj(it),yyj-yyj(it))<=p.tipSupportRadius_px);
   % 保留最远点测量，不静默替换；支撑不足使角度无效并写入状态。
   if TipComponent(row)<p.tipSmallComponent_px
    Status(row)=Status(row)+";tip_local_support_low";
   end
   TipTouch(row)=physicalEdge(ind(it));
   tipTheta=atan2d(dxj(it),dyj(it));
   TipSector(row)=min(abs(tipTheta-edges(2:3)))<=p.sectorGuard_deg;
   % 最大横向宽度：按1像素轴向截面，防止直接混合不同轴向位置。
   iz=round(z); [~,~,grp]=unique(iz);
   lo=accumarray(grp,u,[],@min); hi=accumarray(grp,u,[],@max);
   EnvelopeWidth(row)=max(hi-lo)*scale; % 旧算法包络量，仅存诊断
   bestWidth=-Inf; bestEnds=[];
   for izrow=reshape(unique(iz),1,[])
    seg=axisSegment(sort(u(iz==izrow)));
    if numel(seg)<3, continue; end
    widthNow=seg(end)-seg(1);
    if widthNow>bestWidth
     bestWidth=widthNow;
     bestEnds=[x0 y0]+izrow*ax+[seg(1);seg(end)]*normal;
    end
   end
   if isfinite(bestWidth)
    MaxWidth(row)=bestWidth*scale;
    bt=atan2d(bestEnds(:,1)-x0,bestEnds(:,2)-y0);
    MaxWidthBlocked(row)=endpointBlocked(bestEnds,physicalEdge)|| ...
     any(min(abs(bt-edges(2:3)),[],2)<=p.sectorGuard_deg);
   end
   if useRaw
    coreSamples=[];
    for qc=1:Q
     [CoreSweepCone(row,qc),CoreSweepDown(row,qc),CoreSweepLength(row,qc),coreStatusNow,coreSamplesNow, ...
      CoreSweepLeftHalf(row,qc),CoreSweepRightHalf(row,qc)]= ...
      measureGrayCore(coreMasks{qc},x0,y0,angles(j),edges,j,physicalEdge,p,scale);
     if abs(CoreThresholds(qc)-p.coreContrast)<1e-9
      CoreCone(row)=CoreSweepCone(row,qc); CoreDown(row)=CoreSweepDown(row,qc);
      CoreLength(row)=CoreSweepLength(row,qc); CoreStatus(row)=coreStatusNow;
      CoreLeftHalf(row)=CoreSweepLeftHalf(row,qc); CoreRightHalf(row)=CoreSweepRightHalf(row,qc);
      coreSamples=coreSamplesNow;
     end
    end
    [~,coreStem]=fileparts(names{fi});
    writeUtf8Csv([{'左端X_px','左端Y_px','右端X_px','右端Y_px','剔除代码'};num2cell(reshape(coreSamples,[],5))], ...
     fullfile(out,'section_samples',sprintf('%s_core_jet%d.csv',coreStem,j)));
   end
   station=.5*rmax; sections=(ceil(station-p.halfBand_px):floor(station+p.halfBand_px))';
   left=[]; right=[];
   for q=1:numel(sections)
    cross=iz==sections(q);
    if nnz(cross)>=2
     segment=axisSegment(sort(u(cross)));
     if numel(segment)<3, continue; end
     left(end+1)=min(segment); right(end+1)=max(segment); %#ok<AGROW>
    end
   end
   [FitCandidate(row),FitRMSE(row),FitCoverage(row),FitStatus(row),fitLines{j},DownstreamCandidate(row),edgeSamples{j}]= ...
    fitVisibleEdges(z,u,x0,y0,ax,normal,edges,physicalEdge,[h w],p);
   if ~TipTouch(row)&&~TipSector(row)&&~Detached(row)&&TipComponent(row)>=p.tipSmallComponent_px
    DownstreamAngle(row)=DownstreamCandidate(row);
   elseif isfinite(DownstreamCandidate(row))
    FitStatus(row)=FitStatus(row)+"；前端触边/局部支撑不足/近喷嘴未连接，角度未采用";
   end
   if numel(left)>=p.minSections
    ul=median(left); ur=median(right);
    Width(row)=(ur-ul)*scale;
    e1=[x0 y0]+station*ax+ul*normal; e2=[x0 y0]+station*ax+ur*normal;
    ends(j,:)=[e1 e2];
    AngleCandidate(row)=atan2d(ur,station)-atan2d(ul,station);
    endpointTheta=[atan2d(e1(1)-x0,e1(2)-y0),atan2d(e2(1)-x0,e2(2)-y0)];
    SectionSector(row)=any(min(abs(endpointTheta(:)-edges(2:3)),[],2)<=p.sectorGuard_deg);
    % 仅检查已选连续段的两个端点，不让被剔除分支触边污染判据。
    SectionTouch(row)=endpointBlocked([e1;e2],physicalEdge);
    if ~Detached(row)&&~SectionTouch(row)&&~SectionSector(row)&&~TipTouch(row)&&~TipSector(row)&&TipComponent(row)>=p.tipSmallComponent_px
     Angle(row)=AngleCandidate(row);
    end
   else
    Status(row)=Status(row)+";no_half_section";
   end
   sample=edgeSamples{j};
   if ~isempty(sample)
    q=sample(:,5)==0; endpoints=sample(q,1:4);
    if ~isempty(endpoints)
     va=atan2d(endpoints(:,3)-x0,endpoints(:,4)-y0)-atan2d(endpoints(:,1)-x0,endpoints(:,2)-y0);
     DownRange(row)=max(va)-min(va);
    end
   end
   [~,sampleStem]=fileparts(names{fi});
   sampleHead={'左端X_px','左端Y_px','右端X_px','右端Y_px','剔除代码_0有效_1断开_2分界_3遮挡'};
   writeUtf8Csv([sampleHead;num2cell(reshape(sample,[],5))], ...
    fullfile(out,'section_samples',sprintf('%s_jet%d.csv',sampleStem,j)));
   if Touch(row), Status(row)=Status(row)+";window_touch"; end
   if SectorContact(row), Status(row)=Status(row)+";sector_contact"; end
   if Detached(row), Status(row)=Status(row)+";detached"; end
   Usable(row)=~Touch(row)&&~SectorContact(row); % 长度/面积初步质量标记，仍需复核
  end
  % 与导出阶段采用相同突变规则，确保预览和正式角度一致。
  for j=1:3
   cur=rr(j); prev=cur-3;
   if prev>=1 && FrameID(cur)==FrameID(prev)+1 && isfinite(S(cur)) && isfinite(S(prev))
    if abs(S(cur)-S(prev))>max(p.jumpAbs_mm,p.jumpRel*S(prev))
     Angle(cur)=NaN; DownstreamAngle(cur)=NaN;
     FitStatus(cur)=FitStatus(cur)+"；贯穿距突变，角度未采用";
    end
   end
  end
  for j=1:3
   cur=rr(j); prev=cur-3;
   if prev>=1 && FrameID(cur)==FrameID(prev)+1 && isfinite(CoreLength(cur)) && isfinite(CoreLength(prev))
    if abs(CoreLength(cur)-CoreLength(prev))>max(p.jumpAbs_mm,p.jumpRel*CoreLength(prev))
     CoreCone(cur)=NaN; CoreDown(cur)=NaN;
     CoreStatus(cur)=CoreStatus(cur)+"；主体贯穿距突变，角度未采用";
    end
   end
  end
  IgnoredPixels(i)=sum(labels==0);
  if mod(i-1,p.overlayEvery)==0||i==N
   figure(fig); clf(fig);
   rawpath=''; if useRaw, rawpath=fullfile(raw,names{fi}); end
   if useRaw&&isfile(rawpath)
    bg=imread(rawpath);
    if size(bg,1)~=h||size(bg,2)~=w, error('叠加原图尺寸不同。'); end
    imshow(bg);
   elseif useRaw
    error('原图目录缺少当前帧：%s',names{fi});
   else
    imshow(M);
   end
   hold on; contour(coreMasks{CoreSelectedIndex},[.5 .5],'y:');
   contour(valid,[.5 .5],'c-');
   for j=1:3
    J=false(h,w); m=labels==j; J(sub2ind([h w],yy(m),xx(m)))=true;
    contour(J,[.5 .5],'Color',colors(j,:));
    plot([x0 x0+h*sind(angles(j))],[y0 y0+h*cosd(angles(j))],'--','Color',colors(j,:));
    if all(isfinite(tips(j,:)))
     plot([x0 tips(j,1)],[y0 tips(j,2)],'-','Color',colors(j,:),'LineWidth',1.2);
     plot(tips(j,1),tips(j,2),'o','Color',colors(j,:));
    end
    if isfinite(FitAngle(rr(j))) && ~isempty(fitLines{j})
     ff=fitLines{j};
     plot(ff(:,1),ff(:,2),'-','Color',colors(j,:),'LineWidth',2.5);
     plot(ff(:,3),ff(:,4),'-','Color',colors(j,:),'LineWidth',2.5);
    end
    samples=edgeSamples{j};
    if ~isempty(samples)
     good=samples(:,5)==0;
     plot(samples(good,1),samples(good,2),'.','MarkerSize',7,'Color',colors(j,:));
     plot(samples(good,3),samples(good,4),'.','MarkerSize',7,'Color',colors(j,:));
     plot(samples(~good,1),samples(~good,2),'rx','MarkerSize',3);
     plot(samples(~good,3),samples(~good,4),'rx','MarkerSize',3);
    end
    text(10,25+22*j,sprintf('%d: %s',j,char(FitStatus(rr(j)))),'Color',colors(j,:),'BackgroundColor','k','Interpreter','none');
    if all(isfinite(ends(j,:)))
     e=ends(j,:); plot([e(1) e(3)],[e(2) e(4)],'-','Color',colors(j,:),'LineWidth',2);
     if isfinite(Angle(rr(j)))
      plot([e(1) x0 e(3)],[e(2) y0 e(4)],':','Color',colors(j,:));
     end
    end
   end
   plot(x0,y0,'r+','MarkerSize',12); axis image; xlim([1 w]); ylim([1 h]);
   title(sprintf('%s | %.2f ms | 蓝：左束  绿：中束  橙：右束',names{fi},(ids(fi)-zeroID)*1000/p.fps),'Interpreter','none');
   text(10,h-40,sprintf('版本 %s | 黄虚线=灰度主体 | 原图底图=%d',char(p.codeVersion),useRaw),'Color','w','BackgroundColor','k','Interpreter','none');
   text(10,h-15,'横线：半贯穿截面；彩色点：有效下游端点；红叉：剔除端点；圆：原始最远点','Color','w','BackgroundColor','k','Interpreter','none');
   [~,stem]=fileparts(names{fi}); print(fig,fullfile(out,'overlay',[stem '.png']),'-dpng','-r130');
  end
 catch ME
  CoreCone(rr)=NaN; CoreDown(rr)=NaN; CoreLength(rr)=NaN; CoreStatus(rr)="处理失败";
  CoreLeftHalf(rr)=NaN; CoreRightHalf(rr)=NaN;
  CoreSweepCone(rr,:)=NaN; CoreSweepDown(rr,:)=NaN; CoreSweepLength(rr,:)=NaN;
  CoreSweepLeftHalf(rr,:)=NaN; CoreSweepRightHalf(rr,:)=NaN;
  BaselineS(rr)=NaN;
  Status(rr)="failed"; Error(rr)=string(ME.message);
  DownstreamAngle(rr)=NaN; DownstreamCandidate(rr)=NaN; FitAngle(rr)=NaN; FitCandidate(rr)=NaN; FitStatus(rr)="处理失败"; AngleCandidate(rr)=NaN; S(rr)=NaN; Z(rr)=NaN; Area(rr)=NaN; Angle(rr)=NaN; Width(rr)=NaN; MaxWidth(rr)=NaN; Usable(rr)=false;
 end
 waitbar(i/N,bar,sprintf('%d / %d',i,N));
end
T=table(File,FrameID,Time_ms,Jet,S,Z,Area,Angle,Width,MaxWidth,Touch,SectorContact,Detached,Usable,Status,Error, ...
 'VariableNames',{'File','FrameID','Time_ms','Jet','Penetration_mm','AxialPenetration_mm', ...
 'Area_mm2','ConeAngle_deg','WidthAtHalfPenetration_mm','MaxWidth_mm','WindowTouch','SectorContact', ...
 'Detached','LengthAreaUsable','Status','Error'});
% 时间检查只比较同一喷束的相邻原始帧，不跨缺失帧、不强制单调。
Jump=false(K,1);
for j=1:3
 ix=j:3:K;
 for a=2:numel(ix)
  prev=ix(a-1); cur=ix(a);
  if FrameID(cur)==FrameID(prev)+1 && isfinite(S(prev)) && isfinite(S(cur))
   Jump(cur)=abs(S(cur)-S(prev))>max(p.jumpAbs_mm,p.jumpRel*S(prev));
  end
 end
end
% 角度参考长度发生突变时，候选值留诊断，正式角度不作为通过结果。
T.ConeAngle_deg(Jump)=NaN;
DownstreamAngle(Jump)=NaN;
FitStatus(Jump)=FitStatus(Jump)+"；相邻帧贯穿距突变，角度未采用";
T.CoreCone_deg=CoreCone; T.CoreDown_deg=CoreDown; T.CoreLength_mm=CoreLength; T.CoreStatus=CoreStatus;
T.CoreLeftHalfAngle_deg=CoreLeftHalf; T.CoreRightHalfAngle_deg=CoreRightHalf;
T.EnvelopeWidth_mm=EnvelopeWidth; T.MaxWidthBoundaryFlag=MaxWidthBlocked;
T.DownstreamSectionRange_deg=DownRange;
T.BaselinePenetration_mm=BaselineS;
T.RecoveryDelta_mm=S-BaselineS;
T.TipComponentPixels=TipComponent; T.TemporalJump=Jump;
T.DownstreamAngle_deg=DownstreamAngle; T.DownstreamCandidate_deg=DownstreamCandidate;
T.FittedAngle_deg=FitAngle; T.FittedAngleCandidate_deg=FitCandidate;
T.FitRMSE_px=FitRMSE; T.FitCoverage=FitCoverage; T.FitStatus=FitStatus;
T.AngleCandidate_deg=AngleCandidate;
T.TipTouch=TipTouch; T.TipSector=TipSector;
T.SectionTouch=SectionTouch; T.SectionSector=SectionSector;
save(fullfile(out,'measurements.mat'),'T','IgnoredPixels','CoreThresholds','CoreSweepCone', ...
 'CoreSweepDown','CoreSweepLength','CoreSweepLeftHalf','CoreSweepRightHalf');
exportChinese(T,out,p,calibration);
fid=fopen(fullfile(out,'README.txt'),'w','n','UTF-8');
if fid>=0
 fprintf(fid,['三束测量首版\n时间：第二原始帧为0ms，第一帧背景不统计。缺失帧保留行。\n' ...
 'Penetration：喷嘴到本扇区最远前景像素的距离；AxialPenetration：固定束轴投影。\n' ...
 'Area：有效视窗内本扇区投影面积。没有填孔和补全遮挡。\n' ...
 'WidthAtHalfPenetration：z=0.5*径向贯穿距处的完整横向宽度，不是半宽。截面带内各行边界取中位数。\n' ...
 'ConeAngle：上述边界点与喷嘴连线夹角；不是旧代码的像素角度百分位。\n' ...
 'MaxWidth：各1像素轴向截面中与束轴相交连续段宽度的最大值。固定分束方向/分界由用户确认。\n' ...
 'WindowTouch：远离喷嘴的可见域边界接触，长度/面积可能截断。\n' ...
 'SectorContact：较多像素接近分束边界，需复核归属，可能由真实宽喷束引起。\n' ...
 'Detached：近喷嘴无前景，角度不计算。不是断喷时刻的自动判定。\n' ...
 'Excel按参数分类，各参数状态独立。候选锥角不等于有效锥角；请阅读使用说明。\n' ...
 '无前景或像素过少输出NaN，不当成真实零值。未处理及失败帧有状态。\n' ...
 '标定来自170mm视窗平面，不代表已校正喷雾平面透视误差。\n' ...
 '固定扇区不能可靠区分合并喷雾；叠加图必须抽查，不能将质量标记视为精度证明。\n' ...
 '背景帧不测量；未做曲线平滑。当前代码未在MATLAB环境实际运行。\n']);
 fclose(fid);
end
fprintf('测量完成：%s\n',out);
msgbox(sprintf('已保存：%s\n先检查标定、分束及overlay，再使用数值。',out),'完成');
end

function M=readMask(path,sz)
I=imread(path);
if ndims(I)==3
 if ~isequal(I(:,:,1),I(:,:,2))||~isequal(I(:,:,1),I(:,:,3)), error('需要二值图而不是彩色叠加图。'); end
 I=I(:,:,1);
end
if ~isequal(size(I),sz), error('二值图尺寸不一致。'); end
if ~islogical(I)&&any(I(:)~=0 & I(:)~=1 & I(:)~=255), error('输入不是0/1或0/255二值图。'); end
M=I~=0;
end

function [center,r,rmse]=fitWindow(mask)
[yy,xx]=find(bwperim(mask));
if numel(xx)<20, error('有效视窗边界不足，无法标定。'); end
k=convhull(double(xx),double(yy)); x=double(xx(k(1:end-1))); y=double(yy(k(1:end-1)));
if numel(x)<6, error('外圆弧不足，无法自动拟合。'); end
use=true(size(x));
for it=1:5
 A=[2*x(use),2*y(use),ones(nnz(use),1)]; b=x(use).^2+y(use).^2;
 if rank(A)<3, error('视窗拟合退化。'); end
 c=A\b; center=c(1:2)'; r=sqrt(c(3)+sum(center.^2));
 if ~isfinite(r)||~isreal(r)||r<=0, error('无效视窗拟合。'); end
 residual=hypot(x-center(1),y-center(2))-r;
 tol=max(2,3*1.4826*median(abs(residual-median(residual))));
 newer=abs(residual)<=tol;
 if nnz(newer)<6||isequal(newer,use), break; end
 use=newer;
end
rmse=sqrt(mean(residual(use).^2));
end

function safeClose(h)
if ishghandle(h), close(h); end
end

function [xy,info]=estimateNozzle(root,names,sz,center,radius)
% 只在视窗顶部中央搜索早期前景；至少3帧一致才提供候选。
% 不向黑色遮挡内外推，故可能偏下，需用户确认。
xy=[NaN NaN]; points=[]; used={};
[XX,YY]=meshgrid(1:sz(2),1:sz(1));
search=abs(XX-center(1))<.25*radius & ...
 YY>max(1,center(2)-1.1*radius) & YY<center(2)-.55*radius;
for k=2:min(numel(names),101)
 path=fullfile(root,'6',names{k});
 if ~isfile(path), continue; end
 try
  M=readMask(path,sz); M=M & search;
  if nnz(M)<30, continue; end
  M=bwareafilt(M,1);
  if nnz(M)<30, continue; end
  [y,x]=find(M); ytop=min(y); near=y<=ytop+4;
  points(end+1,:)=[median(double(x(near))),double(ytop)]; %#ok<AGROW>
  used{end+1}=names{k}; %#ok<AGROW>
  if size(points,1)>=8, break; end
 catch
  continue;
 end
end
info=struct('method','early_visible_spray_tip_not_hidden_exit', ...
 'candidate_points',points,'frames',{used},'stable',false);
if size(points,1)<3, return; end
mid=median(points,1); good=hypot(points(:,1)-mid(1),points(:,2)-mid(2))<=6;
if nnz(good)<3, return; end
xy=median(points(good,:),1); info.stable=true;
end

function exportChinese(T,out,p,calibration)
% 使用writecell输出中文表头，兼容不支持中文table变量名的版本。
book=fullfile(out,'喷雾测量结果.xlsx'); n=height(T);
reason=strings(n,1); sr=strings(n,1); ar=strings(n,1); cr=strings(n,1); wr=strings(n,1);
for k=1:n
 base=char(T.Status(k));
 base=strrep(base,'not_processed','未处理'); base=strrep(base,'missing_mask','二值图缺失');
 base=strrep(base,'no_foreground','未识别到前景'); base=strrep(base,'too_small','前景像素不足');
 base=strrep(base,'no_half_section','半贯穿距截面不足'); base=strrep(base,'window_touch','喷束触及可见域边界');
 base=strrep(base,'sector_contact','喷束接近分界'); base=strrep(base,'detached','近喷嘴无前景');
 base=strrep(base,'tip_local_support_low','前端局部支撑不足');
 base=strrep(base,'failed','处理失败'); base=strrep(base,'ok','已计算'); reason(k)=string(base);
 if isnan(T.Penetration_mm(k))
  sr(k)=reason(k); ar(k)=reason(k); cr(k)=reason(k); wr(k)=reason(k); continue;
 end
 sr(k)="已计算，待人工复核"; ar(k)=sr(k); wr(k)=sr(k);
 if T.TemporalJump(k), sr(k)=sr(k)+"；相邻帧突变需查原图"; end
 if T.TipComponentPixels(k)<p.tipSmallComponent_px, sr(k)=sr(k)+"；前端局部支撑不足"; end
 if T.TipTouch(k), sr(k)=sr(k)+"；前端触边，可能截断"; end
 if T.TipSector(k), sr(k)=sr(k)+"；前端接近分界，归属待核查"; end
 if T.WindowTouch(k), ar(k)=ar(k)+"；仅为可见面积，可能截断"; end
 if T.SectorContact(k), ar(k)=ar(k)+"；分束面积归属待核查"; end
 cr(k)="已计算，待人工复核";
 if isnan(T.AngleCandidate_deg(k))
  cr(k)="无法计算：截面不足";
 else
  if T.SectionSector(k), cr(k)=cr(k)+"；截面端点接近人工分界"; end
  if T.SectionTouch(k), cr(k)=cr(k)+"；测角截面触边"; end
  if T.TipComponentPixels(k)<p.tipSmallComponent_px, cr(k)=cr(k)+"；前端局部支撑不足"; end
  if T.Detached(k), cr(k)=cr(k)+"；近喷嘴无前景"; end
  if T.TipTouch(k)||T.TipSector(k), cr(k)=cr(k)+"；贯穿距参考需复核"; end
  if isnan(T.ConeAngle_deg(k)), cr(k)="未通过自动检查："+cr(k); end
 end
 if isnan(T.WidthAtHalfPenetration_mm(k)), wr(k)="无法计算：截面不足";
 elseif T.SectionSector(k)||T.SectionTouch(k)||T.TipTouch(k)||T.TipSector(k)
  wr(k)=wr(k)+"；截面或参考位置需复核";
 end
end
jet=T.Jet; jet(jet=="Left")="左束"; jet(jet=="Middle")="中束"; jet(jet=="Right")="右束";
head={'原始文件名','原始帧号','时间_ms','喷束','径向贯穿距_mm','轴向贯穿距_mm','可见投影面积_mm2', ...
 '通过自动检查的锥角_deg','半贯穿距截面宽度_mm','最大截面宽度_mm','候选锥角_deg', ...
 '贯穿距说明','面积说明','锥角说明','宽度说明','处理状态','错误详情'};
rows=[cellstr(T.File),num2cell(T.FrameID),num2cell(T.Time_ms),cellstr(jet), ...
 num2cell([T.Penetration_mm,T.AxialPenetration_mm,T.Area_mm2,T.ConeAngle_deg, ...
 T.WidthAtHalfPenetration_mm,T.MaxWidth_mm,T.AngleCandidate_deg]), ...
 cellstr(sr),cellstr(ar),cellstr(cr),cellstr(wr),cellstr(reason),cellstr(T.Error)];
% 明确将NaN输出为空；对应原因列必须保留，不以0或插值伪装有效数据。
for k=1:numel(rows)
 if isnumeric(rows{k})&&isscalar(rows{k})&&isnan(rows{k}), rows{k}=[]; end
end
writeUtf8Csv([head;rows],fullfile(out,'质量检查日志.csv'));
extraHead={'原始文件名','时间_ms','喷束','前端局部支撑像素数','时间突变标记','旧斜率诊断角_deg','拟合残差_px','有效截面覆盖率','下游截面检查状态','下游可见展开角候选_deg'};
extraRows=[cellstr(T.File),num2cell(T.Time_ms),cellstr(jet),num2cell([T.TipComponentPixels,double(T.TemporalJump), ...
 T.FittedAngleCandidate_deg,T.FitRMSE_px,T.FitCoverage]),cellstr(T.FitStatus),num2cell(T.DownstreamCandidate_deg)];
writeUtf8Csv([extraHead;extraRows],fullfile(out,'边界与前端诊断.csv'));
% 独立数值质量表，0表示未通过自动筛选，不表示真实物理量为零。
lengthOK=isfinite(T.Penetration_mm)&~T.TipTouch&~T.TipSector& ...
 T.TipComponentPixels>=p.tipSmallComponent_px&~T.TemporalJump;
halfOK=isfinite(T.ConeAngle_deg)&lengthOK;
downOK=isfinite(T.DownstreamAngle_deg)&lengthOK;
qualityHead={'原始文件名','时间_ms','喷束','贯穿距自动筛选通过','半贯穿距锥角自动筛选通过', ...
 '下游展开角自动筛选通过','可见面积未触遮挡','分区归属无警告','恢复前贯穿距_mm','弱边缘恢复引起变化_mm','下游有效截面角度极差_deg','最大宽度端点无边界干扰','旧包络最大宽度_mm'};
qualityRows=[cellstr(T.File),num2cell(T.Time_ms),cellstr(jet), ...
 num2cell([double(lengthOK),double(halfOK),double(downOK), ...
 double(isfinite(T.Area_mm2)&~T.WindowTouch),double(isfinite(T.Area_mm2)&~T.SectorContact), ...
 T.BaselinePenetration_mm,T.RecoveryDelta_mm,T.DownstreamSectionRange_deg, ...
 double(isfinite(T.MaxWidth_mm)&~T.MaxWidthBoundaryFlag),T.EnvelopeWidth_mm])];
writeUtf8Csv([qualityHead;qualityRows],fullfile(out,'数值质量标记.csv'));

mainCols=[1:10];
dataHead=[head(mainCols),{'下游可见展开角_deg','灰度主体半贯穿距锥角_deg','灰度主体左侧半角_deg', ...
 '灰度主体右侧半角_deg','灰度主体下游展开角_deg'}];
dataRows=[rows(:,mainCols),num2cell([T.DownstreamAngle_deg,T.CoreCone_deg,T.CoreLeftHalfAngle_deg, ...
 T.CoreRightHalfAngle_deg,T.CoreDown_deg])];
writeUtf8Csv([{'原始文件名','时间_ms','喷束','主体径向贯穿距_mm','主体半贯穿距锥角_deg', ...
 '主体左侧半角_deg','主体右侧半角_deg','主体下游展开角_deg','主体相对衰减阈值','状态'}; ...
 cellstr(T.File),num2cell(T.Time_ms),cellstr(jet),num2cell([T.CoreLength_mm,T.CoreCone_deg, ...
 T.CoreLeftHalfAngle_deg,T.CoreRightHalfAngle_deg,T.CoreDown_deg,repmat(p.coreContrast,height(T),1)]),cellstr(T.CoreStatus)], ...
 fullfile(out,'灰度主体诊断.csv'));
info={'项目','说明';'分析窗口',sprintf('0~%g ms，第二原始帧为0ms，帧间隔0.04ms',p.analysisEnd_ms); ...
 '长度标定',sprintf('通光直径%g mm；采用像素直径%.4f px；%.8f mm/px',calibration.diameter_mm,calibration.diameter_px,calibration.mm_per_pixel); ...
 '空白含义','未识别、像素不足、无法计算或未通过检查，具体见独立质量检查日志；不代表0'; ...
 '径向贯穿距','喷嘴到该扇区最远前景点距离';'轴向贯穿距','沿固定喷束参考轴的最大投影距离'; ...
 '可见投影面积','只统计二值前景；遮挡部分不补全；分束区域相连时面积归属需复核'; ...
 '锥角','z=0.5倍径向贯穿距处边界点与喷嘴连线夹角'; ...
 '候选锥角','实际计算值，可能受分区或遮挡影响，不得直接当作有效锥角'; ...
 '通过自动检查','仅表示通过当前代码规则，不表示已完成测量精度验证'; ...
 '截面宽度','半贯穿距位置的完整横向宽度，不是半宽'; ...
 '参数分类表','左右中三束同一时间并列；详细异常见独立质量检查日志'; ...
 '原始数据','MAT文件保留英文变量便于程序处理；Excel和CSV采用中文'; ...
 '新旧结果','修改前的缺失锥角不能凭空恢复，需用本版本重新测量'};
try
 info=[info;{'边界拟合展开角',sprintf('固定轴向区间%.2f~%.2f倍轴向贯穿距，两侧自由截距直线斜率夹角；不是原半贯穿距锥角',p.fitRange)}; ...
 {'拟合检查','剔除接近人工分界和遮挡的截面端点，检查连续横截面、覆盖率和拟合残差。弯曲或无法分辨的边界不强行输出'}; ...
 {'前端时间检查','保留原始最大径向距离；小连通域与相邻帧跳变另存诊断，不删帧不插值'}; ...
 {'中文编码','CSV采用UTF-8 BOM；优先打开XLSX。MATLAB源文件也保存为UTF-8 BOM'}];
 info=[info;{'下游可见展开角','固定0.60~0.85倍轴向贯穿距区间，剔除人工边界和遮挡后，逐截面计算两端与喷嘴连线夹角，取中位数；不同于原半贯穿距锥角，也不同于直线斜率角'};{'起始空白','二值图无前景时不可测，不填零；时间仍按用户指定第二帧为0ms'}];
 writeUtf8Csv(info,fullfile(out,'参数定义.csv'));
 labs=["Left","Middle","Right"]; zh={'左束','中束','右束'};
 % 每束独立工作表和CSV，不再输出堆叠总表或三束并列表。
 cols=[1:3,5:numel(dataHead)];
 for j=1:3
  sel=T.Jet==labs(j);
  separate=cleanMissing([dataHead(cols);dataRows(sel,cols)]);
  writecell(separate,book,'Sheet',zh{j});
  writeUtf8Csv(separate,fullfile(out,[zh{j} '_测量数据.csv']));
 end
catch ME
 warning('Excel写入失败，测量数据CSV及MAT已保存：%s',ME.message);
end
end

function [angle,rmse,coverage,status,lines,nozzleAngle,samples]=fitVisibleEdges(z,u,x0,y0,ax,normvec,edges,edgeMask,sz,p)
% 端点类型：0真实可见，1截面断开，2人工分界，3遮挡边界。
nozzleAngle=NaN; angle=NaN; rmse=NaN; coverage=0; lines=[]; samples=[];
status="有效边界不足";
rows=(ceil(p.fitRange(1)*max(z)):floor(p.fitRange(2)*max(z)))';
pts=[]; rejected=zeros(1,4);
for k=1:numel(rows)
 vals=sort(u(round(z)==rows(k)));
 vals=axisSegment(vals);
 if numel(vals)<3, rejected(4)=rejected(4)+1; continue; end
 xy=[x0 y0]+rows(k)*ax+[vals(1);vals(end)]*normvec;
 code=0;
 if any(diff(vals)>3), code=1; end
 theta=atan2d(xy(:,1)-x0,xy(:,2)-y0);
 if any(min(abs(theta-edges(2:3)),[],2)<=p.sectorGuard_deg), code=2; end
 for e=1:2
  x=round(xy(e,1)); y=round(xy(e,2));
  if x<1||x>sz(2)||y<1||y>sz(1), code=3; continue; end
  block=edgeMask(max(1,y-2):min(sz(1),y+2),max(1,x-2):min(sz(2),x+2));
  if any(block(:)), code=3; end
 end
 samples(end+1,:)=[xy(1,:),xy(2,:),code]; %#ok<AGROW>
 if code>0, rejected(code)=rejected(code)+1; continue; end
 pts(end+1,:)=[rows(k),vals(1),vals(end)]; %#ok<AGROW>
end
coverage=size(pts,1)/max(1,numel(rows));
detail=sprintf('有效%d/%d；断开%d；分界%d；遮挡%d；无轴交连续段或像素不足%d',size(pts,1),numel(rows),rejected);
if size(pts,1)<p.fitMinRows||coverage<p.fitMinCoverage
 status="截面不足："+string(detail); return;
end
if max(pts(:,1))-min(pts(:,1))<.7*(rows(end)-rows(1))
 status="轴向覆盖不足："+string(detail); return;
end
nozzleAngle=median(atan2d(pts(:,3),pts(:,1))-atan2d(pts(:,2),pts(:,1)));
status="下游截面通过："+string(detail);
% 旧斜率量只保留供诊断，绝不作为下游展开角判据。
X=[pts(:,1),ones(size(pts,1),1)]; aa=X\pts(:,2); bb=X\pts(:,3);
rmse=sqrt(mean([X*aa-pts(:,2);X*bb-pts(:,3)].^2));
angle=atan2d(bb(1),1)-atan2d(aa(1),1);
end

function cells=cleanMissing(cells)
for k=1:numel(cells)
 if isnumeric(cells{k})&&isscalar(cells{k})&&~isfinite(cells{k}), cells{k}=[]; end
end
end

function writeUtf8Csv(cells,path)
% 自行写标准CSV：UTF-8 BOM、CRLF、双引号转义；Excel双击可识别中文。
fid=fopen(path,'wb');
if fid<0, error('无法写入文件：%s',path); end
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fwrite(fid,uint8([239 187 191]),'uint8');
for r=1:size(cells,1)
 fields=cell(1,size(cells,2));
 for c=1:size(cells,2)
  v=cells{r,c};
  if isempty(v)
   fields{c}='';
  elseif isnumeric(v)||islogical(v)
   if isscalar(v)&&isfinite(v), fields{c}=sprintf('%.15g',double(v)); else, fields{c}=''; end
  else
   if isstring(v)&&ismissing(v), txt=''; else, txt=char(v); end
   fields{c}=['"' strrep(txt,'"','""') '"'];
  end
 end
 line=[strjoin(fields,',') char(13) char(10)];
 fwrite(fid,unicode2native(line,'UTF-8'),'uint8');
end
end
function selected=axisSegment(vals)
% 按大于3像素空隙分段，仅接受与固定束轴相交的连续段。
% 不跨越空隙，不用离轴分支替代主体；允许1像素采样误差。
selected=[];
if isempty(vals), return; end
cuts=[0;find(diff(vals)>3);numel(vals)];
for k=1:numel(cuts)-1
 part=vals(cuts(k)+1:cuts(k+1));
 if part(1)<=1 && part(end)>=-1
  if numel(part)>numel(selected), selected=part; end
 end
end
end

function bad=endpointBlocked(xy,edgeMask)
bad=false; [h,w]=size(edgeMask);
for k=1:size(xy,1)
 x=round(xy(k,1)); y=round(xy(k,2));
 if x<1||x>w||y<1||y>h, bad=true; return; end
 block=edgeMask(max(1,y-2):min(h,y+2),max(1,x-2):min(w,x+2));
 if any(block(:)), bad=true; return; end
end
end

function [cone,down,lengthMM,status,samples,leftHalf,rightHalf]=measureGrayCore(mask,x0,y0,angle,edges,j,physicalEdge,p,scale)
% 独立的光学灰度主体量；不使用原包络长度，不跨越人工分区边界补全。
cone=NaN; down=NaN; lengthMM=NaN; samples=[]; status="主体像素不足";
leftHalf=NaN; rightHalf=NaN;
[y,x]=find(mask); dx=x-x0; dy=y-y0; theta=atan2d(dx,dy);
keep=dy>0 & theta>=edges(j) & theta<edges(j+1);
x=x(keep); y=y(keep); dx=dx(keep); dy=dy(keep);
if numel(x)<p.minPixels, return; end
r=hypot(dx,dy); [rmax,k]=max(r); lengthMM=rmax*scale;
ax=[sind(angle),cosd(angle)]; normal=[cosd(angle),-sind(angle)];
z=dx*ax(1)+dy*ax(2); u=dx*normal(1)+dy*normal(2);
referenceOK=~endpointBlocked([x(k) y(k)],physicalEdge);
referenceOK=referenceOK && min(abs(atan2d(dx(k),dy(k))-edges(2:3)))>p.sectorGuard_deg && ...
 nnz(hypot(x-x(k),y-y(k))<=p.tipSupportRadius_px)>=p.tipSmallComponent_px;
[~,~,~,ds,~,candidate,samples]=fitVisibleEdges(z,u,x0,y0,ax,normal,edges,physicalEdge,size(mask),p);
status=ds;
if referenceOK, down=candidate; else, status=status+"；主体前端参考无效"; end
station=.5*rmax; values=[]; leftValues=[]; rightValues=[];
for zz=ceil(station-p.halfBand_px):floor(station+p.halfBand_px)
 part=axisSegment(sort(u(round(z)==zz)));
 if numel(part)<3, continue; end
 xy=[x0 y0]+zz*ax+[part(1);part(end)]*normal;
 th=atan2d(xy(:,1)-x0,xy(:,2)-y0);
 blocked=[endpointBlocked(xy(1,:),physicalEdge),endpointBlocked(xy(2,:),physicalEdge)];
 sector=min(abs(th-edges(2:3)),[],2)<=p.sectorGuard_deg;
 if ~blocked(1)&&~sector(1), leftValues(end+1)=abs(atan2d(part(1),zz)); end %#ok<AGROW>
 if ~blocked(2)&&~sector(2), rightValues(end+1)=abs(atan2d(part(end),zz)); end %#ok<AGROW>
 if any(blocked)||any(sector), continue; end
 values(end+1)=atan2d(part(end),zz)-atan2d(part(1),zz); %#ok<AGROW>
end
if numel(leftValues)>=p.minSections, leftHalf=median(leftValues); end
if numel(rightValues)>=p.minSections, rightHalf=median(rightValues); end
if referenceOK && numel(values)>=p.minSections
 cone=median(values); status=status+"；主体半贯穿截面通过";
else
 status=status+"；主体半贯穿截面不足或参考无效";
end
if isfinite(leftHalf)&&isfinite(rightHalf)
 status=status+"；双侧半角可见";
elseif isfinite(leftHalf)||isfinite(rightHalf)
 status=status+"；仅单侧半角可见";
else
 status=status+"；两侧半角均无效";
end
end
