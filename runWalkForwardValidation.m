%% runWalkForwardValidation.m
% Walk-forward validation for Kalman trend strategy.
%
% This uses the current fixed baseline parameters and evaluates
% performance year by year.

clear; clc; close all;

%% ---------------- User Inputs ----------------
ticker = "SPYG";
filename = "data/" + ticker + ".csv";

%% ---------------- Fixed Baseline Parameters ----------------
params = struct();

params.q_jerk = 1e-7;
params.r_meas = 5e-4;

params.buyConfirmDays = 5;
params.sellConfirmDays = 8;

params.transactionCost = 0.001;

params.makePlots = true;
params.printSummary = false;

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

    % Run model from warmup start through test end
    params.startDate = warmupStart;
    params.endDate   = testEnd;

    [results, summary] = runKalmanTrendModel_partialExposure(filename, params);

    % Evaluate only the test period
    yearSummary = summarizeBacktestPeriod(results, testStart, testEnd);

    newRow = table( ...
        ticker, ...
        testYear, ...
        warmupStart, ...
        testStart, ...
        testEnd, ...
        100*yearSummary.strategyTotalReturn, ...
        100*yearSummary.buyHoldTotalReturn, ...
        100*yearSummary.strategyMaxDrawdown, ...
        100*yearSummary.buyHoldMaxDrawdown, ...
        yearSummary.strategySharpeApprox, ...
        yearSummary.buyHoldSharpeApprox, ...
        yearSummary.buyCount, ...
        yearSummary.sellCount, ...
        yearSummary.tradeCount, ...
        100*yearSummary.timeInMarket, ...
        'VariableNames', [ ...
        "Ticker", ...
        "TestYear", ...
        "WarmupStart", ...
        "TestStart", ...
        "TestEnd", ...
        "StrategyReturnPct", ...
        "BuyHoldReturnPct", ...
        "StrategyMaxDrawdownPct", ...
        "BuyHoldMaxDrawdownPct", ...
        "StrategySharpe", ...
        "BuyHoldSharpe", ...
        "BuyCount", ...
        "SellCount", ...
        "TradeCount", ...
        "TimeInMarketPct"]);

    walkForwardSummary = [walkForwardSummary; newRow];

end

%% ---------------- Derived Metrics ----------------
walkForwardSummary.ExcessReturnPct = ...
    walkForwardSummary.StrategyReturnPct - walkForwardSummary.BuyHoldReturnPct;

walkForwardSummary.DrawdownImprovementPct = ...
    walkForwardSummary.StrategyMaxDrawdownPct - walkForwardSummary.BuyHoldMaxDrawdownPct;

walkForwardSummary.SharpeImprovement = ...
    walkForwardSummary.StrategySharpe - walkForwardSummary.BuyHoldSharpe;

%% ---------------- Display and Save ----------------
disp(walkForwardSummary);

if ~isfolder("results")
    mkdir("results");
end

outFile = "results/walkforward/walk_forward_" + ticker + ".xlsx";
writetable(walkForwardSummary, outFile);

fprintf("\nWalk-forward summary saved to: %s\n", outFile);

%% ---------------- Local Helper Function ----------------
function periodSummary = summarizeBacktestPeriod(results, startDate, endDate)

    mask = results.Date >= startDate & results.Date <= endDate;

    if sum(mask) < 5
        error("Not enough data points in selected evaluation period.");
    end

    dailyReturn = results.DailyReturn(mask);
    strategyReturnNet = results.StrategyReturnNet(mask);
    position = results.Position(mask);
    action = results.Action(mask);

    buyHoldEquity = cumprod(1 + dailyReturn);
    strategyEquity = cumprod(1 + strategyReturnNet);

    strategyRunningMax = cummax(strategyEquity);
    strategyDrawdown = strategyEquity ./ strategyRunningMax - 1;

    buyHoldRunningMax = cummax(buyHoldEquity);
    buyHoldDrawdown = buyHoldEquity ./ buyHoldRunningMax - 1;

    periodSummary = struct();

    periodSummary.strategyTotalReturn = strategyEquity(end) - 1;
    periodSummary.buyHoldTotalReturn = buyHoldEquity(end) - 1;

    periodSummary.strategyMaxDrawdown = min(strategyDrawdown);
    periodSummary.buyHoldMaxDrawdown = min(buyHoldDrawdown);

    periodSummary.strategySharpeApprox = safeSharpe(strategyReturnNet);
    periodSummary.buyHoldSharpeApprox = safeSharpe(dailyReturn);

    periodSummary.buyCount = sum(action == "Buy");
    periodSummary.sellCount = sum(action == "Sell");
    periodSummary.tradeCount = periodSummary.buyCount + periodSummary.sellCount;

    periodSummary.timeInMarket = mean(position);

end

function sharpe = safeSharpe(returns)

    s = std(returns);

    if s == 0 || isnan(s)
        sharpe = NaN;
    else
        sharpe = sqrt(252) * mean(returns) / s;
    end

end