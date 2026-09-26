function [angle,left,right,coverage,reason,sections]=spray_visible_angle(z,lo,hi,range,edge,x0,y0,ax,nv)
% 固定区间内各可见截面的喷嘴张角中位数；不是边界斜率夹角。
z=z(:);lo=lo(:);hi=hi(:);
q=z>0&z>=range(1)&z<=range(2)&isfinite(lo)&isfinite(hi)&hi>lo;
zz=z(q); ll=lo(q); rr=hi(q);
a=[x0 y0]+zz*ax+ll*nv; b=[x0 y0]+zz*ax+rr*nv;
[h,w]=size(edge); good=true(size(zz));
for k=1:numel(zz)
 xy=round([a(k,:);b(k,:)]);
 if any(xy(:,1)<1|xy(:,1)>w|xy(:,2)<1|xy(:,2)>h), good(k)=false; continue; end
 good(k)=~any(edge(sub2ind([h w],xy(:,2),xy(:,1))));
end
coverage=nnz(good)/max(1,floor(range(2))-ceil(range(1))+1);
sections=[];
angle=NaN;left=NaN;right=NaN;reason="可见截面不足";
if nnz(good)<5||coverage<.5, return; end
% 半角保留符号，避免将收缩或轴线偏移强行截为零。
l=-atan2d(ll(good),zz(good)); r=atan2d(rr(good),zz(good));
sections=[a(good,:) b(good,:)];
angle=median(l+r);left=median(l);right=median(r);reason="可见截面张角";
end

