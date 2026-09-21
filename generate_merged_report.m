function reportFile=generate_merged_report(measurementRoot)
%GENERATE_MERGED_REPORT 整体喷雾有效率和质量标记汇总。
s=load(fullfile(measurementRoot,'measurements.mat'),'T'); T=s.T; n=height(T);
names={'贯穿距','整体拟合锥角','下游展开角','整体面积','主体贯穿距','主体拟合锥角','主体下游角'};
vars={'Penetration_mm','ConeAngle_deg','DownstreamAngle_deg','Area_mm2', ...
 'CorePenetration_mm','CoreConeAngle_deg','CoreDownstreamAngle_deg'};
rows=cell(numel(vars),4);
for k=1:numel(vars)
 valid=isfinite(T.(vars{k})); rows(k,:)={names{k},nnz(valid),100*nnz(valid)/max(n,1),vars{k}};
end
reportFile=fullfile(measurementRoot,'整体喷雾自动验证报告.xlsx');
writecell([{'指标','有效帧数','有效率_pct','字段名'};rows],reportFile,'Sheet','整体质量汇总');
diag={'总帧数',n;'自动可靠帧数',nnz(T.Reliable);'自动可靠率_pct',100*mean(T.Reliable); ...
 '触及视窗帧数',nnz(T.WindowTouch);'脱离喷嘴帧数',nnz(T.Detached); ...
 '前端支撑不足帧数',nnz(T.TipSupportPixels<20);'边界拟合RMSE中位数_px',median(T.BoundaryRMSE_px,'omitnan'); ...
 '下游拟合RMSE中位数_px',median(T.DownstreamRMSE_px,'omitnan')};
writecell([{'诊断项','值'};diag],reportFile,'Sheet','整体诊断');
writetable(T(:,{'File','Time_ms','Status','Error'}),reportFile,'Sheet','逐帧状态');
fprintf('整体喷雾：贯穿距 %.1f%%，整体锥角 %.1f%%，下游角 %.1f%%，自动可靠 %.1f%%。\n', ...
 rows{1,3},rows{2,3},rows{3,3},100*mean(T.Reliable));
end
