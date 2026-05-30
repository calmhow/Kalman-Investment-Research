function [results, summary, figs] = runKalmanTrendModel(filename, params)
% runKalmanTrendModel
% Reusable Kalman trend model for one ticker CSV file.
%
% Required input:
%   filename : CSV file path, for example "data/SPY.csv"
%
% Optional input:
%   params : struct of optional tuning/settings values
%
% Example:
%   [results, summary, figs] = runKalmanTrendModel("data/SPY.csv");
%
% Example with overrides:
%   params = struct();
%   params.r_meas = 7.5e-4;
%   params.makePlots = false;
%   [results, summary] = runKalmanTrendModel("data/QQQ.csv", params);
%
% State:
%   x = [log_price; trend; acceleration]
%
% Current baseline:
%   q_jerk = 1e-7
%   r_meas = 5e-4
%   buySignal  = trend_est > 0
%   sellSignal = trend_high < 0
%   buyConfirmDays = 5
%   sellConfirmDays = 8

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
    params = setDefault(params, "transactionCost", 0.001);    % 0.1% per trade
    params = setDefault(params, "makePlots", true);
    params = setDefault(params, "printSummary", true);
    params = setDefault(params, "startDate", []);
    params = setDefault(params, "endDate", []);

    dt = params.dt;
    q_jerk = params.q_jerk;
    r_meas = params.r_meas;
    zCI = params.zCI;

    %% ---------------- Load Data ----------------
    T = readtable(filename);

    % Convert date column if needed
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

    % Use adjusted close if available, otherwise close
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

    % Clean missing or invalid prices
    valid = ~isnan(price) & price > 0;
    price = price(valid);
    dates = dates(valid);

    % Sort oldest to newest
    [dates, sortIdx] = sort(dates);
    price = price(sortIdx);

    % Optional date filter
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

    % Random jerk process noise model
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

        % Predict
        x_pred = F * xhat(:,k-1);
        P_pred = F * P * F' + Q;

        % Innovation
        innovation = z(k) - H * x_pred;
        S = H * P_pred * H' + R;

        % Kalman gain
        K = P_pred * H' / S;

        % Update
        xhat(:,k) = x_pred + K * innovation;

        % Joseph covariance update for numerical stability
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

    %% ---------------- Signal Logic ----------------
    % Current baseline:
    %   buySignal  = trend_est > 0
    %   sellSignal = trend_high < 0

    position = zeros(N,1);

    buySignal  = trend_est > 0;
    sellSignal = trend_high < 0;

    buyCounter = 0;
    sellCounter = 0;

    for k = 2:N

        % Default: hold previous position
        position(k) = position(k-1);

        if position(k-1) == 0

            % In cash, only look for buy confirmation
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

            % Long, only look for sell confirmation
            if sellSignal(k)
                sellCounter = sellCounter + 1;
            else
                sellCounter = 0;
            end

            buyCounter = 0;

            if sellCounter >= params.sellConfirmDays
                position(k) = 0;
                sellCounter = 0;
            end
        end
    end

    %% ---------------- Buy/Sell Action Labels ----------------
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

    %% ---------------- Backtest Diagnostics ----------------
    % Uses yesterday's position for today's return to avoid look-ahead bias.

    dailyReturn = [0; price(2:end)./price(1:end-1) - 1];

    % Position must be lagged by one day
    strategyReturn = [0; position(1:end-1) .* dailyReturn(2:end)];

    trades = [0; abs(diff(position))];

    strategyReturnNet = strategyReturn - params.transactionCost * trades;

    buyHoldEquity = cumprod(1 + dailyReturn);
    strategyEquity = cumprod(1 + strategyReturnNet);

    totalReturnStrategy = strategyEquity(end) - 1;
    totalReturnBuyHold = buyHoldEquity(end) - 1;

    runningMax = cummax(strategyEquity);
    drawdown = strategyEquity ./ runningMax - 1;
    maxDrawdown = min(drawdown);

    buyHoldRunningMax = cummax(buyHoldEquity);
    buyHoldDrawdown = buyHoldEquity ./ buyHoldRunningMax - 1;
    buyHoldMaxDrawdown = min(buyHoldDrawdown);

    strategySharpeApprox = safeSharpe(strategyReturnNet);
    buyHoldSharpeApprox = safeSharpe(dailyReturn);

    tradeCount = sum(abs(diff(position)) > 0);
    timeInMarket = mean(position);

    %% ---------------- Output Tables/Structs ----------------
    results = table(dates, price, price_est, price_low, price_high, ...
        trend_est, trend_low, trend_high, ...
        accel_est, accel_low, accel_high, ...
        position, action, dailyReturn, strategyReturnNet, ...
        buyHoldEquity, strategyEquity, drawdown, buyHoldDrawdown, ...
        'VariableNames', ["Date", "Price", "FilteredPrice", "PriceLowCI", "PriceHighCI", ...
        "Trend", "TrendLowCI", "TrendHighCI", ...
        "Acceleration", "AccelLowCI", "AccelHighCI", ...
        "Position", "Action", "DailyReturn", "StrategyReturnNet", ...
        "BuyHoldEquity", "StrategyEquity", "StrategyDrawdown", "BuyHoldDrawdown"]);

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

    %% ---------------- Print Summary ----------------
    if params.printSummary
        fprintf("\nFile: %s\n", filename);
        fprintf("Data start date: %s\n", string(summary.startDate));
        fprintf("Data end date:   %s\n", string(summary.endDate));
        fprintf("Number of data points: %d\n", summary.numDataPoints);

        fprintf("\nBuy count: %d\n", buyCount);
        fprintf("Sell count: %d\n", sellCount);
        fprintf("Strategy total return: %.2f%%\n", 100*totalReturnStrategy);
        fprintf("Buy-hold total return: %.2f%%\n", 100*totalReturnBuyHold);
        fprintf("Strategy max drawdown: %.2f%%\n", 100*maxDrawdown);
        fprintf("Buy-hold max drawdown: %.2f%%\n", 100*buyHoldMaxDrawdown);
        fprintf("Strategy Approx. Sharpe ratio: %.2f\n", strategySharpeApprox);
        fprintf("Buy-hold Approx. Sharpe ratio: %.2f\n", buyHoldSharpeApprox);
        fprintf("Trade count: %d\n", tradeCount);
        fprintf("Time in market: %.2f%%\n", 100*timeInMarket);
    end

    %% ---------------- Plots ----------------
    figs = struct();

    if params.makePlots

        % Plot 1: Price Estimate
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
        title("Kalman Filter Price Estimate with Confidence Interval");
        legend("CI", "Observed Price", "Filtered Price", "Location", "best");

        % Plot 2: Buy/Sell Markers
        buyIdx = action == "Buy";
        sellIdx = action == "Sell";

        figs.buySellSignals = figure;
        hold on; grid on;

        plot(dates, price, 'k', 'LineWidth', 1.0);
        plot(dates, price_est, 'r', 'LineWidth', 1.5);

        scatter(dates(buyIdx), price(buyIdx), 60, '^', 'filled');
        scatter(dates(sellIdx), price(sellIdx), 60, 'v', 'filled');

        xlabel("Date");
        ylabel("Price");
        title("Kalman Trend Buy/Sell Signals");
        legend("Observed Price", "Filtered Price", "Buy", "Sell", "Location", "best");

        % Plot 3: Trend Estimate
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
        title("Estimated Log-Price Trend with Confidence Interval");
        legend("CI", "Trend", "Zero Line", "Location", "best");

        % Plot 4: Acceleration Estimate
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
        title("Estimated Log-Price Acceleration with Confidence Interval");
        legend("CI", "Acceleration", "Zero Line", "Location", "best");

        % Plot 5: Position Signal
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
        title("Preliminary Trend-Based Position Signal");

        legend([hPrice, hPosition], {'Price', 'Position'}, 'Location', 'best');

        % Plot 6: Strategy vs Buy-and-Hold
        figs.strategyComparison = figure;
        hold on; grid on;

        plot(dates, buyHoldEquity, 'k', 'LineWidth', 1.2);
        plot(dates, strategyEquity, 'b', 'LineWidth', 1.5);

        xlabel("Date");
        ylabel("Growth of $1");
        title("Kalman Strategy vs Buy-and-Hold");
        legend("Buy and Hold", "Kalman Strategy", "Location", "best");
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
