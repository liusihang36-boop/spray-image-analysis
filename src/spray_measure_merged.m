function out=spray_measure_merged(root,settingsFile,rawOverride)
%SPRAY_MEASURE_MERGED 整体塌缩/合并喷雾二维几何测量（MATLAB R2023a）。
% 不进行左/中/右人为分束。外层二值轮廓用于贯穿距和面积；灰度主体用于
% 动态中心轴及主体角。角度由一段边界稳健拟合得到，不由单行截面决定。

p.codeVersion="20260921_dual_mode_1";
p.fps=25000; p.analysisEnd_ms=5; p.windowDiameter_mm=170;
p.coreContrast=0.45; p.coreCandidates=[0.30 0.35 0.40 0.45];
p.minPixels=100; p.nozzleRadius_px=30; p.tipRadius_px=6;
p.minTipSupport=20; p.fitRange=[0.15 0.60]; p.downRange=[0.55 0.85];
p.minFitRows=15; p.maxFitRMSE_px=8; p.edgeMargin_px=2;
p.axisMinRadius_px=20; p.axisMaxDeflection_deg=45; p.overlayEvery=1;
out='';
if nargin<1||isempty(root)
 root=uigetdir(pwd,'选择预处理结果目录（包含6和settings.mat）');
 if isequal(root,0), return; end
end
sf=fullfile(root,'settings.mat'); lf=fullfile(root,'processing_log.csv');
if ~isfile(sf)||~isfile(lf)||~isfolder(fullfile(root,'6'))
 error('整体模式需要settings.mat、processing_log.csv和6子目录。');
end
s=load(sf,'B','valid','p'); B=single(s.B); valid=logical(s.valid); [h,w]=size(B);
L=readtable(lf,'TextType','string'); [ids,ord]=sort(double(L.FrameID)); L=L(ord,:);
names=cellstr(L.File);
if numel(ids)<2||numel(unique(ids))~=numel(ids), error('原始帧号不足或重复。'); end
zeroID=ids(2); if isfield(s,'p')&&isfield(s.p,'zeroFrameID'), zeroID=s.p.zeroFrameID; end
keep=ids==ids(1)|((ids-zeroID)*1000/p.fps>=0&(ids-zeroID)*1000/p.fps<=p.analysisEnd_ms+1e-9);
ids=ids(keep); names=names(keep);

saved=nargin>=2&&~isempty(settingsFile)&&isfile(settingsFile);
if saved
 c=load(settingsFile);
 required={'calibration','x0','y0','axisAngle'};
 if ~all(isfield(c,required)), error('整体喷雾配置缺少calibration/x0/y0/axisAngle。'); end
 calibration=c.calibration; x0=double(c.x0); y0=double(c.y0); axisAngle=double(c.axisAngle);
else
 [center,r,rmse]=fitWindowMerged(bwareafilt(B>30,1));
 f=figure('Name','整体喷雾标定','Color','w'); imshow(B,[0 255]); hold on;
 t=linspace(0,2*pi,400); plot(center(1)+r*cos(t),center(2)+r*sin(t),'g-','LineWidth',1.5);
 a=inputdlg({'视窗直径_mm','采用的视窗像素直径','喷嘴X_列','喷嘴Y_行'}, ...
  '整体喷雾初始参数',1,{num2str(p.windowDiameter_mm),sprintf('%.3f',2*r),sprintf('%.1f',center(1)),'20'});
 if isempty(a), safeClose(f); return; end
 vals=str2double(a); if any(~isfinite(vals))||any(vals<=0), safeClose(f); error('初始参数必须为正数。'); end
 calibration=struct('diameter_mm',vals(1),'diameter_px',vals(2), ...
  'mm_per_pixel',vals(1)/vals(2),'center_xy',center,'fit_rmse_px',rmse,'user_confirmed',true);
 x0=vals(3); y0=vals(4);
 [rf,rp]=uigetfile(fullfile(root,'6','*.bmp'),'选择整体喷雾轮廓清楚的参考帧');
 if isequal(rf,0), safeClose(f); return; end
 R=readMaskMerged(fullfile(rp,rf),[h w]);
 g=figure('Name','整体喷雾参考轴','Color','w'); imshow(R); hold on; plot(x0,y0,'r+');
 title('点击整体喷雾初始中心方向上的一点（后续逐帧允许动态偏转）');
 [xc,yc,b]=ginput(1); if isempty(xc)||b~=1||yc<=y0, safeClose(f); safeClose(g); return; end
 axisAngle=atan2d(xc-x0,yc-y0);
 plot([x0 xc],[y0 yc],'c-','LineWidth',2); drawnow;
 q=questdlg(sprintf('整体参考轴 %.2f°，是否采用？',axisAngle),'确认','采用','取消','采用');
 if ~strcmp(q,'采用'), safeClose(f); safeClose(g); return; end
 safeClose(f); safeClose(g);
