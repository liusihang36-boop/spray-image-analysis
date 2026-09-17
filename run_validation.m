function result = run_validation
%RUN_VALIDATION 固定验证数据的一键处理入口（MATLAB R2023a）。
% 第一次运行仍需确认标定、喷嘴和分界；后续版本将复用确认配置。

repoRoot=fileparts(mfilename('fullpath'));
if isfolder(fullfile(repoRoot,'src'))
    addpath(fullfile(repoRoot,'src'));
elseif isfolder(repoRoot)
    addpath(repoRoot);
end
cfgFile=fullfile(repoRoot,'config','local_config.mat');
if ~isfile(cfgFile)
    error('未找到config/local_config.mat，请先在仓库根目录运行setup_local。');
end
s=load(cfgFile,'cfg'); cfg=s.cfg;
if ~isfield(cfg,'validationDir') || ~isfolder(cfg.validationDir)
    error('本地配置中的验证数据目录不存在，请重新运行setup_local。');
end

fprintf('验证数据：%s\n',cfg.validationDir);
fprintf('阶段1/2：处理0~%.1f ms原始序列...\n',cfg.analysisEnd_ms);
preprocessRoot=spray_preprocess_trial(cfg.validationDir);
if isempty(preprocessRoot) || ~isfolder(preprocessRoot)
    error('预处理未完成，没有生成有效结果目录。');
end

fprintf('阶段2/2：测量左、中、右三束喷雾...\n');
measurementRoot=spray_measure_threejets(preprocessRoot);
result=struct('preprocessRoot',preprocessRoot, ...
    'measurementRoot',measurementRoot,'completedAt',datetime('now'));
save(fullfile(preprocessRoot,'validation_run.mat'),'result','cfg');
fprintf('本次验证结束。结果目录：%s\n',preprocessRoot);
end
