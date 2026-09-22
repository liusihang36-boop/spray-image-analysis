function [excluded,meta]=spray_obstruction_mask(folder,B)
% 圈定所有风扇的完整扫掠范围，不按单帧叶片位置扣除。
path=fullfile(folder,'obstruction_settings.mat');
if isfile(path)
 s=load(path); excluded=logical(s.excluded); meta=s.meta;
 if ~isequal(size(excluded),size(B)), error('遮挡配置尺寸不符，请重做obstruction_settings.mat。'); end
 return;
end
excluded=false(size(B)); meta=struct('method','manual_full_sweep','confirmed',false);
f=figure('Name','风扇完整扫掠区域','Color','w'); imshow(B,[0 255]);
q=questdlg('是否存在旋转风扇？请选择完整扫掠区域，包含叶片所有可能位置。','动态遮挡','圈选扫掠区','无旋转风扇','取消','圈选扫掠区');
if isempty(q)||strcmp(q,'取消'), close(f); error('spray:Cancelled','取消遮挡配置。'); end
if strcmp(q,'圈选扫掠区')
 while true
  title('画多边形包围一台风扇的完整扫掠区域；双击结束');
  roi=drawpolygon; wait(roi); excluded=excluded|createMask(roi);
  q=questdlg('还需添加其他风扇扫掠区域吗？','扫掠区域','继续添加','完成','继续添加');
  if strcmp(q,'完成'), break; end
  if isempty(q), close(f); error('spray:Cancelled','取消遮挡配置。'); end
 end
end
meta.confirmed=true; close(f); save(path,'excluded','meta');
end
