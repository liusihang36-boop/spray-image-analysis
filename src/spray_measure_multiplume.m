function out=spray_measure_multiplume(root,settingsFile,raw)
% 可变束数测量：参考扇区只是身份假设；接触分界的指标必须标记。
% 先输出整体可见喷雾，后输出参考分束；不可辨帧不重编号、不补边界。
whole=spray_measure_merged(root,settingsFile,raw);
c=load(fullfile(whole,'measurement_settings.mat'));
s=load(fullfile(root,'settings.mat'));
[rf,rp]=uigetfile(fullfile(raw,'*.bmp'),'选择能分辨全部喷束的早期原图');
if isequal(rf,0), error('spray:Cancelled','取消多束参考帧。'); end
I=imread(fullfile(rp,rf));if ndims(I)==3,I=rgb2gray(I);end
c=spray_confirm_geometry(s.B,I,c,"multi_plume");
out=whole;save(fullfile(out,'multiplume_settings.mat'),'-struct','c');
[h,w]=size(s.valid);[X,Y]=meshgrid(1:w,1:h);theta=atan2d(X-c.x0,Y-c.y0);
combined=table;
for j=1:numel(c.angles)
 stage=fullfile(whole,sprintf('reference_plume_%02d',j));mkdir(stage);mkdir(fullfile(stage,'6'));
 sector=Y>c.y0&theta>=c.edges(j)&theta<c.edges(j+1);
 sj=s;sj.physicalValid=logical(s.valid);sj.sectorMask=sector;
 sj.valid=logical(s.valid)&sector;
 save(fullfile(stage,'settings.mat'),'-struct','sj');
 copyfile(fullfile(root,'processing_log.csv'),fullfile(stage,'processing_log.csv'));
 files=dir(fullfile(root,'6','*.bmp'));
 for k=1:numel(files)
  M=imread(fullfile(files(k).folder,files(k).name));
  if ndims(M)==3,M=M(:,:,1);end
  imwrite((M~=0)&sector,fullfile(stage,'6',files(k).name));
 end
 cfg=c;cfg.axisAngle=c.angles(j);cfg.internalConfirmed=true;
 fp=fullfile(stage,'reference_settings.mat');save(fp,'-struct','cfg');
 one=spray_measure_merged(stage,fp,raw);r=load(fullfile(one,'measurements.mat'),'T');
 t=r.T;t.Jet=repmat(string(sprintf('参考束%d',j)),height(t),1);
 t.AssignmentStatus=repmat("参考扇区内可见，须原图复核",height(t),1);
 t.AssignmentStatus(t.WindowTouch)="触及物理遮挡，须复核可见范围";
 t.AssignmentStatus(t.SectorContact)="接触参考分界，独立归属不确定";
 % 保留局部质量合格的可见截面量；它们不是已确认身份的独立喷束锥角。
 t.AngleDefinition(:)="参考扇区可见截面张角_非已确认独立束角";
 combined=[combined;t]; %#ok<AGROW>
end
T=combined;save(fullfile(out,'multiplume_measurements.mat'),'T');
writetable(T,fullfile(out,'多束参考测量.xlsx'));
end

