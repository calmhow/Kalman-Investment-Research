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
ticker = "QQQ";
filename = "data/" + ticker + ".csv";

%% ---------------- Fixed Baseline Parameters ----------------
params = struct();

params.q_jerk = 1e-7;
params.r_meas = 1e-3;

params.buyConfirmDays = 5;
params.sellConfirmDays = 8;

params.transactionCost = 0.001;

jerk=string(params.q_jerk);
meas=string(params.r_meas);
buydays=string(params.buyConfirmDays);
selldays=string(params.sellConfirmDays);

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
        100*yearSummary.buyHoldMaxDrawdown, ...
        100*yearSummary.baselineMaxDrawdown, ...
        100*yearSummary.exposureMaxDrawdown, ...
        yearSummary.buyHoldSharpeApprox, ...
        yearSummary.baselineSharpeApprox, ...
        yearSummary.exposureSharpeApprox, ...
        yearSummary.buyHoldBuyCount, ...
        yearSummary.baselineBuyCount, ...
        yearSummary.exposureBuyCount, ...
        yearSummary.buyHoldSellCount, ...
        yearSummary.baselineSellCount, ...
        yearSummary.exposureSellCount, ...
        yearSummary.buyHoldTradeCount, ...
        yearSummary.baselineTradeCount, ...
        yearSummary.exposureTradeCount, ...
        100*yearSummary.buyHoldTimeInMarket, ...
        100*yearSummary.baselineTimeInMarket, ...
        100*yearSummary.exposureTimeInMarket, ...
        100*yearSummary.exposureAverage, ...
        yearSummary.exposureTurnoverTotal, ...
        yearSummary.exposureTargetAdjustmentCount, ...
        yearSummary.exposureHysteresisDelayCount, ...
        yearSummary.maxSellPressure, ...
        yearSummary.avgSellPressureWhileLong, ...
        100*yearSummary.buyHoldExcessReturn, ...
        100*yearSummary.baselineExcessReturn, ...
        100*yearSummary.exposureExcessReturn, ...
        100*yearSummary.buyHoldDrawdownImprovement, ...
        100*yearSummary.baselineDrawdownImprovement, ...
        100*yearSummary.exposureDrawdownImprovement, ...
        yearSummary.buyHoldSharpeImprovement, ...
        yearSummary.baselineSharpeImprovement, ...
        yearSummary.exposureSharpeImprovement, ...
        'VariableNames', [ ...
        "Ticker", ...
        "TestYear", ...
        "WarmupStart", ...
        "TestStart", ...
        "TestEnd", ...
        "BuyHoldReturnPct", ...
        "BaselineReturnPct", ...
        "ExposureReturnPct", ...
        "BuyHoldMaxDrawdownPct", ...
        "BaselineMaxDrawdownPct", ...
        "ExposureMaxDrawdownPct", ...
        "BuyHoldSharpe", ...
        "BaselineSharpe", ...
        "ExposureSharpe", ...
        "BuyHoldBuyCount", ...
        "BaselineBuyCount", ...
        "ExposureBuyCount", ...
        "BuyHoldSellCount", ...
        "BaselineSellCount", ...
        "ExposureSellCount", ...
        "BuyHoldTradeCount", ...
        "BaselineTradeCount", ...
        "ExposureTradeCount", ...
        "BuyHoldTimeInMarketPct", ...
        "BaselineTimeInMarketPct", ...
        "ExposureTimeInMarketPct", ...
        "ExposureAveragePct", ...
        "ExposureTurnoverTotal", ...
        "ExposureTargetAdjustmentCount", ...
        "ExposureHysteresisDelayCount", ...
        "MaxSellPressure", ...
        "AvgSellPressureWhileLong", ...
        "BuyHoldExcessReturnPct", ...
        "BaselineExcessReturnPct", ...
        "ExposureExcessReturnPct", ...
        "BuyHoldDrawdownImprovementPct", ...
        "BaselineDrawdownImprovementPct", ...
        "ExposureDrawdownImprovementPct", ...
        "BuyHoldSharpeImprovement", ...
        "BaselineSharpeImprovement", ...
        "ExposureSharpeImprovement"]);

    walkForwardSummary = [walkForwardSummary; newRow];

end

%% ---------------- Display and Save ----------------
disp(walkForwardSummary);

if ~isfolder("results")
    mkdir("results");
end

if ~isfolder("results/walkforward")
    mkdir("results/walkforward");
end

tickerOutDir = "results/walkforward/" + ticker;
if ~isfolder(tickerOutDir)
    mkdir(tickerOutDir);
end

outFile = tickerOutDir + "/wf_" + ticker + "_"+ jerk +"_" + meas + "_"+ selldays +"_" + buydays + ".xlsx";
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

end

function sharpe = safeSharpe(returns)

    s = std(returns);

    if s == 0 || isnan(s)
        sharpe = NaN;
    else
        sharpe = sqrt(252) * mean(returns) / s;
    end

end
