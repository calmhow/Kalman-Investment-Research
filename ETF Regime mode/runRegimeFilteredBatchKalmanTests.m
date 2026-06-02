%% runRegimeFilteredBatchKalmanTests.m
% Batch runner for ETF-regime-filtered Kalman strategy testing.
%
% File-tree expectation:
%   project root/
%       data/
%       ETF Regime mode/
%           batchruns/
%           walkforward/
%           runRegimeFilteredBatchKalmanTests.m
%
% This script compares:
%   1. Buy-and-hold
%   2. Baseline 0/1 Kalman strategy
%   3. Partial-exposure Kalman strategy
%   4. Selected strategy
%   5. Selected strategy + SPY soft regime filter
%
% Soft regime filter:
%   SPY baseline position is used as the broad-market risk-on/risk-off filter.
%   If SPY is risk-on, selected exposure is unchanged.
%   If SPY is risk-off, selected exposure is scaled by regimeRiskOffScale.

clear; clc; close all;

%% ---------------- Path Setup ----------------
scriptDir = string(fileparts(mfilename('fullpath')));
projectRoot = string(fileparts(scriptDir));
dataDir = fullfile(projectRoot, "data");
addpath(projectRoot);

%% ---------------- Model Configuration Table ----------------
modelConfig = table( ...
    ["SPY"; "QQQ"; "SPYG"], ...
    ["Baseline"; "Exposure"; "Exposure"], ...
    [5e-4; 1e-3; 5e-4], ...
    [1e-7; 1e-7; 1e-7], ...
    [5; 5; 5], ...
    [8; 8; 8], ...
    'VariableNames', ["Ticker", "SelectedStrategy", "r_meas", "q_jerk", "BuyConfirmDays", "SellConfirmDays"]);

regimeRiskOffScale =.5;

%% ---------------- Shared Non-Model Settings ----------------
transactionCost = 0.001;
makePlots = true;
showStatePlots = false;
printSummary = false;
runPartialExposure = true;

%% ---------------- SPY Regime Filter Parameters ----------------
spyRegimeParams = struct();
spyRegimeParams.q_jerk = 1e-7;
spyRegimeParams.r_meas = 5e-4;
spyRegimeParams.buyConfirmDays = 5;
spyRegimeParams.sellConfirmDays = 8;
spyRegimeParams.transactionCost = transactionCost;
spyRegimeParams.makePlots = false;
spyRegimeParams.showStatePlots = false;
spyRegimeParams.printSummary = false;
spyRegimeParams.runPartialExposure = true;

spyRegimeFile = fullfile(dataDir, "SPY.csv");

fprintf("Running SPY regime filter model...\n");
[spyRegimeResults, ~] = runKalmanTrendModel_partialExposure(spyRegimeFile, spyRegimeParams);

summaryRows = table();

