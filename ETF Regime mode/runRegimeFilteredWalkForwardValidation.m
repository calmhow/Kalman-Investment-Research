%% runRegimeFilteredWalkForwardValidation.m
% Walk-forward validation for ETF-regime-filtered selected strategy.
%
% File-tree expectation:
%   project root/
%       data/
%       ETF Regime mode/
%           batchruns/
%           walkforward/
%           runRegimeFilteredWalkForwardValidation.m
%
% This script compares:
%   1. Buy-and-hold
%   2. Baseline 0/1 Kalman strategy
%   3. Partial-exposure Kalman strategy
%   4. Selected strategy
%   5. Selected strategy + SPY soft regime filter

clear; clc; close all;

%% ---------------- User Inputs ----------------
ticker = "QQQ";

scriptDir = string(fileparts(mfilename('fullpath')));
projectRoot = string(fileparts(scriptDir));
dataDir = fullfile(projectRoot, "data");
addpath(projectRoot);
filename = fullfile(dataDir, ticker + ".csv");

%% ---------------- Model Configuration Table ----------------
modelConfig = table( ...
    ["SPY"; "QQQ"; "SPYG"], ...
    ["Baseline"; "Exposure"; "Exposure"], ...
    [5e-4; 1e-3; 5e-4], ...
    [1e-7; 1e-7; 1e-7], ...
    [5; 5; 5], ...
    [8; 8; 8], ...
    'VariableNames', ["Ticker", "SelectedStrategy", "r_meas", "q_jerk", "BuyConfirmDays", "SellConfirmDays"]);

configIdx = find(modelConfig.Ticker == ticker, 1);

if isempty(configIdx)
    error("Ticker %s is not in modelConfig.", ticker);
end

selectedStrategyForTicker = modelConfig.SelectedStrategy(configIdx);

%% ---------------- Fixed Parameters for Selected Ticker ----------------
params = struct();
params.q_jerk = modelConfig.q_jerk(configIdx);
params.r_meas = modelConfig.r_meas(configIdx);
params.buyConfirmDays = modelConfig.BuyConfirmDays(configIdx);
params.sellConfirmDays = modelConfig.SellConfirmDays(configIdx);
params.transactionCost = 0.001;

jerk = sprintf("%.0e", params.q_jerk);
meas = sprintf("%.0e", params.r_meas);
buydays = sprintf("%d", params.buyConfirmDays);
selldays = sprintf("%d", params.sellConfirmDays);

params.makePlots = false;
params.showStatePlots = false;
params.printSummary = false;
params.runPartialExposure = true;

% Soft regime filter setting.
% 0.00 reproduces the earlier hard risk-off filter.
% 0.50 keeps half of selected exposure when SPY is risk-off.
regimeRiskOffScale = 0.50;

%% ---------------- SPY Regime Filter Parameters ----------------
spyRegimeParams = struct();
spyRegimeParams.q_jerk = 1e-7;
spyRegimeParams.r_meas = 5e-4;
spyRegimeParams.buyConfirmDays = 5;
spyRegimeParams.sellConfirmDays = 8;
spyRegimeParams.transactionCost = params.transactionCost;
spyRegimeParams.makePlots = false;
spyRegimeParams.showStatePlots = false;
spyRegimeParams.printSummary = false;
spyRegimeParams.runPartialExposure = true;

spyRegimeFile = fullfile(dataDir, "SPY.csv");

%% ---------------- Walk-Forward Settings ----------------
testYears = 2018:2026;
warmupYears = 3;
finalEndDate = datetime(2026,5,29);

walkForwardSummary = table();

