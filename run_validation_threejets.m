function result=run_validation_threejets(validationDir,settingsFile)
%RUN_VALIDATION_THREEJETS 未合并三束喷雾入口。
if nargin<1, validationDir=[]; end
if nargin<2, settingsFile=[]; end
result=run_validation(validationDir,settingsFile,"three_jets");
end
