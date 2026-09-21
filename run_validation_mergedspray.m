function result=run_validation_mergedspray(validationDir,settingsFile)
%RUN_VALIDATION_MERGEDSPRAY 塌缩/合并后整体喷雾入口。
if nargin<1, validationDir=[]; end
if nargin<2, settingsFile=[]; end
result=run_validation(validationDir,settingsFile,"merged_spray");
end
