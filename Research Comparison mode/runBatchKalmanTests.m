%% runBatchKalmanTests.m
% Batch runner for Kalman trend model across multiple tickers.
% data for any specific ticker must be included in the data folder

clear; clc; close all;

%% ---------------- Path Setup ----------------
% Assumes this script is inside:
%   Research Comparison mode/
%
% and the data folder is one level above:
%   ../data/
scriptDir = string(fileparts(mfilename('fullpath')));
projectRoot = string(fileparts(scriptDir));

dataDir = fullfile(projectRoot, "data");

%% ---------------- Shared Parameters ----------------
params = struct();

% Current shared ETF baseline % most optimal values as of 5/31/2026
params.q_jerk = 1e-7;
params.r_meas = 5e-4;

params.buyConfirmDays = 5;
params.sellConfirmDays = 8;

params.transactionCost = 0.001;

% Suppress plots and printed output during batch runs
params.makePlots = false;
params.printSummary = false;

%% ---------------- Tickers to Test ----------------
tickers = ["SPY", "QQQ", "SPYG", "MSFT", "NVDA"];

numTickers = length(tickers);

summaryRows = table();

%% ---------------- Run Batch Tests ----------------
 for i = 1:numTickers

    ticker = tickers(i);
    filename = fullfile(dataDir, ticker + ".csv");

    fprintf("Running %s...\n", ticker);

    [results, summary] = runKalmanTrendModel_partialExposure(filename, params);

    newRow = table( ...
        ticker, ...
        summary.startDate, ...
        summary.endDate, ...
        summary.q_jerk, ...
        summary.r_meas, ...
        summary.buyConfirmDays, ...
        summary.sellConfirmDays, ...
        summary.buyCount, ...
        summary.sellCount, ...
        summary.tradeCount, ...
        100*summary.timeInMarket, ...
        100*summary.strategyTotalReturn, ...
        100*summary.buyHoldTotalReturn, ...
        100*summary.strategyMaxDrawdown, ...
        100*summary.buyHoldMaxDrawdown, ...
        summary.strategySharpeApprox, ...
        summary.buyHoldSharpeApprox, ...
        'VariableNames', [ ...
        "Ticker", ...
        "StartDate", ...
        "EndDate", ...
        "q_jerk", ...
        "r_meas", ...
        "BuyConfirmDays", ...
        "SellConfirmDays", ...
        "BuyCount", ...
        "SellCount", ...
        "TradeCount", ...
        "TimeInMarketPct", ...
        "StrategyReturnPct", ...
        "BuyHoldReturnPct", ...
        "StrategyMaxDrawdownPct", ...
        "BuyHoldMaxDrawdownPct", ...
        "StrategySharpe", ...
        "BuyHoldSharpe"]);

    summaryRows = [summaryRows; newRow];

 end

%% ---------------- Derived Comparison Metrics ----------------
summaryRows.ExcessReturnPct = summaryRows.StrategyReturnPct - summaryRows.BuyHoldReturnPct;
summaryRows.DrawdownImprovementPct = summaryRows.StrategyMaxDrawdownPct - summaryRows.BuyHoldMaxDrawdownPct;
summaryRows.SharpeImprovement = summaryRows.StrategySharpe - summaryRows.BuyHoldSharpe;

%% ---------------- Display Summary ----------------
disp(summaryRows);

%% ---------------- Save Results ----------------
% Save results inside:
%   Research Comparison mode/results/batchruns/
resultsDir = fullfile(scriptDir, "results");
batchRunsDir = fullfile(resultsDir, "batchruns");

if ~isfolder(resultsDir)
    mkdir(resultsDir);
end

if ~isfolder(batchRunsDir)
    mkdir(batchRunsDir);
end

outFile = fullfile(batchRunsDir, "batch_kalman_summary.xlsx");
writetable(summaryRows, outFile);

fprintf("\nBatch summary saved to: %s\n", outFile);