end
if ~isfinite(calibration.mm_per_pixel)||calibration.mm_per_pixel<=0|| ...
 any(~isfinite([x0 y0 axisAngle]))||x0<1||x0>w||y0<1||y0>h
 error('整体喷雾配置无效。');
end
scale=double(calibration.mm_per_pixel);
if nargin>=3&&~isempty(rawOverride), raw=char(rawOverride); else, raw=fileparts(root); end
if ~isfolder(raw), error('原始BMP目录不存在：%s',raw); end
missing=names(~cellfun(@(n)isfile(fullfile(raw,n)),names));
if ~isempty(missing), error('原图目录缺少%s。',missing{1}); end

out=fullfile(root,['measure_merged_' datestr(now,'yyyymmdd_HHMMSS')]);
while isfolder(out), out=[out '_new']; end %#ok<AGROW>
mkdir(out); mkdir(fullfile(out,'overlay'));
save(fullfile(out,'measurement_settings.mat'),'p','calibration','x0','y0','axisAngle','zeroID','raw');
copyfile([mfilename('fullpath') '.m'],fullfile(out,'executed_spray_measure_merged.m'));

N=numel(ids)-1; File=string(names(2:end)); FrameID=ids(2:end); Time_ms=(FrameID-zeroID)*1000/p.fps;
nanv=nan(N,1); Penetration_mm=nanv; AxialPenetration_mm=nanv; Area_mm2=nanv;
ConeAngle_deg=nanv; LeftHalfAngle_deg=nanv; RightHalfAngle_deg=nanv; DownstreamAngle_deg=nanv;
MaxWidth_mm=nanv; WidthHalf_mm=nanv; NearWidth_mm=nanv; ShapeFactor=nanv;
CentroidOffset_mm=nanv; DeflectionAngle_deg=nanv; DynamicAxis_deg=nanv;
CorePenetration_mm=nanv; CoreConeAngle_deg=nanv; CoreDownstreamAngle_deg=nanv;
TipSupportPixels=nanv; BoundaryRMSE_px=nanv; DownstreamRMSE_px=nanv;
WindowTouch=false(N,1); Detached=false(N,1); Reliable=false(N,1);
Status=repmat("未处理",N,1); Error=repmat("",N,1);
physicalEdge=valid&~imerode(valid,strel('disk',p.edgeMargin_px,0));
fig=figure('Visible','off','Color','w','Position',[100 100 950 900]); cleanFig=onCleanup(@()safeClose(fig)); %#ok<NASGU>
for i=1:N
 try
  M=readMaskMerged(fullfile(root,'6',names{i+1}),[h w])&valid;
  I=imread(fullfile(raw,names{i+1})); if ndims(I)==3, I=rgb2gray(I); end
  if ~isa(I,'uint8'), error('整体灰度主体当前要求8位原图。'); end
  M=keepNozzleComponents(M,x0,y0,p.nozzleRadius_px);
  if nnz(M)<p.minPixels, Status(i)="前景不足"; continue; end
  core=grayCoreMerged(B,single(I),valid,p.coreContrast);
  core=keepNozzleComponents(core,x0,y0,p.nozzleRadius_px);
  DynamicAxis_deg(i)=estimateAxisMerged(core,M,x0,y0,axisAngle,p);
  ax=[sind(DynamicAxis_deg(i)) cosd(DynamicAxis_deg(i))]; nv=[cosd(DynamicAxis_deg(i)) -sind(DynamicAxis_deg(i))];
  met=measureOneMerged(M,x0,y0,ax,nv,physicalEdge,p,scale);
  Penetration_mm(i)=met.radial*scale; AxialPenetration_mm(i)=met.axial*scale; Area_mm2(i)=nnz(M)*scale^2;
  ConeAngle_deg(i)=met.cone; LeftHalfAngle_deg(i)=met.left; RightHalfAngle_deg(i)=met.right;
  DownstreamAngle_deg(i)=met.down; MaxWidth_mm(i)=met.maxWidth*scale;
  WidthHalf_mm(i)=met.halfWidth*scale; NearWidth_mm(i)=met.nearWidth*scale;
  ShapeFactor(i)=Area_mm2(i)/max(Penetration_mm(i)^2,eps);
  CentroidOffset_mm(i)=met.centroidOffset*scale; DeflectionAngle_deg(i)=DynamicAxis_deg(i)-axisAngle;
  TipSupportPixels(i)=met.tipSupport; BoundaryRMSE_px(i)=met.rmse; DownstreamRMSE_px(i)=met.downRMSE;
  WindowTouch(i)=met.touch; Detached(i)=met.detached;
  if any(core(:))
   cm=measureOneMerged(core,x0,y0,ax,nv,physicalEdge,p,scale);
   CorePenetration_mm(i)=cm.radial*scale; CoreConeAngle_deg(i)=cm.cone; CoreDownstreamAngle_deg(i)=cm.down;
  end
  Reliable(i)=~met.detached&&met.tipSupport>=p.minTipSupport&&isfinite(met.down);
  Status(i)="已计算";
  if met.touch, Status(i)=Status(i)+"；触及视窗，可见值可能截断"; end
  if met.tipSupport<p.minTipSupport, Status(i)=Status(i)+"；前端支撑不足"; end
  if mod(i-1,p.overlayEvery)==0||i==N
   figure(fig); clf(fig); imshow(I); hold on;
   contour(M,[.5 .5],'r-','LineWidth',1); if any(core(:)), contour(core,[.5 .5],'y:'); end
   plot([x0 x0+h*ax(1)],[y0 y0+h*ax(2)],'c--','LineWidth',1.2); plot(x0,y0,'g+','MarkerSize',12);
   if ~isempty(met.lines)
    plot(met.lines(:,1),met.lines(:,2),'b-','LineWidth',2); plot(met.lines(:,3),met.lines(:,4),'b-','LineWidth',2);
   end
   title(sprintf('%s | %.2f ms | 整体喷雾',names{i+1},Time_ms(i)),'Interpreter','none');
   text(10,h-15,sprintf('S=%.2f mm  angle=%.2f°  deflection=%.2f°',Penetration_mm(i),ConeAngle_deg(i),DeflectionAngle_deg(i)), ...
    'Color','w','BackgroundColor','k');
   [~,stem]=fileparts(names{i+1}); print(fig,fullfile(out,'overlay',[stem '.png']),'-dpng','-r130');
  end
 catch ME
  Status(i)="处理失败"; Error(i)=string(ME.message);
 end
