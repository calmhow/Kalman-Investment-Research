function [results, summary, figs] = runKalmanTrendModel_partialExposure(filename, params)
% runKalmanTrendModel_partialExposure
% Reusable Kalman trend model with baseline 0/1 strategy plus a separate
% partial-exposure comparison strategy.
%
% Required input:
%   filename : CSV file path, for example "data/SPY.csv"
%
% Optional input:
%   params : struct of optional tuning/settings values
%
% Example:
%   [results, summary, figs] = runKalmanTrendModel_partialExposure("data/SPY.csv");
%
% Quiet example:
%   params = struct();
%   params.makePlots = false;
%   params.printSummary = false;
%   [results, summary] = runKalmanTrendModel_partialExposure("data/SPY.csv", params);
%
% Optional plot control:
%   params.makePlots = true/false;       % master plot switch
%   params.showStatePlots = true/false;  % price CI, trend CI, acceleration CI
%
% Baseline strategy:
%   position = 0 or 1
%
% Partial-exposure strategy:
%   exposure scales the baseline position rather than replacing it.
%   Current version uses late-stage sell-pressure de-risking.

    %% ---------------- Default Parameters ----------------
    if nargin < 2 || isempty(params)
        params = struct();
    end

    params = setDefault(params, "dt", 1);
    params = setDefault(params, "q_jerk", 1e-7);
    params = setDefault(params, "r_meas", 5e-4);
    params = setDefault(params, "zCI", 1.64485);              % 90% two-sided CI
    params = setDefault(params, "buyConfirmDays", 5);
    params = setDefault(params, "sellConfirmDays", 8);
    params = setDefault(params, "transactionCost", 0.001);    % 0.1% per full-turnover trade
    params = setDefault(params, "makePlots", true);
    params = setDefault(params, "showStatePlots", false);     % price CI, trend CI, acceleration CI
    params = setDefault(params, "printSummary", true);
    params = setDefault(params, "startDate", []);
    params = setDefault(params, "endDate", []);

    % Parallel model-comparison branch.
    % Baseline 0/1 position logic is left unchanged.
    % Partial exposure is calculated separately for comparison.
    %
    % Late-stage sell-pressure de-risking:
    %   The baseline 0/1 model decides whether the strategy is long or cash.
    %   Exposure stays fully long during weak/early sell pressure.
    %   Exposure only scales down when the baseline sell condition is close
    %   to confirmation.
    params = setDefault(params, "runPartialExposure", true);
    params = setDefault(params, "exposureNoSellPressure", 1.00);       % baseline long, no active sell pressure
    params = setDefault(params, "exposureLowSellPressure", 1.00);      % early sell pressure; stay fully invested
    params = setDefault(params, "exposureMediumSellPressure", 0.75);   % late-stage sell pressure
    params = setDefault(params, "exposureHighSellPressure", 0.50);     % very late-stage sell pressure, but not full exit yet
    params = setDefault(params, "exposureCash", 0.00);                % baseline cash
    params = setDefault(params, "sellPressureLowThreshold", 0.50);
    params = setDefault(params, "sellPressureHighThreshold", 0.75);

    dt = params.dt;
    q_jerk = params.q_jerk;
    r_meas = params.r_meas;
    zCI = params.zCI;

    % Ticker label for plot titles
    [~, tickerLabel, ~] = fileparts(char(filename));
    tickerLabel = upper(string(tickerLabel));

    %% ---------------- Load Data ----------------
    T = readtable(filename);

    if ismember("Date", T.Properties.VariableNames)
        dates = T.Date;

        if ~isdatetime(dates)
            try
                dates = datetime(dates, "InputFormat", "yyyy-MM-dd");
            catch
                dates = datetime(dates);
            end
        end
    else
        dates = (1:height(T))';
    end

    if ismember("AdjClose", T.Properties.VariableNames)
        price = T.AdjClose;
    elseif ismember("Adj_Close", T.Properties.VariableNames)
        price = T.Adj_Close;
    elseif ismember("AdjustedClose", T.Properties.VariableNames)
        price = T.AdjustedClose;
    elseif ismember("Close", T.Properties.VariableNames)
        price = T.Close;
    elseif ismember("close", T.Properties.VariableNames)
        price = T.close;
    else
        error("CSV must contain AdjClose, Adj_Close, AdjustedClose, Close, or close.");
    end

    valid = ~isnan(price) & price > 0;
    price = price(valid);
    dates = dates(valid);

    [dates, sortIdx] = sort(dates);
    price = price(sortIdx);

    if ~isempty(params.startDate)
        startDate = datetime(params.startDate);
        keep = dates >= startDate;
        dates = dates(keep);
        price = price(keep);
    end

    if ~isempty(params.endDate)
        endDate = datetime(params.endDate);
        keep = dates <= endDate;
        dates = dates(keep);
        price = price(keep);
    end

    z = log(price);
    N = length(z);

    if N < 10
        error("Not enough valid price data after cleaning/filtering.");
    end

    %% ---------------- Model Matrices ----------------
    F = [1, dt, 0.5*dt^2;
         0, 1,  dt;
         0, 0,  1];

    H = [1, 0, 0];

    G = [dt^3/6;
         dt^2/2;
         dt];

    Q = q_jerk * (G * G');
    R = r_meas;

    n = 3;

    %% ---------------- Initialization ----------------
    xhat = zeros(n, N);
    Pstore = zeros(n, n, N);

    xhat(:,1) = [z(1); 0; 0];

    P = diag([1e-4, 1e-5, 1e-6]);
    Pstore(:,:,1) = P;

    %% ---------------- Kalman Filter Loop ----------------
    for k = 2:N
        x_pred = F * xhat(:,k-1);
        P_pred = F * P * F' + Q;

        innovation = z(k) - H * x_pred;
        S = H * P_pred * H' + R;

        K = P_pred * H' / S;

        xhat(:,k) = x_pred + K * innovation;

        I = eye(n);
        P = (I - K*H) * P_pred * (I - K*H)' + K * R * K';

        Pstore(:,:,k) = P;
    end

    %% ---------------- Extract Estimates ----------------
    logPrice_est = xhat(1,:)';
    trend_est    = xhat(2,:)';
    accel_est    = xhat(3,:)';

    price_est = exp(logPrice_est);

    sigma_logPrice = squeeze(sqrt(Pstore(1,1,:)));
    sigma_trend    = squeeze(sqrt(Pstore(2,2,:)));
    sigma_accel    = squeeze(sqrt(Pstore(3,3,:)));

    logPrice_low  = logPrice_est - zCI*sigma_logPrice;
    logPrice_high = logPrice_est + zCI*sigma_logPrice;

    price_low  = exp(logPrice_low);
    price_high = exp(logPrice_high);

    trend_low  = trend_est - zCI*sigma_trend;
    trend_high = trend_est + zCI*sigma_trend;

    accel_low  = accel_est - zCI*sigma_accel;
    accel_high = accel_est + zCI*sigma_accel;

    %% ---------------- Baseline Signal Logic ----------------
    position = zeros(N,1);

    buySignal  = trend_est > 0;
    sellSignal = trend_high < 0;

    buyCounter = 0;
    sellCounter = 0;

    % Store how close the baseline model is to a confirmed sell.
    % These histories are used only by the partial-exposure overlay.
    buyCounterHistory = zeros(N,1);
    sellCounterHistory = zeros(N,1);
    sellPressure = zeros(N,1);

    for k = 2:N
        position(k) = position(k-1);

        if position(k-1) == 0
            if buySignal(k)
                buyCounter = buyCounter + 1;
            else
                buyCounter = 0;
            end

            sellCounter = 0;

            if buyCounter >= params.buyConfirmDays
                position(k) = 1;
                buyCounter = 0;
            end

        elseif position(k-1) == 1
            if sellSignal(k)
                sellCounter = sellCounter + 1;
            else
                sellCounter = 0;
            end

            buyCounter = 0;

            if sellCounter >= params.sellConfirmDays
                position(k) = 0;

                % Record full sell pressure on the exit day, then reset.
                sellCounterHistory(k) = params.sellConfirmDays;
                sellPressure(k) = 1.0;

                sellCounter = 0;
            end
        end

        buyCounterHistory(k) = buyCounter;

        % If we did not already record the full sell-pressure exit case,
        % record the current sell pressure while the baseline is still long.
        if ~(position(k) == 0 && sellPressure(k) == 1.0)
            sellCounterHistory(k) = sellCounter;

            if position(k) == 1
                sellPressure(k) = min(sellCounter / params.sellConfirmDays, 1.0);
            else
                sellPressure(k) = 0.0;
            end
        end
    end

    %% ---------------- Baseline Buy/Sell Action Labels ----------------
    action = strings(N,1);
    action(:) = "Hold";

    for k = 2:N
        if position(k-1) == 0 && position(k) == 1
            action(k) = "Buy";
        elseif position(k-1) == 1 && position(k) == 0
            action(k) = "Sell";
        elseif position(k) == 1
            action(k) = "Hold Long";
        else
            action(k) = "Hold Cash";
        end
    end

    buyCount = sum(action == "Buy");
    sellCount = sum(action == "Sell");

    %% ---------------- Partial Exposure Logic ----------------
    % This branch does NOT replace the baseline position model.
    %
    % Late-stage sell-pressure de-risking:
    %   - If the baseline is cash, exposure is 0.
    %   - If the baseline is long and sell pressure is weak, exposure stays 1.
    %   - Exposure only scales down once sell pressure reaches the late-stage
    %     threshold.
    %
    % This is intentionally less reactive than the previous sell-pressure
    % overlay. The goal is to reduce exposure churn while only de-risking
    % when a confirmed baseline sell is getting close.

    exposure = zeros(N,1);

    if params.runPartialExposure
        for k = 1:N
            if position(k) == 0
                exposure(k) = params.exposureCash;
            else
                if sellPressure(k) < params.sellPressureLowThreshold
                    exposure(k) = params.exposureNoSellPressure;
                elseif sellPressure(k) < params.sellPressureHighThreshold
                    exposure(k) = params.exposureMediumSellPressure;
                else
                    exposure(k) = params.exposureHighSellPressure;
                end
            end
        end
    else
        exposure = position;
    end

    %% ---------------- Backtest Diagnostics ----------------
    dailyReturn = [0; price(2:end)./price(1:end-1) - 1];

    % Baseline 0/1 branch.
    strategyReturn = [0; position(1:end-1) .* dailyReturn(2:end)];
    trades = [0; abs(diff(position))];
    strategyReturnNet = strategyReturn - params.transactionCost * trades;

    buyHoldEquity = cumprod(1 + dailyReturn);
    strategyEquity = cumprod(1 + strategyReturnNet);

    % Partial exposure branch.
    exposureReturn = [0; exposure(1:end-1) .* dailyReturn(2:end)];
    exposureTurnover = [0; abs(diff(exposure))];

    % Transaction cost scales with turnover.
    % Example: 0.50 -> 1.00 counts as 0.50 turnover.
    exposureReturnNet = exposureReturn - params.transactionCost * exposureTurnover;
    exposureEquity = cumprod(1 + exposureReturnNet);

    totalReturnStrategy = strategyEquity(end) - 1;
    totalReturnExposure = exposureEquity(end) - 1;
    totalReturnBuyHold = buyHoldEquity(end) - 1;

    runningMax = cummax(strategyEquity);
    drawdown = strategyEquity ./ runningMax - 1;
    maxDrawdown = min(drawdown);

    exposureRunningMax = cummax(exposureEquity);
    exposureDrawdown = exposureEquity ./ exposureRunningMax - 1;
    exposureMaxDrawdown = min(exposureDrawdown);

    buyHoldRunningMax = cummax(buyHoldEquity);
    buyHoldDrawdown = buyHoldEquity ./ buyHoldRunningMax - 1;
    buyHoldMaxDrawdown = min(buyHoldDrawdown);

    strategySharpeApprox = safeSharpe(strategyReturnNet);
    exposureSharpeApprox = safeSharpe(exposureReturnNet);
    buyHoldSharpeApprox = safeSharpe(dailyReturn);

    tradeCount = sum(abs(diff(position)) > 0);
    timeInMarket = mean(position);

    exposureBuyCount = sum(exposure(1:end-1) == 0 & exposure(2:end) > 0);
    exposureSellCount = sum(exposure(1:end-1) > 0 & exposure(2:end) == 0);
    exposureAdjustmentCount = sum(abs(diff(exposure)) > 0);
    exposureTurnoverTotal = sum(exposureTurnover);
    exposureTimeInMarket = mean(exposure > 0);
    averageExposure = mean(exposure);

    baselineExcessReturn = totalReturnStrategy - totalReturnBuyHold;
    baselineDrawdownImprovement = maxDrawdown - buyHoldMaxDrawdown;
    baselineSharpeImprovement = strategySharpeApprox - buyHoldSharpeApprox;

    exposureExcessReturn = totalReturnExposure - totalReturnBuyHold;
    exposureDrawdownImprovement = exposureMaxDrawdown - buyHoldMaxDrawdown;
    exposureSharpeImprovement = exposureSharpeApprox - buyHoldSharpeApprox;

    %% ---------------- Output Tables/Structs ----------------
    results = table(dates, price, price_est, price_low, price_high, ...
        trend_est, trend_low, trend_high, ...
        accel_est, accel_low, accel_high, ...
        position, action, buyCounterHistory, sellCounterHistory, sellPressure, exposure, ...
        dailyReturn, strategyReturnNet, exposureReturnNet, ...
        buyHoldEquity, strategyEquity, exposureEquity, drawdown, exposureDrawdown, buyHoldDrawdown, ...
        'VariableNames', ["Date", "Price", "FilteredPrice", "PriceLowCI", "PriceHighCI", ...
        "Trend", "TrendLowCI", "TrendHighCI", ...
        "Acceleration", "AccelLowCI", "AccelHighCI", ...
        "Position", "Action", "BuyCounter", "SellCounter", "SellPressure", "Exposure", ...
        "DailyReturn", "StrategyReturnNet", "ExposureReturnNet", ...
        "BuyHoldEquity", "StrategyEquity", "ExposureEquity", "StrategyDrawdown", "ExposureDrawdown", "BuyHoldDrawdown"]);

    summary = struct();
    summary.filename = filename;
    summary.startDate = dates(1);
    summary.endDate = dates(end);
    summary.numDataPoints = N;

    summary.q_jerk = q_jerk;
    summary.r_meas = r_meas;
    summary.buyConfirmDays = params.buyConfirmDays;
    summary.sellConfirmDays = params.sellConfirmDays;
    summary.transactionCost = params.transactionCost;

    % Backward-compatible baseline fields.
    summary.buyCount = buyCount;
    summary.sellCount = sellCount;
    summary.tradeCount = tradeCount;
    summary.timeInMarket = timeInMarket;
    summary.strategyTotalReturn = totalReturnStrategy;
    summary.buyHoldTotalReturn = totalReturnBuyHold;
    summary.strategyMaxDrawdown = maxDrawdown;
    summary.buyHoldMaxDrawdown = buyHoldMaxDrawdown;
    summary.strategySharpeApprox = strategySharpeApprox;
    summary.buyHoldSharpeApprox = buyHoldSharpeApprox;

    % Explicit buy-hold comparison fields.
    summary.buyHoldBuyCount = 1;
    summary.buyHoldSellCount = 0;
    summary.buyHoldTradeCount = 0;
    summary.buyHoldTimeInMarket = 1;
    summary.buyHoldExcessReturn = 0;
    summary.buyHoldDrawdownImprovement = 0;
    summary.buyHoldSharpeImprovement = 0;

    % Explicit baseline comparison fields.
    summary.baselineBuyCount = buyCount;
    summary.baselineSellCount = sellCount;
    summary.baselineTradeCount = tradeCount;
    summary.baselineTimeInMarket = timeInMarket;
    summary.baselineTotalReturn = totalReturnStrategy;
    summary.baselineMaxDrawdown = maxDrawdown;
    summary.baselineSharpeApprox = strategySharpeApprox;
    summary.baselineExcessReturn = baselineExcessReturn;
    summary.baselineDrawdownImprovement = baselineDrawdownImprovement;
    summary.baselineSharpeImprovement = baselineSharpeImprovement;

    % Explicit partial-exposure comparison fields.
    summary.runPartialExposure = params.runPartialExposure;
    summary.exposureBuyCount = exposureBuyCount;
    summary.exposureSellCount = exposureSellCount;
    summary.exposureTradeCount = exposureAdjustmentCount;
    summary.exposureTimeInMarket = exposureTimeInMarket;
    summary.averageExposure = averageExposure;
    summary.exposureTurnoverTotal = exposureTurnoverTotal;
    summary.maxSellPressure = max(sellPressure);

    if any(position == 1)
        summary.avgSellPressureWhileLong = mean(sellPressure(position == 1), "omitnan");
    else
        summary.avgSellPressureWhileLong = NaN;
    end
    summary.exposureTotalReturn = totalReturnExposure;
    summary.exposureMaxDrawdown = exposureMaxDrawdown;
    summary.exposureSharpeApprox = exposureSharpeApprox;
    summary.exposureExcessReturn = exposureExcessReturn;
    summary.exposureDrawdownImprovement = exposureDrawdownImprovement;
    summary.exposureSharpeImprovement = exposureSharpeImprovement;

    %% ---------------- Print Summary ----------------
    if params.printSummary
        fprintf("\nFile: %s\n", filename);
        fprintf("Data start date: %s\n", string(summary.startDate));
        fprintf("Data end date:   %s\n", string(summary.endDate));
        fprintf("Number of data points: %d\n", summary.numDataPoints);

        fprintf("\nBuy-hold total return: %.2f%%\n", 100*totalReturnBuyHold);
        fprintf("Buy-hold max drawdown: %.2f%%\n", 100*buyHoldMaxDrawdown);
        fprintf("Buy-hold Approx. Sharpe ratio: %.2f\n", buyHoldSharpeApprox);

        fprintf("\nBaseline buy count: %d\n", buyCount);
        fprintf("Baseline sell count: %d\n", sellCount);
        fprintf("Baseline trade count: %d\n", tradeCount);
        fprintf("Baseline time in market: %.2f%%\n", 100*timeInMarket);
        fprintf("Baseline total return: %.2f%%\n", 100*totalReturnStrategy);
        fprintf("Baseline max drawdown: %.2f%%\n", 100*maxDrawdown);
        fprintf("Baseline Approx. Sharpe ratio: %.2f\n", strategySharpeApprox);
        fprintf("Baseline excess return: %.2f%%\n", 100*baselineExcessReturn);
        fprintf("Baseline drawdown improvement: %.2f percentage points\n", 100*baselineDrawdownImprovement);
        fprintf("Baseline Sharpe improvement: %.2f\n", baselineSharpeImprovement);

        if params.runPartialExposure
            fprintf("\nExposure buy count: %d\n", exposureBuyCount);
            fprintf("Exposure sell count: %d\n", exposureSellCount);
            fprintf("Exposure adjustment count: %d\n", exposureAdjustmentCount);
            fprintf("Exposure time in market: %.2f%%\n", 100*exposureTimeInMarket);
            fprintf("Average exposure: %.2f%%\n", 100*averageExposure);
            fprintf("Total exposure turnover: %.2f\n", exposureTurnoverTotal);
            fprintf("Max sell pressure: %.2f\n", max(sellPressure));

            if any(position == 1)
                fprintf("Average sell pressure while long: %.2f\n", mean(sellPressure(position == 1), "omitnan"));
            else
                fprintf("Average sell pressure while long: NaN\n");
            end
            fprintf("Exposure total return: %.2f%%\n", 100*totalReturnExposure);
            fprintf("Exposure max drawdown: %.2f%%\n", 100*exposureMaxDrawdown);
            fprintf("Exposure Approx. Sharpe ratio: %.2f\n", exposureSharpeApprox);
            fprintf("Exposure excess return: %.2f%%\n", 100*exposureExcessReturn);
            fprintf("Exposure drawdown improvement: %.2f percentage points\n", 100*exposureDrawdownImprovement);
            fprintf("Exposure Sharpe improvement: %.2f\n", exposureSharpeImprovement);
        end
    end

    %% ---------------- Plots ----------------
    figs = struct();

    if params.makePlots

        buyIdx = action == "Buy";
        sellIdx = action == "Sell";

        % Plot 1: Buy/Sell Markers
        figs.buySellSignals = figure;
        hold on; grid on;

        plot(dates, price, 'k', 'LineWidth', 1.0);
        plot(dates, price_est, 'r', 'LineWidth', 1.5);

        scatter(dates(buyIdx), price(buyIdx), 60, '^', 'filled');
        scatter(dates(sellIdx), price(sellIdx), 60, 'v', 'filled');

        xlabel("Date");
        ylabel("Price");
        title(tickerLabel + " - Kalman Trend Buy/Sell Signals");
        legend("Observed Price", "Filtered Price", "Buy", "Sell", "Location", "best");

        % Plot 2: Position Signal
        figs.positionSignal = figure;
        hold on; grid on;

        yyaxis left;
        hPrice = plot(dates, price, 'k', 'LineWidth', 1.0);
        ylabel("Price");

        yyaxis right;
        hPosition = stairs(dates, position, 'LineWidth', 1.5);
        ylabel("Position");
        ylim([-0.1 1.1]);

        xlabel("Date");
        title(tickerLabel + " - Baseline Position Signal");

        legend([hPrice, hPosition], {'Price', 'Position'}, 'Location', 'best');

        % Plot 3: Strategy Comparison
        figs.strategyComparison = figure;
        hold on; grid on;

        plot(dates, buyHoldEquity, 'k', 'LineWidth', 1.2);
        plot(dates, strategyEquity, 'b', 'LineWidth', 1.5);

        if params.runPartialExposure
            plot(dates, exposureEquity, 'g', 'LineWidth', 1.5);
            legend("Buy and Hold", "Baseline 0/1 Strategy", "Partial Exposure Strategy", "Location", "best");
        else
            legend("Buy and Hold", "Baseline 0/1 Strategy", "Location", "best");
        end

        xlabel("Date");
        ylabel("Growth of $1");
        title(tickerLabel + " - Strategy Comparison");

        % Plot 4: Partial Exposure Signal
        if params.runPartialExposure
            figs.partialExposureSignal = figure;
            hold on; grid on;

            yyaxis left;
            hPrice2 = plot(dates, price, 'k', 'LineWidth', 1.0);
            ylabel("Price");

            yyaxis right;
            hExposure = stairs(dates, exposure, 'LineWidth', 1.5);
            ylabel("Exposure");
            ylim([-0.1 1.1]);

            xlabel("Date");
            title(tickerLabel + " - Late-Stage Sell-Pressure Partial Exposure Signal");

            legend([hPrice2, hExposure], {'Price', 'Exposure'}, 'Location', 'best');
        end

        if params.showStatePlots
            % Optional Plot 5: Price Estimate with CI
            figs.priceEstimate = figure;
            hold on; grid on;

            fill([dates; flipud(dates)], ...
                 [price_low; flipud(price_high)], ...
                 [0.85 0.85 0.85], ...
                 'EdgeColor', 'none', ...
                 'FaceAlpha', 0.5);

            plot(dates, price, 'k', 'LineWidth', 1.0);
            plot(dates, price_est, 'r', 'LineWidth', 1.5);

            xlabel("Date");
            ylabel("Price");
            title(tickerLabel + " - Kalman Filter Price Estimate with Confidence Interval");
            legend("CI", "Observed Price", "Filtered Price", "Location", "best");

            % Optional Plot 6: Trend Estimate
            figs.trendEstimate = figure;
            hold on; grid on;

            fill([dates; flipud(dates)], ...
                 [trend_low; flipud(trend_high)], ...
                 [0.85 0.85 0.85], ...
                 'EdgeColor', 'none', ...
                 'FaceAlpha', 0.5);

            plot(dates, trend_est, 'b', 'LineWidth', 1.5);
            yline(0, 'k--');

            xlabel("Date");
            ylabel("Trend Estimate");
            title(tickerLabel + " - Estimated Log-Price Trend with Confidence Interval");            legend("CI", "Trend", "Zero Line", "Location", "best");

            % Optional Plot 7: Acceleration Estimate
            figs.accelerationEstimate = figure;
            hold on; grid on;

            fill([dates; flipud(dates)], ...
                 [accel_low; flipud(accel_high)], ...
                 [0.85 0.85 0.85], ...
                 'EdgeColor', 'none', ...
                 'FaceAlpha', 0.5);

            plot(dates, accel_est, 'm', 'LineWidth', 1.5);
            yline(0, 'k--');

            xlabel("Date");
            ylabel("Acceleration Estimate");
            title(tickerLabel + " - Estimated Log-Price Acceleration with Confidence Interval");            legend("CI", "Acceleration", "Zero Line", "Location", "best");
        end
    end
end

%% ---------------- Local Helper Functions ----------------
function params = setDefault(params, fieldName, defaultValue)
    if ~isfield(params, fieldName) || isempty(params.(fieldName))
        params.(fieldName) = defaultValue;
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