%% ---------------- Run Batch Tests ----------------
for i = 1:height(modelConfig)

    ticker = modelConfig.Ticker(i);
    filename = fullfile(dataDir, ticker + ".csv");

    fprintf("Running regime-filtered selected configuration for %s...\n", ticker);

    params = struct();
    params.q_jerk = modelConfig.q_jerk(i);
    params.r_meas = modelConfig.r_meas(i);
    params.buyConfirmDays = modelConfig.BuyConfirmDays(i);
    params.sellConfirmDays = modelConfig.SellConfirmDays(i);
    params.transactionCost = transactionCost;
    params.makePlots = makePlots;
    params.showStatePlots = showStatePlots;
    params.printSummary = printSummary;
    params.runPartialExposure = runPartialExposure;

    [results, summary] = runKalmanTrendModel_partialExposure(filename, params);

    selectedStrategy = modelConfig.SelectedStrategy(i);
    selected = getSelectedBranchSummary(summary, selectedStrategy);

    selectedExposure = getSelectedExposure(results, selectedStrategy);
    spyRiskOn = alignRegimePosition(results.Date, spyRegimeResults.Date, spyRegimeResults.Position);

    regimeScale = regimeRiskOffScale + (1 - regimeRiskOffScale) * spyRiskOn;
    regimeFilteredExposure = selectedExposure .* regimeScale;

    regime = summarizeExposureBranch(results.DailyReturn, regimeFilteredExposure, transactionCost);

    regimeExcessReturn = regime.totalReturn - summary.buyHoldTotalReturn;
    regimeDrawdownImprovement = regime.maxDrawdown - summary.buyHoldMaxDrawdown;
    regimeSharpeImprovement = regime.sharpe - summary.buyHoldSharpeApprox;

    newRow = table( ...
        ticker, selectedStrategy, summary.startDate, summary.endDate, summary.q_jerk, summary.r_meas, ...
        summary.buyConfirmDays, summary.sellConfirmDays, regimeRiskOffScale, ...
        100*summary.buyHoldTotalReturn, 100*summary.baselineTotalReturn, 100*summary.exposureTotalReturn, ...
        selected.returnPct, 100*regime.totalReturn, ...
        100*summary.buyHoldMaxDrawdown, 100*summary.baselineMaxDrawdown, 100*summary.exposureMaxDrawdown, ...
        selected.maxDrawdownPct, 100*regime.maxDrawdown, ...
        summary.buyHoldSharpeApprox, summary.baselineSharpeApprox, summary.exposureSharpeApprox, ...
        selected.sharpe, regime.sharpe, ...
        summary.buyHoldBuyCount, summary.baselineBuyCount, summary.exposureBuyCount, selected.buyCount, regime.buyCount, ...
        summary.buyHoldSellCount, summary.baselineSellCount, summary.exposureSellCount, selected.sellCount, regime.sellCount, ...
        summary.buyHoldTradeCount, summary.baselineTradeCount, summary.exposureTradeCount, selected.tradeCount, regime.tradeCount, ...
        100*summary.buyHoldTimeInMarket, 100*summary.baselineTimeInMarket, 100*summary.exposureTimeInMarket, ...
        selected.timeInMarketPct, 100*regime.timeInMarket, ...
        100*summary.averageExposure, selected.averageExposurePct, 100*regime.averageExposure, ...
        summary.exposureTurnoverTotal, regime.turnoverTotal, ...
        getSummaryField(summary, "exposureTargetAdjustmentCount", NaN), ...
        getSummaryField(summary, "exposureHysteresisDelayCount", NaN), ...
        getSummaryField(summary, "maxSellPressure", NaN), ...
        getSummaryField(summary, "avgSellPressureWhileLong", NaN), ...
        100*mean(spyRiskOn > 0), 100*mean(regimeScale), ...
        100*summary.buyHoldExcessReturn, 100*summary.baselineExcessReturn, 100*summary.exposureExcessReturn, ...
        selected.excessReturnPct, 100*regimeExcessReturn, ...
        100*summary.buyHoldDrawdownImprovement, 100*summary.baselineDrawdownImprovement, 100*summary.exposureDrawdownImprovement, ...
        selected.drawdownImprovementPct, 100*regimeDrawdownImprovement, ...
        summary.buyHoldSharpeImprovement, summary.baselineSharpeImprovement, summary.exposureSharpeImprovement, ...
        selected.sharpeImprovement, regimeSharpeImprovement, ...
        100*(regime.totalReturn - selected.returnDecimal), ...
        100*(regime.maxDrawdown - selected.maxDrawdownDecimal), ...
        regime.sharpe - selected.sharpe, ...
        'VariableNames', [ ...
        "Ticker", "SelectedStrategy", "StartDate", "EndDate", "q_jerk", "r_meas", ...
        "BuyConfirmDays", "SellConfirmDays", "RegimeRiskOffScale", ...
        "BuyHoldReturnPct", "BaselineReturnPct", "ExposureReturnPct", "SelectedReturnPct", "RegimeFilteredReturnPct", ...
        "BuyHoldMaxDrawdownPct", "BaselineMaxDrawdownPct", "ExposureMaxDrawdownPct", "SelectedMaxDrawdownPct", "RegimeFilteredMaxDrawdownPct", ...
        "BuyHoldSharpe", "BaselineSharpe", "ExposureSharpe", "SelectedSharpe", "RegimeFilteredSharpe", ...
        "BuyHoldBuyCount", "BaselineBuyCount", "ExposureBuyCount", "SelectedBuyCount", "RegimeFilteredBuyCount", ...
        "BuyHoldSellCount", "BaselineSellCount", "ExposureSellCount", "SelectedSellCount", "RegimeFilteredSellCount", ...
        "BuyHoldTradeCount", "BaselineTradeCount", "ExposureTradeCount", "SelectedTradeCount", "RegimeFilteredTradeCount", ...
        "BuyHoldTimeInMarketPct", "BaselineTimeInMarketPct", "ExposureTimeInMarketPct", "SelectedTimeInMarketPct", "RegimeFilteredTimeInMarketPct", ...
        "ExposureAveragePct", "SelectedAverageExposurePct", "RegimeFilteredAverageExposurePct", ...
        "ExposureTurnoverTotal", "RegimeFilteredTurnoverTotal", ...
        "ExposureTargetAdjustmentCount", "ExposureHysteresisDelayCount", "MaxSellPressure", "AvgSellPressureWhileLong", "SPYRegimeRiskOnPct", "AverageRegimeScalePct", ...
        "BuyHoldExcessReturnPct", "BaselineExcessReturnPct", "ExposureExcessReturnPct", "SelectedExcessReturnPct", "RegimeFilteredExcessReturnPct", ...
        "BuyHoldDrawdownImprovementPct", "BaselineDrawdownImprovementPct", "ExposureDrawdownImprovementPct", "SelectedDrawdownImprovementPct", "RegimeFilteredDrawdownImprovementPct", ...
        "BuyHoldSharpeImprovement", "BaselineSharpeImprovement", "ExposureSharpeImprovement", "SelectedSharpeImprovement", "RegimeFilteredSharpeImprovement", ...
        "RegimeFilteredVsSelectedReturnPct", "RegimeFilteredVsSelectedDrawdownImprovementPct", "RegimeFilteredVsSelectedSharpeImprovement"]);

    summaryRows = [summaryRows; newRow];