end
T=table(File,FrameID,Time_ms,Penetration_mm,AxialPenetration_mm,Area_mm2,ConeAngle_deg, ...
 LeftHalfAngle_deg,RightHalfAngle_deg,DownstreamAngle_deg,MaxWidth_mm,WidthHalf_mm,NearWidth_mm, ...
 ShapeFactor,CentroidOffset_mm,DeflectionAngle_deg,DynamicAxis_deg,CorePenetration_mm, ...
 CoreConeAngle_deg,CoreDownstreamAngle_deg,TipSupportPixels,BoundaryRMSE_px,DownstreamRMSE_px, ...
 WindowTouch,Detached,Reliable,Status,Error);
save(fullfile(out,'measurements.mat'),'T'); writetable(T,fullfile(out,'整体喷雾测量结果.xlsx'),'Sheet','整体喷雾');
fprintf('整体喷雾测量完成：%s\n',out);
end

function M=readMaskMerged(path,sz)
if ~isfile(path), error('缺少二值图：%s',path); end
I=imread(path); if ndims(I)==3, I=I(:,:,1); end
if ~isequal(size(I),sz), error('二值图尺寸不一致。'); end
M=I~=0;
end

function M=keepNozzleComponents(M,x0,y0,r)
[h,w]=size(M); [X,Y]=meshgrid(1:w,1:h); seed=M&hypot(X-x0,Y-y0)<=r;
if any(seed(:)), M=imreconstruct(seed,M,8); elseif any(M(:)), M=bwareafilt(M,1); end
end

function C=grayCoreMerged(B,I,valid,threshold)
weights=imgaussfilt(single(valid),.8,'FilterSize',7,'Padding','replicate');
D=imgaussfilt((B-I).*single(valid),.8,'FilterSize',7,'Padding','replicate')./max(weights,1e-6);
C=bwareaopen(valid&(max(D,0)./max(B,1)>=threshold),8,8);
end

function a=estimateAxisMerged(core,outer,x0,y0,a0,p)
M=core; if nnz(M)<p.minPixels, M=outer; end
[y,x]=find(M); dx=double(x)-x0; dy=double(y)-y0; r=hypot(dx,dy);
q=dy>0&r>=p.axisMinRadius_px; if nnz(q)<20, a=a0; return; end
% 远处面积质心提供逐帧偏转；限制相对人工参考轴的最大偏转。
rq=sort(r(q)); cap=rq(max(1,ceil(.90*numel(rq))));
wgt=min(r(q),cap); cx=sum(dx(q).*wgt)/sum(wgt); cy=sum(dy(q).*wgt)/sum(wgt);
a=atan2d(cx,cy); delta=mod(a-a0+180,360)-180;
a=a0+max(-p.axisMaxDeflection_deg,min(p.axisMaxDeflection_deg,delta));
end