%% ---------------- Run Walk-Forward Test ----------------
for i = 1:length(testYears)

    testYear = testYears(i);

    warmupStart = datetime(testYear - warmupYears, 1, 1);
    testStart   = datetime(testYear, 1, 1);

    if testYear == 2026
        testEnd = finalEndDate;
    else
        testEnd = datetime(testYear, 12, 31);
    end

    params.startDate = warmupStart;
    params.endDate   = testEnd;

    spyRegimeParams.startDate = warmupStart;
    spyRegimeParams.endDate   = testEnd;

    [results, ~] = runKalmanTrendModel_partialExposure(filename, params);
    [spyRegimeResults, ~] = runKalmanTrendModel_partialExposure(spyRegimeFile, spyRegimeParams);

    spyRiskOnFull = alignRegimePosition(results.Date, spyRegimeResults.Date, spyRegimeResults.Position);

    % Compute regime-filtered returns on the full warmup-to-testEnd vector first,
    % then evaluate only the test year inside summarizeBacktestPeriod.
    % This avoids resetting the regime branch at the year boundary.
    selectedExposureFull = getSelectedExposureFromVectors(results.Position, results.Exposure, selectedStrategyForTicker);
    regimeScaleFull = regimeRiskOffScale + (1 - regimeRiskOffScale) * spyRiskOnFull;
    regimeExposureFull = selectedExposureFull .* regimeScaleFull;
    regimeReturnNetFull = computeExposureReturnNet(results.DailyReturn, regimeExposureFull, params.transactionCost);

    yearSummary = summarizeBacktestPeriod(results, testStart, testEnd, selectedStrategyForTicker, ...
        spyRiskOnFull, regimeScaleFull, regimeExposureFull, regimeReturnNetFull);

    newRow = table( ...
        ticker, selectedStrategyForTicker, testYear, warmupStart, testStart, testEnd, ...
        params.q_jerk, params.r_meas, params.sellConfirmDays, params.buyConfirmDays, regimeRiskOffScale, ...
        100*yearSummary.buyHoldTotalReturn, 100*yearSummary.baselineTotalReturn, ...
        100*yearSummary.exposureTotalReturn, 100*yearSummary.selectedTotalReturn, 100*yearSummary.regimeFilteredTotalReturn, ...
        100*yearSummary.buyHoldMaxDrawdown, 100*yearSummary.baselineMaxDrawdown, ...
        100*yearSummary.exposureMaxDrawdown, 100*yearSummary.selectedMaxDrawdown, 100*yearSummary.regimeFilteredMaxDrawdown, ...
        yearSummary.buyHoldSharpeApprox, yearSummary.baselineSharpeApprox, ...
        yearSummary.exposureSharpeApprox, yearSummary.selectedSharpeApprox, yearSummary.regimeFilteredSharpeApprox, ...
        yearSummary.buyHoldBuyCount, yearSummary.baselineBuyCount, yearSummary.exposureBuyCount, ...
        yearSummary.selectedBuyCount, yearSummary.regimeFilteredBuyCount, ...
        yearSummary.buyHoldSellCount, yearSummary.baselineSellCount, yearSummary.exposureSellCount, ...
        yearSummary.selectedSellCount, yearSummary.regimeFilteredSellCount, ...
        yearSummary.buyHoldTradeCount, yearSummary.baselineTradeCount, yearSummary.exposureTradeCount, ...
        yearSummary.selectedTradeCount, yearSummary.regimeFilteredTradeCount, ...
        100*yearSummary.buyHoldTimeInMarket, 100*yearSummary.baselineTimeInMarket, ...
        100*yearSummary.exposureTimeInMarket, 100*yearSummary.selectedTimeInMarket, 100*yearSummary.regimeFilteredTimeInMarket, ...
        100*yearSummary.exposureAverage, 100*yearSummary.selectedAverageExposure, 100*yearSummary.regimeFilteredAverageExposure, ...
        yearSummary.exposureTurnoverTotal, yearSummary.regimeFilteredTurnoverTotal, ...
        yearSummary.exposureTargetAdjustmentCount, yearSummary.exposureHysteresisDelayCount, ...
        yearSummary.maxSellPressure, yearSummary.avgSellPressureWhileLong, 100*yearSummary.spyRegimeRiskOn, 100*yearSummary.averageRegimeScale, ...
        100*yearSummary.buyHoldExcessReturn, 100*yearSummary.baselineExcessReturn, ...
        100*yearSummary.exposureExcessReturn, 100*yearSummary.selectedExcessReturn, 100*yearSummary.regimeFilteredExcessReturn, ...
        100*yearSummary.buyHoldDrawdownImprovement, 100*yearSummary.baselineDrawdownImprovement, ...
        100*yearSummary.exposureDrawdownImprovement, 100*yearSummary.selectedDrawdownImprovement, 100*yearSummary.regimeFilteredDrawdownImprovement, ...
        yearSummary.buyHoldSharpeImprovement, yearSummary.baselineSharpeImprovement, ...
        yearSummary.exposureSharpeImprovement, yearSummary.selectedSharpeImprovement, yearSummary.regimeFilteredSharpeImprovement, ...
        100*yearSummary.regimeFilteredVsSelectedReturn, ...
        100*yearSummary.regimeFilteredVsSelectedDrawdownImprovement, ...
        yearSummary.regimeFilteredVsSelectedSharpeImprovement, ...
        'VariableNames', [ ...
        "Ticker", "SelectedStrategy", "TestYear", "WarmupStart", "TestStart", "TestEnd", ...
        "q_jerk", "r_meas", "SellConfirmDays", "BuyConfirmDays", "RegimeRiskOffScale", ...
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
        "BuyHoldDrawdownImprovementPct", "BaselineDrawdownImprovementPct", "ExposureDrawdownImprovementPct", ...
        "SelectedDrawdownImprovementPct", "RegimeFilteredDrawdownImprovementPct", ...
        "BuyHoldSharpeImprovement", "BaselineSharpeImprovement", "ExposureSharpeImprovement", ...
        "SelectedSharpeImprovement", "RegimeFilteredSharpeImprovement", ...
        "RegimeFilteredVsSelectedReturnPct", "RegimeFilteredVsSelectedDrawdownImprovementPct", "RegimeFilteredVsSelectedSharpeImprovement"]);

    walkForwardSummary = [walkForwardSummary; newRow];
