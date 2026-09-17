function setup_local
% 本地自动验证环境初始化（MATLAB R2023a）
% 在仓库根目录运行一次：setup_local

clc;
repoRoot = fileparts(mfilename('fullpath'));
srcDir = fullfile(repoRoot,'src');
if ~isfolder(srcDir)
    error('未找到 src 文件夹。请从仓库根目录运行 setup_local。');
end
addpath(srcDir);

requiredRelease = 'R2023a';
currentRelease = version('-release');
fprintf('MATLAB版本：%s\n', currentRelease);
if ~strcmp(currentRelease,requiredRelease)
    warning('当前版本为%s；项目基准版本为%s。',currentRelease,requiredRelease);
end

toolboxInfo = ver('images');
hasFunctions = exist('bwareafilt','file')==2 && ...
    exist('imreconstruct','file')==2 && exist('imgaussfilt','file')==2;
if isempty(toolboxInfo) || ~hasFunctions
    error(['未检测到可用的 Image Processing Toolbox。' newline ...
        '请在MATLAB主页选择“附加功能→获取附加功能”，搜索并安装 Image Processing Toolbox。']);
end
fprintf('Image Processing Toolbox：%s（可用）\n',toolboxInfo.Version);

defaultValidationDir = 'D:\桌面\验证数据目录';
answer = inputdlg({'固定验证数据目录：'},'初始化本地验证环境',1,{defaultValidationDir});
if isempty(answer), return; end
validationDir = strtrim(answer{1});
if ~isfolder(validationDir)
    error('验证数据目录不存在：%s',validationDir);
end

bmpFiles = dir(fullfile(validationDir,'*.bmp'));
if isempty(bmpFiles)
    error('验证数据目录内没有BMP文件：%s',validationDir);
end

configDir = fullfile(repoRoot,'config');
if ~isfolder(configDir), mkdir(configDir); end
cfg = struct;
cfg.schemaVersion = 1;
cfg.matlabRelease = currentRelease;
cfg.validationDir = validationDir;
cfg.frameRate_fps = 25000;
cfg.analysisStartFrameOffset = 1;
cfg.analysisEnd_ms = 5;
cfg.windowDiameter_mm = 170;
cfg.createdAt = datetime('now');
save(fullfile(configDir,'local_config.mat'),'cfg');

fprintf('\n初始化完成。\n');
fprintf('验证目录：%s\n',validationDir);
fprintf('检测到BMP：%d张\n',numel(bmpFiles));
fprintf('本地配置：%s\n',fullfile(configDir,'local_config.mat'));
fprintf('local_config.mat已被.gitignore排除，不会上传到公开仓库。\n');
end