function m=measureOneMerged(M,x0,y0,ax,nv,edge,p,scale) %#ok<INUSD>
[h,w]=size(M); [y,x]=find(M); dx=double(x)-x0; dy=double(y)-y0;
z=dx*ax(1)+dy*ax(2); u=dx*nv(1)+dy*nv(2); r=hypot(dx,dy); q=z>0;
x=x(q); y=y(q); z=z(q); u=u(q); r=r(q);
m=struct('radial',NaN,'axial',NaN,'cone',NaN,'left',NaN,'right',NaN,'down',NaN, ...
 'maxWidth',NaN,'halfWidth',NaN,'nearWidth',NaN,'centroidOffset',NaN,'tipSupport',0, ...
 'rmse',NaN,'downRMSE',NaN,'touch',false,'detached',true,'lines',[]);
if isempty(z), return; end
[m.radial,it]=max(r); m.axial=max(z); m.centroidOffset=mean(u); m.detached=~any(r<=p.nozzleRadius_px);
m.tipSupport=nnz(hypot(double(x)-double(x(it)),double(y)-double(y(it)))<=p.tipRadius_px);
ind=sub2ind([h w],y,x); m.touch=any(edge(ind)&r>p.nozzleRadius_px);
[zs,lo,hi]=rowEnvelope(z,u); widths=hi-lo; m.maxWidth=max(widths);
m.halfWidth=localWidth(zs,widths,.5*m.axial); m.nearWidth=localWidth(zs,widths,.2*m.axial);
[m.cone,m.left,m.right,m.rmse,m.lines]=fitEnvelope(zs,lo,hi,p.fitRange*m.axial,x0,y0,ax,nv,p);
[m.down,~,~,m.downRMSE]=fitEnvelope(zs,lo,hi,p.downRange*m.axial,x0,y0,ax,nv,p);
end

function [zs,lo,hi]=rowEnvelope(z,u)
zr=round(z); [zs,~,g]=unique(zr); lo=accumarray(g,u,[],@min); hi=accumarray(g,u,[],@max);
end

function v=localWidth(z,w,target)
q=abs(z-target)<=5; if nnz(q)<2, v=NaN; else, v=median(w(q)); end
end

function [cone,left,right,rmse,lines]=fitEnvelope(z,lo,hi,range,x0,y0,ax,nv,p)
cone=NaN; left=NaN; right=NaN; rmse=NaN; lines=[];
q=z>=range(1)&z<=range(2)&isfinite(lo)&isfinite(hi);
if nnz(q)<p.minFitRows, return; end
zz=double(z(q)); ll=double(lo(q)); hh=double(hi(q));
[bl,rl]=robustLine(zz,ll); [br,rr]=robustLine(zz,hh); rmse=max(rl,rr);
if ~isfinite(rmse)||rmse>p.maxFitRMSE_px, return; end
left=max(0,-atan2d(bl(1),1)); right=max(0,atan2d(br(1),1)); cone=left+right;
ze=[min(zz);max(zz)]; ul=polyval(bl,ze); ur=polyval(br,ze);
pl=[x0 y0]+ze*ax+ul*nv; pr=[x0 y0]+ze*ax+ur*nv; lines=[pl pr];
end

function [b,rmse]=robustLine(x,y)
use=true(size(x)); b=[NaN NaN];
for k=1:5
 if nnz(use)<5, break; end
 b=polyfit(x(use),y(use),1); e=y-polyval(b,x); med=median(e(use)); madv=1.4826*median(abs(e(use)-med));
 if madv<1e-6, break; end
 newer=abs(e-med)<=3*madv; if isequal(newer,use), break; end; use=newer;
end
if nnz(use)<5, rmse=NaN; else, rmse=sqrt(mean((y(use)-polyval(b,x(use))).^2)); end
end

function [center,r,rmse]=fitWindowMerged(mask)
[y,x]=find(bwperim(mask)); k=convhull(double(x),double(y)); x=double(x(k(1:end-1))); y=double(y(k(1:end-1)));
A=[2*x 2*y ones(size(x))]; c=A\(x.^2+y.^2); center=c(1:2)'; r=sqrt(c(3)+sum(center.^2));
rmse=sqrt(mean((hypot(x-center(1),y-center(2))-r).^2));
end

function safeClose(h)
if ishghandle(h), close(h); end
end