end

%% ---------------- Display and Save Results ----------------
disp(walkForwardSummary);

walkforwardDir = fullfile(scriptDir, "walkforward");
tickerOutDir = fullfile(walkforwardDir, ticker);

if ~isfolder(walkforwardDir)
    mkdir(walkforwardDir);
end

if ~isfolder(tickerOutDir)
    mkdir(tickerOutDir);
end

outFile = fullfile(tickerOutDir, ...
    "wf_regime_" + ticker + "_" + jerk + "_" + meas + "_" + selldays + "_" + buydays + ".xlsx");

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

missingRegimeColumns = setdiff(requiredRegimeColumns, string(walkForwardSummary.Properties.VariableNames));

if ~isempty(missingRegimeColumns)
    error("Missing expected regime-filter output columns: %s", strjoin(missingRegimeColumns, ", "));
end

fprintf("\nConfirmed regime-filter walk-forward output columns are present.\n");

% Force overwrite so an older workbook does not hide the new columns.
if isfile(outFile)
    delete(outFile);
end

writetable(walkForwardSummary, outFile);

fprintf("\nRegime-filtered walk-forward summary saved to: %s\n", outFile);

%% ---------------- Local Helper Functions ----------------
function periodSummary = summarizeBacktestPeriod(results, startDate, endDate, selectedStrategy, spyRiskOnFull, regimeScaleFull, regimeExposureFull, regimeReturnNetFull)

    mask = results.Date >= startDate & results.Date <= endDate;

    if sum(mask) < 5
        error("Not enough data points in selected evaluation period.");
    end

    dailyReturn = results.DailyReturn(mask);
    baselineReturnNet = results.StrategyReturnNet(mask);
    exposureReturnNet = results.ExposureReturnNet(mask);

    position = results.Position(mask);
    action = results.Action(mask);
    exposure = results.Exposure(mask);
    spyRiskOn = spyRiskOnFull(mask);
    regimeScale = regimeScaleFull(mask);
    regimeExposure = regimeExposureFull(mask);
    regimeReturnNet = regimeReturnNetFull(mask);

    if ismember("SellPressure", results.Properties.VariableNames)
        sellPressure = results.SellPressure(mask);
    else
        sellPressure = zeros(sum(mask),1);
    end

    if ismember("TargetExposure", results.Properties.VariableNames)
        targetExposure = results.TargetExposure(mask);
    else
        targetExposure = exposure;
    end

    buyHoldEquity = cumprod(1 + dailyReturn);
    baselineEquity = cumprod(1 + baselineReturnNet);
    exposureEquity = cumprod(1 + exposureReturnNet);

    buyHoldRunningMax = cummax(buyHoldEquity);
    baselineRunningMax = cummax(baselineEquity);
    exposureRunningMax = cummax(exposureEquity);

    buyHoldDrawdown = buyHoldEquity ./ buyHoldRunningMax - 1;
    baselineDrawdown = baselineEquity ./ baselineRunningMax - 1;
    exposureDrawdown = exposureEquity ./ exposureRunningMax - 1;

    buyHoldTotalReturn = buyHoldEquity(end) - 1;
    baselineTotalReturn = baselineEquity(end) - 1;
    exposureTotalReturn = exposureEquity(end) - 1;

    buyHoldMaxDrawdown = min(buyHoldDrawdown);
    baselineMaxDrawdown = min(baselineDrawdown);
    exposureMaxDrawdown = min(exposureDrawdown);

    buyHoldSharpe = safeSharpe(dailyReturn);
    baselineSharpe = safeSharpe(baselineReturnNet);
    exposureSharpe = safeSharpe(exposureReturnNet);

    regime = summarizePrecomputedExposureBranch(regimeReturnNet, regimeExposure);

    periodSummary = struct();

    periodSummary.buyHoldTotalReturn = buyHoldTotalReturn;
    periodSummary.baselineTotalReturn = baselineTotalReturn;
    periodSummary.exposureTotalReturn = exposureTotalReturn;

    periodSummary.buyHoldMaxDrawdown = buyHoldMaxDrawdown;
    periodSummary.baselineMaxDrawdown = baselineMaxDrawdown;
    periodSummary.exposureMaxDrawdown = exposureMaxDrawdown;

    periodSummary.buyHoldSharpeApprox = buyHoldSharpe;
    periodSummary.baselineSharpeApprox = baselineSharpe;
    periodSummary.exposureSharpeApprox = exposureSharpe;

    periodSummary.buyHoldBuyCount = 1;
    periodSummary.buyHoldSellCount = 0;
    periodSummary.buyHoldTradeCount = 0;
    periodSummary.buyHoldTimeInMarket = 1;

    periodSummary.baselineBuyCount = sum(action == "Buy");
    periodSummary.baselineSellCount = sum(action == "Sell");
    periodSummary.baselineTradeCount = periodSummary.baselineBuyCount + periodSummary.baselineSellCount;
    periodSummary.baselineTimeInMarket = mean(position);

    periodSummary.exposureBuyCount = sum(exposure(1:end-1) == 0 & exposure(2:end) > 0);
    periodSummary.exposureSellCount = sum(exposure(1:end-1) > 0 & exposure(2:end) == 0);
    periodSummary.exposureTradeCount = sum(abs(diff(exposure)) > 0);
    periodSummary.exposureTimeInMarket = mean(exposure > 0);
    periodSummary.exposureAverage = mean(exposure);
    periodSummary.exposureTurnoverTotal = sum([0; abs(diff(exposure))]);

    periodSummary.exposureTargetAdjustmentCount = sum(abs(diff(targetExposure)) > 0);
    periodSummary.exposureHysteresisDelayCount = sum(abs(targetExposure - exposure) > 0);
    periodSummary.maxSellPressure = max(sellPressure);

    if any(position == 1)
        periodSummary.avgSellPressureWhileLong = mean(sellPressure(position == 1), "omitnan");
    else
        periodSummary.avgSellPressureWhileLong = NaN;
    end

    periodSummary.buyHoldExcessReturn = 0;
    periodSummary.baselineExcessReturn = baselineTotalReturn - buyHoldTotalReturn;
    periodSummary.exposureExcessReturn = exposureTotalReturn - buyHoldTotalReturn;

    periodSummary.buyHoldDrawdownImprovement = 0;
    periodSummary.baselineDrawdownImprovement = baselineMaxDrawdown - buyHoldMaxDrawdown;
    periodSummary.exposureDrawdownImprovement = exposureMaxDrawdown - buyHoldMaxDrawdown;

    periodSummary.buyHoldSharpeImprovement = 0;
    periodSummary.baselineSharpeImprovement = baselineSharpe - buyHoldSharpe;
    periodSummary.exposureSharpeImprovement = exposureSharpe - buyHoldSharpe;

    if selectedStrategy == "Exposure"
        periodSummary.selectedTotalReturn = exposureTotalReturn;
        periodSummary.selectedMaxDrawdown = exposureMaxDrawdown;
        periodSummary.selectedSharpeApprox = exposureSharpe;
        periodSummary.selectedBuyCount = periodSummary.exposureBuyCount;
        periodSummary.selectedSellCount = periodSummary.exposureSellCount;
        periodSummary.selectedTradeCount = periodSummary.exposureTradeCount;
        periodSummary.selectedTimeInMarket = periodSummary.exposureTimeInMarket;
        periodSummary.selectedAverageExposure = periodSummary.exposureAverage;
        periodSummary.selectedExcessReturn = periodSummary.exposureExcessReturn;
        periodSummary.selectedDrawdownImprovement = periodSummary.exposureDrawdownImprovement;
        periodSummary.selectedSharpeImprovement = periodSummary.exposureSharpeImprovement;
    elseif selectedStrategy == "Baseline"
        periodSummary.selectedTotalReturn = baselineTotalReturn;
        periodSummary.selectedMaxDrawdown = baselineMaxDrawdown;
        periodSummary.selectedSharpeApprox = baselineSharpe;
        periodSummary.selectedBuyCount = periodSummary.baselineBuyCount;
        periodSummary.selectedSellCount = periodSummary.baselineSellCount;
        periodSummary.selectedTradeCount = periodSummary.baselineTradeCount;
        periodSummary.selectedTimeInMarket = periodSummary.baselineTimeInMarket;
        periodSummary.selectedAverageExposure = periodSummary.baselineTimeInMarket;
        periodSummary.selectedExcessReturn = periodSummary.baselineExcessReturn;
        periodSummary.selectedDrawdownImprovement = periodSummary.baselineDrawdownImprovement;
        periodSummary.selectedSharpeImprovement = periodSummary.baselineSharpeImprovement;
    else
        error("Unknown selectedStrategy. Use 'Baseline' or 'Exposure'.");
    end

    periodSummary.regimeFilteredTotalReturn = regime.totalReturn;
    periodSummary.regimeFilteredMaxDrawdown = regime.maxDrawdown;
    periodSummary.regimeFilteredSharpeApprox = regime.sharpe;

    periodSummary.regimeFilteredBuyCount = regime.buyCount;
    periodSummary.regimeFilteredSellCount = regime.sellCount;
    periodSummary.regimeFilteredTradeCount = regime.tradeCount;
    periodSummary.regimeFilteredTimeInMarket = regime.timeInMarket;
    periodSummary.regimeFilteredAverageExposure = regime.averageExposure;
    periodSummary.regimeFilteredTurnoverTotal = regime.turnoverTotal;

    periodSummary.regimeFilteredExcessReturn = regime.totalReturn - buyHoldTotalReturn;
    periodSummary.regimeFilteredDrawdownImprovement = regime.maxDrawdown - buyHoldMaxDrawdown;
    periodSummary.regimeFilteredSharpeImprovement = regime.sharpe - buyHoldSharpe;

    periodSummary.regimeFilteredVsSelectedReturn = regime.totalReturn - periodSummary.selectedTotalReturn;
    periodSummary.regimeFilteredVsSelectedDrawdownImprovement = regime.maxDrawdown - periodSummary.selectedMaxDrawdown;
    periodSummary.regimeFilteredVsSelectedSharpeImprovement = regime.sharpe - periodSummary.selectedSharpeApprox;

    periodSummary.spyRegimeRiskOn = mean(spyRiskOn > 0);
    periodSummary.averageRegimeScale = mean(regimeScale);
