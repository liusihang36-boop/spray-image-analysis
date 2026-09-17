function reportFile = generate_validation_report(measurementRoot)
%GENERATE_VALIDATION_REPORT 自动汇总三束喷雾测量完整性和质量标记。

dataFile=fullfile(measurementRoot,'measurements.mat');
if ~isfile(dataFile), error('缺少测量数据：%s',dataFile); end
s=load(dataFile); T=s.T;
required={'Jet','Penetration_mm','ConeAngle_deg','DownstreamAngle_deg', ...
    'CoreCone_deg','CoreDown_deg','TemporalJump','Status','AngleCandidate_deg', ...
    'TipTouch','TipSector','SectionTouch','SectionSector','Detached','TipComponentPixels','Error'};
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

diagHead={'喷束','有候选锥角','正式锥角缺失','截面不足','相邻帧突变', ...
    '前端触边','前端接近分界','测角截面触边','测角截面接近分界','近喷嘴无前景','前端支撑不足'};
diagRows=cell(3,numel(diagHead));
for j=1:3
    q=T.Jet==labels(j); missing=~isfinite(T.ConeAngle_deg) & isfinite(T.Penetration_mm);
    diagRows(j,:)={char(zh(j)),nnz(q&isfinite(T.AngleCandidate_deg)),nnz(q&missing), ...
        nnz(q&missing&~isfinite(T.AngleCandidate_deg)),nnz(q&missing&T.TemporalJump), ...
        nnz(q&missing&T.TipTouch),nnz(q&missing&T.TipSector), ...
        nnz(q&missing&T.SectionTouch),nnz(q&missing&T.SectionSector), ...
        nnz(q&missing&T.Detached),nnz(q&missing&(T.TipComponentPixels<20))};
end
writecell([diagHead;diagRows],reportFile,'Sheet','锥角缺失诊断');

if all(isfield(s,{'CoreThresholds','CoreSweepCone','CoreSweepDown','CoreSweepLeftHalf','CoreSweepRightHalf'}))
    sweepHead={'主体相对衰减阈值','喷束','完整锥角有效数','完整锥角有效率_pct', ...
        '左侧半角有效数','右侧半角有效数','仅单侧可见数','两侧均可见数', ...
        '下游展开角有效数','下游展开角有效率_pct'};
    sweepRows=cell(numel(s.CoreThresholds)*3,numel(sweepHead)); row=0;
    for qc=1:numel(s.CoreThresholds)
        for j=1:3
            row=row+1; q=T.Jet==labels(j); n=nnz(q);
            cone=isfinite(s.CoreSweepCone(q,qc)); down=isfinite(s.CoreSweepDown(q,qc));
            left=isfinite(s.CoreSweepLeftHalf(q,qc)); right=isfinite(s.CoreSweepRightHalf(q,qc));
            sweepRows(row,:)={s.CoreThresholds(qc),char(zh(j)),nnz(cone),pct(nnz(cone),n), ...
                nnz(left),nnz(right),nnz(xor(left,right)),nnz(left&right),nnz(down),pct(nnz(down),n)};
        end
    end
    writecell([sweepHead;sweepRows],reportFile,'Sheet','主体阈值敏感性');
end

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
    fprintf('%s：贯穿距 %.1f%%，正式锥角 %.1f%%，灰度主体锥角 %.1f%%，下游展开角 %.1f%%，灰度主体下游角 %.1f%%。\n', ...
        rows{j,1},rows{j,4},rows{j,6},rows{j,8},rows{j,10},rows{j,12});
    fprintf('  锥角缺失原因计数：截面不足%d，时间突变%d，前端触边%d，前端分界%d，截面触边%d，截面分界%d，脱离喷嘴%d，支撑不足%d。\n', ...
        diagRows{j,4},diagRows{j,5},diagRows{j,6},diagRows{j,7},diagRows{j,8}, ...
        diagRows{j,9},diagRows{j,10},diagRows{j,11});
end
if exist('sweepRows','var')
    fprintf('\n灰度主体阈值敏感性（完整锥角有效率%% / 下游角有效率%%）：\n');
    for row=1:size(sweepRows,1)
        fprintf('阈值 %.2f %s：%.1f / %.1f；仅单侧可见%d。\n', ...
            sweepRows{row,1},sweepRows{row,2},sweepRows{row,4},sweepRows{row,10},sweepRows{row,7});
    end
end
fprintf('质量报告：%s\n',reportFile);
end

function value=pct(count,total)
if total<=0, value=NaN; else, value=100*count/total; end
end
