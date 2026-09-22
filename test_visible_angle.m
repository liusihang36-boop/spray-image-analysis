function test_visible_angle
% MATLAB R2023a 中运行；已知几何验证，与实验有效率无关。
addpath(fullfile(fileparts(mfilename('fullpath')),'src'));
z=(10:100)';lo=-z*tand(10);hi=z*tand(15);E=false(250,250);
a=spray_visible_angle(z,lo,hi,[20 80],E,125,10,[0 1],[1 0]);
assert(abs(a-25)<1e-10,'理想锥体张角不正确');
% 平移坐标不应改变角度。
b=spray_visible_angle(z,lo,hi,[20 80],E,130,20,[0 1],[1 0]);
assert(abs(a-b)<1e-10,'平移改变角度');
% 遮挡端点必须阻止伪完整角。
E(:)=true;c=spray_visible_angle(z,lo,hi,[20 80],E,125,10,[0 1],[1 0]);
assert(isnan(c),'遮挡端点仍输出角度');
E(:)=false;c=spray_visible_angle(z(1:3),lo(1:3),hi(1:3),[10 80],E,125,10,[0 1],[1 0]);
assert(isnan(c),'截面不足仍输出角度');
fprintf('可见截面张角几何检查通过。\n');
end