end

function selectedExposure = getSelectedExposureFromVectors(position, exposure, selectedStrategy)

    if selectedStrategy == "Exposure"
        selectedExposure = exposure;
    elseif selectedStrategy == "Baseline"
        selectedExposure = position;
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

function returnNet = computeExposureReturnNet(dailyReturn, exposure, transactionCost)

    exposure = double(exposure(:));
    dailyReturn = dailyReturn(:);

    grossReturn = [0; exposure(1:end-1) .* dailyReturn(2:end)];
    turnover = [0; abs(diff(exposure))];

    returnNet = grossReturn - transactionCost * turnover;
end

function branch = summarizePrecomputedExposureBranch(returnNet, exposure)

    exposure = double(exposure(:));
    returnNet = returnNet(:);

    branchEquity = cumprod(1 + returnNet);

    branchRunningMax = cummax(branchEquity);
    branchDrawdown = branchEquity ./ branchRunningMax - 1;

    branch = struct();
    branch.totalReturn = branchEquity(end) - 1;
    branch.maxDrawdown = min(branchDrawdown);
    branch.sharpe = safeSharpe(returnNet);
    branch.buyCount = sum(exposure(1:end-1) == 0 & exposure(2:end) > 0);
    branch.sellCount = sum(exposure(1:end-1) > 0 & exposure(2:end) == 0);
    branch.tradeCount = sum(abs(diff(exposure)) > 0);
    branch.timeInMarket = mean(exposure > 0);
    branch.averageExposure = mean(exposure);
    branch.turnoverTotal = sum([0; abs(diff(exposure))]);
end

function sharpe = safeSharpe(returns)

    s = std(returns);

    if s == 0 || isnan(s)
        sharpe = NaN;
    else
        sharpe = sqrt(252) * mean(returns) / s;
    end
end