end

%% ---------------- Display and Save Results ----------------
disp(summaryRows);

batchRunsDir = fullfile(scriptDir, "batchruns");

if ~isfolder(batchRunsDir)
    mkdir(batchRunsDir);
end

outFile = fullfile(batchRunsDir, "batch_regime_filtered_strategy.xlsx");

requiredRegimeColumns = [ ...
    "RegimeRiskOffScale", ...
    "RegimeFilteredReturnPct", ...
    "RegimeFilteredMaxDrawdownPct", ...
    "RegimeFilteredSharpe", ...
    "SPYRegimeRiskOnPct", ...
    "AverageRegimeScalePct", ...
    "RegimeFilteredVsSelectedReturnPct", ...
    "RegimeFilteredVsSelectedDrawdownImprovementPct", ...
    "RegimeFilteredVsSelectedSharpeImprovement"];

missingRegimeColumns = setdiff(requiredRegimeColumns, string(summaryRows.Properties.VariableNames));

if ~isempty(missingRegimeColumns)
    error("Missing expected regime-filter output columns: %s", strjoin(missingRegimeColumns, ", "));
end

fprintf("\nConfirmed regime-filter batch output columns are present.\n");

% Force overwrite so an older workbook does not hide the new columns.
if isfile(outFile)
    delete(outFile);
end

writetable(summaryRows, outFile);

fprintf("\nRegime-filtered batch summary saved to: %s\n", outFile);

