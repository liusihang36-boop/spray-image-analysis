function c=spray_confirm_geometry(B,reference,c,mode)
% 原图预览并确认几何配置；旧配置也必须经过本次预览。
[h,w]=size(B); f=figure('Name','喷嘴和视窗确认','Color','w');
cleanup=onCleanup(@()closeFigure(f)); %#ok<NASGU>
while true
 figure(f); clf(f);
 for j=1:2
  subplot(1,2,j); imshow(reference,[]); hold on;
  plot(c.x0,c.y0,'g+','MarkerSize',18,'LineWidth',2);
  if isfield(c,'calibration')
   tt=linspace(0,2*pi,300); cc=c.calibration.center_xy; rr=c.calibration.diameter_px/2;
   plot(cc(1)+rr*cos(tt),cc(2)+rr*sin(tt),'c-');
  end
  if j==2, xlim([max(1,c.x0-75) min(w,c.x0+75)]); ylim([max(1,c.y0-75) min(h,c.y0+75)]); end
 end
 drawnow;
 q=questdlg('检查绿色喷嘴坐标；旧默认值也需要确认。','喷嘴坐标','确认','修改','取消','修改');
 if strcmp(q,'取消')||isempty(q), error('spray:Cancelled','已取消标定。'); end
 if strcmp(q,'确认'), break; end
 a=inputdlg({'喷嘴X（列）','喷嘴Y（行）'},'修改坐标',1,{num2str(c.x0),num2str(c.y0)});
 if isempty(a), continue; end
 xy=str2double(a);
 if any(~isfinite(xy))||xy(1)<1||xy(1)>w||xy(2)<1||xy(2)>h, continue; end
 c.x0=xy(1); c.y0=xy(2);
end
figure(f); clf(f); imshow(reference,[]); hold on; plot(c.x0,c.y0,'g+');
if mode=="multi_plume"
 a=inputdlg('当前参考帧中可独立辨认的喷束数（2至8）','束数',1,{'5'});
 if isempty(a), error('spray:Cancelled','取消束数设置。'); end
 n=str2double(a{1}); if ~isscalar(n)||~isfinite(n)||n<2||n>8||fix(n)~=n, error('束数必须为2至8的整数。'); end
 title(sprintf('在清晰早期参考帧，按左到右点击%d条喷束中心方向',n));
 [x,y]=ginput(n); if numel(x)~=n||any(y<=c.y0), error('参考方向设置未完成。'); end
 c.angles=atan2d(x-c.x0,y-c.y0);
 if any(diff(c.angles)<=1), error('请按左到右选择独立喷束。'); end
 c.edges=[-90; (c.angles(1:end-1)+c.angles(2:end))/2;90]';
 for j=1:n, plot([c.x0 x(j)],[c.y0 y(j)],'c-'); end
else
 title('点击整体参考轴方向上的一点'); [x,y]=ginput(1);
 if isempty(x)||y<=c.y0, error('参考轴设置未完成。'); end
 c.axisAngle=atan2d(x-c.x0,y-c.y0);
 plot([c.x0 x],[c.y0 y],'c-');
end
q=questdlg('确认原图中的参考方向？','方向确认','确认','取消','确认');
if ~strcmp(q,'确认'), error('spray:Cancelled','取消方向设置。'); end
c.reviewedVersion='20260922_review2';
end
function closeFigure(f)
if ishghandle(f), close(f); end
end
