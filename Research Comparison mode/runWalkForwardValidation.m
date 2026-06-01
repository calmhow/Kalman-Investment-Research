%% runWalkForwardValidation.m
% Walk-forward validation for Kalman trend strategy.
%
% This script compares:
%   1. Buy-and-hold
%   2. Baseline 0/1 Kalman strategy
%   3. Partial-exposure Kalman strategy
%
% The model is run from warmupStart through testEnd, but metrics are
% evaluated only over the selected test year.

clear; clc; close all;

%% ---------------- User Inputs ----------------
ticker = "SPY";

% Path setup based on this script's location.
% Assumes this script is inside:
%   Research Comparison mode/
%
% and the data folder is one level above:
%   ../data/
scriptDir = string(fileparts(mfilename('fullpath')));
projectRoot = string(fileparts(scriptDir));

dataDir = fullfile(projectRoot, "data");
filename = fullfile(dataDir, ticker + ".csv");

%% ---------------- Fixed Baseline Parameters ----------------
params = struct();

params.q_jerk = 1e-7;
params.r_meas = 5e-4;

params.buyConfirmDays = 5;
params.sellConfirmDays = 8;

params.transactionCost = 0.001;

jerk = sprintf("%.0e", params.q_jerk);
meas = sprintf("%.0e", params.r_meas);
buydays = sprintf("%d", params.buyConfirmDays);
selldays = sprintf("%d", params.sellConfirmDays);

params.makePlots = false;
params.showStatePlots = false;   % price CI, trend CI, acceleration CI
params.printSummary = false;

params.runPartialExposure = true;

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

    [results, summary] = runKalmanTrendModel_partialExposure(filename, params); 

    yearSummary = summarizeBacktestPeriod(results, testStart, testEnd);

    newRow = table( ...
        ticker, ...
        testYear, ...
        warmupStart, ...
        testStart, ...
        testEnd, ...
        100*yearSummary.buyHoldTotalReturn, ...
        100*yearSummary.baselineTotalReturn, ...
        100*yearSummary.exposureTotalReturn, ...
        yearSummary.selectedStrategy, ...
        100*yearSummary.selectedTotalReturn, ...
        100*yearSummary.buyHoldMaxDrawdown, ...
        100*yearSummary.baselineMaxDrawdown, ...
        100*yearSummary.exposureMaxDrawdown, ...
        100*yearSummary.selectedMaxDrawdown, ...
        yearSummary.buyHoldSharpeApprox, ...
        yearSummary.baselineSharpeApprox, ...
        yearSummary.exposureSharpeApprox, ...
        yearSummary.selectedSharpeApprox, ...
        yearSummary.buyHoldBuyCount, ...
        yearSummary.baselineBuyCount, ...
        yearSummary.exposureBuyCount, ...
        yearSummary.selectedBuyCount, ...
        yearSummary.buyHoldSellCount, ...
        yearSummary.baselineSellCount, ...
        yearSummary.exposureSellCount, ...
        yearSummary.selectedSellCount, ...
        yearSummary.buyHoldTradeCount, ...
        yearSummary.baselineTradeCount, ...
        yearSummary.exposureTradeCount, ...
        yearSummary.selectedTradeCount, ...
        100*yearSummary.buyHoldTimeInMarket, ...
        100*yearSummary.baselineTimeInMarket, ...
        100*yearSummary.exposureTimeInMarket, ...
        100*yearSummary.selectedTimeInMarket, ...
        100*yearSummary.exposureAverage, ...
        100*yearSummary.selectedAverageExposure, ...
        yearSummary.exposureTurnoverTotal, ...
        yearSummary.exposureTargetAdjustmentCount, ...
        yearSummary.exposureHysteresisDelayCount, ...
        yearSummary.maxSellPressure, ...
        yearSummary.avgSellPressureWhileLong, ...
        100*yearSummary.buyHoldExcessReturn, ...
        100*yearSummary.baselineExcessReturn, ...
        100*yearSummary.exposureExcessReturn, ...
        100*yearSummary.selectedExcessReturn, ...
        100*yearSummary.buyHoldDrawdownImprovement, ...
        100*yearSummary.baselineDrawdownImprovement, ...
        100*yearSummary.exposureDrawdownImprovement, ...
        100*yearSummary.selectedDrawdownImprovement, ...
        yearSummary.buyHoldSharpeImprovement, ...
        yearSummary.baselineSharpeImprovement, ...
        yearSummary.exposureSharpeImprovement, ...
        yearSummary.selectedSharpeImprovement, ...
        'VariableNames', [ ...
        "Ticker", ...
        "TestYear", ...
        "WarmupStart", ...
        "TestStart", ...
        "TestEnd", ...
        "BuyHoldReturnPct", ...
        "BaselineReturnPct", ...
        "ExposureReturnPct", ...
        "SelectedStrategy", ...
        "SelectedReturnPct", ...
        "BuyHoldMaxDrawdownPct", ...
        "BaselineMaxDrawdownPct", ...
        "ExposureMaxDrawdownPct", ...
        "SelectedMaxDrawdownPct", ...
        "BuyHoldSharpe", ...
        "BaselineSharpe", ...
        "ExposureSharpe", ...
        "SelectedSharpe", ...
        "BuyHoldBuyCount", ...
        "BaselineBuyCount", ...
        "ExposureBuyCount", ...
        "SelectedBuyCount", ...
        "BuyHoldSellCount", ...
        "BaselineSellCount", ...
        "ExposureSellCount", ...
        "SelectedSellCount", ...
        "BuyHoldTradeCount", ...
        "BaselineTradeCount", ...
        "ExposureTradeCount", ...
        "SelectedTradeCount", ...
        "BuyHoldTimeInMarketPct", ...
        "BaselineTimeInMarketPct", ...
        "ExposureTimeInMarketPct", ...
        "SelectedTimeInMarketPct", ...
        "ExposureAveragePct", ...
        "SelectedAverageExposurePct", ...
        "ExposureTurnoverTotal", ...
        "ExposureTargetAdjustmentCount", ...
        "ExposureHysteresisDelayCount", ...
        "MaxSellPressure", ...
        "AvgSellPressureWhileLong", ...
        "BuyHoldExcessReturnPct", ...
        "BaselineExcessReturnPct", ...
        "ExposureExcessReturnPct", ...
        "SelectedExcessReturnPct", ...
        "BuyHoldDrawdownImprovementPct", ...
        "BaselineDrawdownImprovementPct", ...
        "ExposureDrawdownImprovementPct", ...
        "SelectedDrawdownImprovementPct", ...
        "BuyHoldSharpeImprovement", ...
        "BaselineSharpeImprovement", ...
        "ExposureSharpeImprovement", ...
        "SelectedSharpeImprovement"]);

    walkForwardSummary = [walkForwardSummary; newRow];

