function spray_write_run_manifest(outputDir,repoRoot,mode,raw,settingsFile,stage)
% 保存实际调用位置及Git状态；无法获取版本时明确记录，不阻止数据处理。
m=struct('recordedAt',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')), ...
 'stage',char(stage),'analysisMode',char(mode),'rawDirectory',char(raw), ...
 'settingsFile',char(settingsFile),'matlabVersion',version,'gitCommit','unknown', ...
 'gitStatus','unknown');
names={'run_validation','spray_preprocess_trial','spray_measure_merged', ...
 'spray_measure_multiplume','spray_measure_threejets','spray_visible_angle'};
for k=1:numel(names)
 m.resolvedFunctions.(names{k})=which(names{k});
 m.allFunctionMatches.(names{k})=which(names{k},'-all');
end
% 路径来自本地代码目录。含命令行特殊字符时跳过Git查询。
if isempty(regexp(repoRoot,'["$`%\r\n]','once'))
 [ok,rev]=system(sprintf('git -C "%s" rev-parse HEAD',repoRoot));
 if ok==0, m.gitCommit=strtrim(rev); end
 [ok,status]=system(sprintf('git -C "%s" status --porcelain',repoRoot));
 if ok==0, m.gitStatus=strtrim(status); end
end
fid=fopen(fullfile(outputDir,'run_manifest.json'),'w','n','UTF-8');
if fid<0, error('无法写入运行追溯记录。'); end
closer=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',jsonencode(m,'PrettyPrint',true));
end