%% ---------------- Local Helper Functions ----------------
function selected = getSelectedBranchSummary(summary, selectedStrategy)

    selected = struct();

    if selectedStrategy == "Exposure"
        selected.returnDecimal = summary.exposureTotalReturn;
        selected.maxDrawdownDecimal = summary.exposureMaxDrawdown;
        selected.sharpe = summary.exposureSharpeApprox;
        selected.buyCount = summary.exposureBuyCount;
        selected.sellCount = summary.exposureSellCount;
        selected.tradeCount = summary.exposureTradeCount;
        selected.timeInMarketPct = 100*summary.exposureTimeInMarket;
        selected.averageExposurePct = 100*summary.averageExposure;
        selected.excessReturnPct = 100*summary.exposureExcessReturn;
        selected.drawdownImprovementPct = 100*summary.exposureDrawdownImprovement;
        selected.sharpeImprovement = summary.exposureSharpeImprovement;
    elseif selectedStrategy == "Baseline"
        selected.returnDecimal = summary.baselineTotalReturn;
        selected.maxDrawdownDecimal = summary.baselineMaxDrawdown;
        selected.sharpe = summary.baselineSharpeApprox;
        selected.buyCount = summary.baselineBuyCount;
        selected.sellCount = summary.baselineSellCount;
        selected.tradeCount = summary.baselineTradeCount;
        selected.timeInMarketPct = 100*summary.baselineTimeInMarket;
        selected.averageExposurePct = 100*summary.baselineTimeInMarket;
        selected.excessReturnPct = 100*summary.baselineExcessReturn;
        selected.drawdownImprovementPct = 100*summary.baselineDrawdownImprovement;
        selected.sharpeImprovement = summary.baselineSharpeImprovement;
    else
        error("Unknown selectedStrategy. Use 'Baseline' or 'Exposure'.");
    end

    selected.returnPct = 100*selected.returnDecimal;
    selected.maxDrawdownPct = 100*selected.maxDrawdownDecimal;
end

function selectedExposure = getSelectedExposure(results, selectedStrategy)

    if selectedStrategy == "Exposure"
        selectedExposure = results.Exposure;
    elseif selectedStrategy == "Baseline"
        selectedExposure = results.Position;
    else
        error("Unknown selectedStrategy. Use 'Baseline' or 'Exposure'.");
    end
end

function spyRiskOn = alignRegimePosition(targetDates, spyDates, spyPosition)

    [tf, loc] = ismember(targetDates, spyDates);

    spyRiskOn = zeros(length(targetDates),1);
    spyRiskOn(tf) = spyPosition(loc(tf));

    if any(~tf)
        warning("%d target dates did not match SPY regime dates. Missing regime dates are treated as risk-off.", sum(~tf));
    end
end

function branch = summarizeExposureBranch(dailyReturn, exposure, transactionCost)

    exposure = double(exposure(:));
    dailyReturn = dailyReturn(:);

    branchReturn = [0; exposure(1:end-1) .* dailyReturn(2:end)];
    turnover = [0; abs(diff(exposure))];

    branchReturnNet = branchReturn - transactionCost * turnover;
    branchEquity = cumprod(1 + branchReturnNet);

    branchRunningMax = cummax(branchEquity);
    branchDrawdown = branchEquity ./ branchRunningMax - 1;

    branch = struct();
    branch.totalReturn = branchEquity(end) - 1;
    branch.maxDrawdown = min(branchDrawdown);
    branch.sharpe = safeSharpe(branchReturnNet);
    branch.buyCount = sum(exposure(1:end-1) == 0 & exposure(2:end) > 0);
    branch.sellCount = sum(exposure(1:end-1) > 0 & exposure(2:end) == 0);
    branch.tradeCount = sum(abs(diff(exposure)) > 0);
    branch.timeInMarket = mean(exposure > 0);
    branch.averageExposure = mean(exposure);
    branch.turnoverTotal = sum(turnover);
end

function value = getSummaryField(summary, fieldName, defaultValue)

    if isfield(summary, fieldName)
        value = summary.(fieldName);
    else
        value = defaultValue;
    end
end

function sharpe = safeSharpe(returns)

    s = std(returns);

    if s == 0 || isnan(s)
        sharpe = NaN;
    else
        sharpe = sqrt(252) * mean(returns) / s;
    end
end