end

%% ---------------- Display and Save ----------------
disp(walkForwardSummary);

% Save results inside:
%   Research Comparison mode/results/walkforward/<ticker>/
resultsDir = fullfile(scriptDir, "results");
walkforwardDir = fullfile(resultsDir, "walkforward");
tickerOutDir = fullfile(walkforwardDir, ticker);

if ~isfolder(resultsDir)
    mkdir(resultsDir);
end

if ~isfolder(walkforwardDir)
    mkdir(walkforwardDir);
end

if ~isfolder(tickerOutDir)
    mkdir(tickerOutDir);
end

outFile = fullfile(tickerOutDir, ...
    "wf_" + ticker + "_" + jerk + "_" + meas + "_" + selldays + "_" + buydays + ".xlsx");

writetable(walkForwardSummary, outFile);

fprintf("\nWalk-forward summary saved to: %s\n", outFile);

%% ---------------- Local Helper Functions ----------------
function periodSummary = summarizeBacktestPeriod(results, startDate, endDate)

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

    % Optional exposure diagnostics from newer partial-exposure model versions.
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

    if ismember("ZeroSellPressureCounter", results.Properties.VariableNames)
        zeroSellPressureCounter = results.ZeroSellPressureCounter(mask); %#ok<NASGU>
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

    % Extra exposure diagnostics.
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

    %% ---------------- Selected Strategy Logic ----------------
    % Current research interpretation:
    %   SPY: baseline usually remains stronger.
    %   QQQ/SPYG: softened exposure is a candidate improvement.
    %
    % This selection is for reporting only and does not remove the full
    % buy-hold, baseline, or exposure metrics from the output.

    % The ticker-specific selected strategy rule can be added at the caller level.
    % This local function uses a metric-based selection rule.

    % Infer ticker from the outer script by checking whether the selected
    % period came from a growth-style ETF. This function does not receive
    % ticker directly, so the caller sets the selected strategy below.
    %
    % Default: choose exposure if it improves Sharpe and does not materially
    % hurt return; otherwise choose baseline.
    exposureReturnPenalty = exposureTotalReturn - baselineTotalReturn;
    exposureSharpeGain = exposureSharpe - baselineSharpe;
    exposureDrawdownGain = exposureMaxDrawdown - baselineMaxDrawdown;

    if exposureSharpeGain > 0 && exposureReturnPenalty > -0.01
        periodSummary.selectedStrategy = "Exposure";
    elseif exposureDrawdownGain > 0 && exposureReturnPenalty > -0.01
        periodSummary.selectedStrategy = "Exposure";
    else
        periodSummary.selectedStrategy = "Baseline";
    end

    if periodSummary.selectedStrategy == "Exposure"
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
    else
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
