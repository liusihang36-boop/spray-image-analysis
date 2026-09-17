function reportFile = generate_validation_report(measurementRoot)
%GENERATE_VALIDATION_REPORT 自动汇总三束喷雾测量完整性和质量标记。

dataFile=fullfile(measurementRoot,'measurements.mat');
if ~isfile(dataFile), error('缺少测量数据：%s',dataFile); end
s=load(dataFile,'T'); T=s.T;
required={'Jet','Penetration_mm','ConeAngle_deg','DownstreamAngle_deg', ...
    'CoreCone_deg','CoreDown_deg','TemporalJump','Status'};
if ~all(ismember(required,T.Properties.VariableNames))
    error('measurements.mat字段不完整，无法生成质量报告。');
end

labels=["Left","Middle","Right"];
zh=["左束","中束","右束"];
head={'喷束','总时间点','识别到贯穿距','贯穿距识别率_pct', ...
    '正式锥角有效数','正式锥角有效率_pct','灰度主体锥角有效数','灰度主体锥角有效率_pct', ...
    '下游展开角有效数','下游展开角有效率_pct','灰度主体下游角有效数','灰度主体下游角有效率_pct', ...
    '相邻帧异常跳变数','处理失败数'};
rows=cell(3,numel(head));
for j=1:3
    q=T.Jet==labels(j); n=nnz(q);
    lengthN=nnz(isfinite(T.Penetration_mm(q)));
    coneN=nnz(isfinite(T.ConeAngle_deg(q)));
    coreConeN=nnz(isfinite(T.CoreCone_deg(q)));
    downN=nnz(isfinite(T.DownstreamAngle_deg(q)));
    coreDownN=nnz(isfinite(T.CoreDown_deg(q)));
    rows(j,:)={char(zh(j)),n,lengthN,pct(lengthN,n),coneN,pct(coneN,n), ...
        coreConeN,pct(coreConeN,n),downN,pct(downN,n),coreDownN,pct(coreDownN,n), ...
        nnz(T.TemporalJump(q)),nnz(T.Status(q)=="failed")};
end

reportFile=fullfile(measurementRoot,'自动验证报告.xlsx');
writecell([head;rows],reportFile,'Sheet','三束质量汇总');

problem=T.TemporalJump | T.Status=="failed";
detailHead={'原始文件名','时间_ms','喷束','处理状态','时间突变','错误详情'};
detailRows=cell(nnz(problem),numel(detailHead));
ix=find(problem);
for k=1:numel(ix)
    i=ix(k); jet=zh(labels==T.Jet(i));
    detailRows(k,:)={char(T.File(i)),T.Time_ms(i),char(jet),char(T.Status(i)), ...
        double(T.TemporalJump(i)),char(T.Error(i))};
end
writecell([detailHead;detailRows],reportFile,'Sheet','异常帧');

fprintf('\n自动质量汇总：\n');
for j=1:3
    fprintf('%s：贯穿距 %.1f%%，正式锥角 %.1f%%，灰度主体锥角 %.1f%%，下游展开角 %.1f%%。\n', ...
        rows{j,1},rows{j,4},rows{j,6},rows{j,8},rows{j,10});
end
fprintf('质量报告：%s\n',reportFile);
end

function value=pct(count,total)
if total<=0, value=NaN; else, value=100*count/total; end
end
