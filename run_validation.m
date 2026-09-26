function result = run_validation(validationDir,settingsFile,analysisMode)
%RUN_VALIDATION 固定验证数据的一键处理入口（MATLAB R2023a）。
% 可指定独立settingsFile；不存在时首次人工确认并保存，后续仅复用该配置。

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
if nargin>=1 && ~isempty(validationDir)
    if ~isfolder(validationDir), error('指定的验证数据目录不存在：%s',validationDir); end
    cfg.validationDir=char(validationDir);
end
if ~isfield(cfg,'validationDir') || ~isfolder(cfg.validationDir)
    error('本地配置中的验证数据目录不存在，请重新运行setup_local。');
end

if nargin<3 || isempty(analysisMode)
    choice=questdlg('请选择本工况测量方式，旧三束仅用于对照。', ...
        '确认分析模式','多束参考','整体喷雾','旧三束对照','多束参考');
    switch choice
        case '多束参考', analysisMode="multi_plume";
        case '整体喷雾', analysisMode="merged_spray";
        case '旧三束对照', analysisMode="three_jets";
        otherwise, error('spray:Cancelled','取消模式选择。');
    end
end
analysisMode=lower(string(analysisMode));
if ~ismember(analysisMode,["three_jets","merged_spray","multi_plume"])
    error('analysisMode必须为three_jets、merged_spray或multi_plume。');
end
if nargin<2 || isempty(settingsFile)
    if analysisMode~="three_jets"
        settingsFile=fullfile(cfg.validationDir,'measurement_settings_merged.mat');
    else
        settingsFile=fullfile(cfg.validationDir,'measurement_settings.mat');
    end
else
    settingsFile=char(settingsFile);
end

fprintf('验证数据：%s\n',cfg.validationDir);
fprintf('阶段1/2：处理0~%.1f ms原始序列...\n',cfg.analysisEnd_ms);
preprocessRoot=spray_preprocess_trial(cfg.validationDir);
if isempty(preprocessRoot) || ~isfolder(preprocessRoot)
    error('预处理未完成，没有生成有效结果目录。');
end

spray_write_run_manifest(preprocessRoot,repoRoot,analysisMode,cfg.validationDir,settingsFile,'measurement_pending');

fprintf('阶段2/2：分析模式 %s。\n',analysisMode);
if isfile(settingsFile)
    fprintf('读取本工况独立测量配置。\n');
    if analysisMode~="three_jets"
        if analysisMode=="multi_plume"
            measurementRoot=spray_measure_multiplume(preprocessRoot,settingsFile,cfg.validationDir);
        else
            measurementRoot=spray_measure_merged(preprocessRoot,settingsFile,cfg.validationDir);
        end
    else
        measurementRoot=spray_measure_threejets(preprocessRoot,settingsFile,cfg.validationDir);
    end
else
    fprintf('未找到固定测量配置，本次进入首次人工确认。\n');
    if analysisMode~="three_jets"
        if analysisMode=="multi_plume"
            measurementRoot=spray_measure_multiplume(preprocessRoot,[],cfg.validationDir);
        else
            measurementRoot=spray_measure_merged(preprocessRoot,[],cfg.validationDir);
        end
    else
        measurementRoot=spray_measure_threejets(preprocessRoot,[],cfg.validationDir);
    end
    generatedSettings=fullfile(measurementRoot,'measurement_settings.mat');
    if isfile(generatedSettings)
        settingsDir=fileparts(settingsFile);
        if ~isempty(settingsDir) && ~isfolder(settingsDir), mkdir(settingsDir); end
        copyfile(generatedSettings,settingsFile);
        fprintf('首次确认参数已保存：%s\n',settingsFile);
    end
end
result=struct('preprocessRoot',preprocessRoot,'measurementRoot',measurementRoot, ...
    'analysisMode',analysisMode,'completedAt',datetime('now'));
if analysisMode~="three_jets"
    result.reportFile=generate_merged_report(measurementRoot);
else
    result.reportFile=generate_validation_report(measurementRoot);
end
save(fullfile(preprocessRoot,'validation_run.mat'),'result','cfg');
spray_write_run_manifest(preprocessRoot,repoRoot,analysisMode,cfg.validationDir,settingsFile,'completed');
fprintf('本次验证结束。结果目录：%s\n',preprocessRoot);
end

