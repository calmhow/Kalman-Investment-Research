%% Single-Stock Kalman Filter Trend Model
% State:
% x = [log_price; trend; acceleration]
%
% trend       = first derivative of log price
% acceleration = second derivative of log price

clear; clc; close all;

%% ---------------- User Inputs ----------------
filename = "data/SPY.csv";   % Change to SPY.csv, NVDA.csv, etc.
dt = 1;                  % 1 trading day

% Tuning parameters
q_jerk = 1e-7;            % Process noise strength
r_meas = 1e-4;            % Measurement noise variance in log-price space

% Confidence level
z90 = 1.64485;            % 90% two-sided confidence interval

%% ---------------- Load Data ----------------
T = readtable(filename);

% Convert date column if needed
if ismember("Date", T.Properties.VariableNames)
    dates = datetime(T.Date);
else
    dates = (1:height(T))';
end

% Use adjusted close if available, otherwise close
if ismember("AdjClose", T.Properties.VariableNames)
    price = T.AdjClose;
elseif ismember("Close", T.Properties.VariableNames)
    price = T.Close;
else
    error("CSV must contain either AdjClose or Close column.");
end

% Clean missing or invalid prices
valid = ~isnan(price) & price > 0;
price = price(valid);
dates = dates(valid);

z = log(price);
N = length(z);

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

% Initial state estimate
xhat(:,1) = [z(1); 0; 0];

% Initial covariance
P = diag([1e-4, 1e-5, 1e-6]);
Pstore(:,:,1) = P;

%% ---------------- Kalman Filter Loop ----------------
for k = 2:N

    % ---------- Predict ----------
    x_pred = F * xhat(:,k-1);
    P_pred = F * P * F' + Q;

    % ---------- Innovation ----------
    y = z(k) - H * x_pred;
    S = H * P_pred * H' + R;

    % ---------- Kalman Gain ----------
    K = P_pred * H' / S;

    % ---------- Update ----------
    xhat(:,k) = x_pred + K * y;

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

% Standard deviations
sigma_logPrice = squeeze(sqrt(Pstore(1,1,:)));
sigma_trend    = squeeze(sqrt(Pstore(2,2,:)));
sigma_accel    = squeeze(sqrt(Pstore(3,3,:)));

% 90% confidence intervals
logPrice_low  = logPrice_est - z90*sigma_logPrice;
logPrice_high = logPrice_est + z90*sigma_logPrice;

price_low  = exp(logPrice_low);
price_high = exp(logPrice_high);

trend_low  = trend_est - z90*sigma_trend;
trend_high = trend_est + z90*sigma_trend;

accel_low  = accel_est - z90*sigma_accel;
accel_high = accel_est + z90*sigma_accel;

%% ---------------- Improved Asymmetric Signal Logic ----------------
% 1 = long
% 0 = cash
%
% Buy rule is stricter.
% Sell rule uses a negative buffer to avoid selling on tiny trend noise.

position = zeros(N,1);

buyConfirmDays  = 10;
sellConfirmDays = 5;

sellBuffer = -0.0005;   % negative trend threshold

buySignal  = trend_low > 0;
sellSignal = trend_est < sellBuffer;

buyCount = 0;
sellCount = 0;

for k = 2:N

    % Default: hold previous position
    position(k) = position(k-1);

    if position(k-1) == 0
        % We are in cash, so only look for buy confirmation
        if buySignal(k)
            buyCount = buyCount + 1;
        else
            buyCount = 0;
        end

        sellCount = 0;

        if buyCount >= buyConfirmDays
            position(k) = 1;
            buyCount = 0;
        end

    elseif position(k-1) == 1
        % We are long, so only look for sell confirmation
        if sellSignal(k)
            sellCount = sellCount + 1;
        else
            sellCount = 0;
        end

        buyCount = 0;

        if sellCount >= sellConfirmDays
            position(k) = 0;
            sellCount = 0;
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

fprintf("Buy count: %d\n", buyCount);
fprintf("Sell count: %d\n", sellCount);

%% ---------------- Basic Backtest Diagnostics ----------------
% Uses yesterday's position for today's return to avoid look-ahead bias.

dailyReturn = [0; diff(price)./price(1:end-1)];

% Position must be lagged by one day
strategyReturn = [0; position(1:end-1) .* dailyReturn(2:end)];

% Simple transaction cost model
transactionCost = 0.001;   % 0.1% per trade
trades = [0; abs(diff(position))];

strategyReturnNet = strategyReturn - transactionCost * trades;

buyHoldEquity = cumprod(1 + dailyReturn);
strategyEquity = cumprod(1 + strategyReturnNet);

totalReturnStrategy = strategyEquity(end) - 1;
totalReturnBuyHold = buyHoldEquity(end) - 1;

runningMax = cummax(strategyEquity);
drawdown = strategyEquity ./ runningMax - 1;
maxDrawdown = min(drawdown);

sharpeApprox = sqrt(252) * mean(strategyReturnNet) / std(strategyReturnNet);

fprintf("Strategy total return: %.2f%%\n", 100*totalReturnStrategy);
fprintf("Buy-hold total return: %.2f%%\n", 100*totalReturnBuyHold);
fprintf("Strategy max drawdown: %.2f%%\n", 100*maxDrawdown);
fprintf("Approx. Sharpe ratio: %.2f\n", sharpeApprox);

%% ---------------- Signal Diagnostics ----------------
tradeCount = sum(abs(diff(position)) > 0);
timeInMarket = mean(position);

fprintf("Trade count: %d\n", tradeCount);
fprintf("Time in market: %.2f%%\n", 100*timeInMarket);

%% ---------------- Plot 1: Price Estimate ----------------
figure;
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
title("Kalman Filter Price Estimate with 90% Confidence Interval");
legend("90% CI", "Observed Price", "Filtered Price", "Location", "best");

%% ---------------- Plot 2: Buy/sell marker plot ----------------
buyIdx = action == "Buy";
sellIdx = action == "Sell";

figure;
hold on; grid on;

plot(dates, price, 'k', 'LineWidth', 1.0);
plot(dates, price_est, 'r', 'LineWidth', 1.5);

scatter(dates(buyIdx), price(buyIdx), 60, '^', 'filled');
scatter(dates(sellIdx), price(sellIdx), 60, 'v', 'filled');

xlabel("Date");
ylabel("Price");
title("Kalman Trend Buy/Sell Signals");
legend("Observed Price", "Filtered Price", "Buy", "Sell", "Location", "best");


%% ---------------- Plot 3: Trend Estimate ----------------
figure;
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
title("Estimated Log-Price Trend with 90% Confidence Interval");
legend("90% CI", "Trend", "Zero Line", "Location", "best");

%% ---------------- Plot 4: Acceleration Estimate ----------------
figure;
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
title("Estimated Log-Price Acceleration with 90% Confidence Interval");
legend("90% CI", "Acceleration", "Zero Line", "Location", "best");

%% ---------------- Plot 5: Position Signal ----------------
figure;
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

%% ---------------- Plot 6: Strategy vs Buy-and-Hold ----------------
figure;
hold on; grid on;

plot(dates, buyHoldEquity, 'k', 'LineWidth', 1.2);
plot(dates, strategyEquity, 'b', 'LineWidth', 1.5);

xlabel("Date");
ylabel("Growth of $1");
title("Kalman Strategy vs Buy-and-Hold");
legend("Buy and Hold", "Kalman Strategy", "Location", "best");

%% ---------------- Output Summary ----------------
results = table(dates, price, price_est, trend_est, trend_low, trend_high, ...
    accel_est, accel_low, accel_high, position, action, ...
    'VariableNames', ["Date", "Price", "FilteredPrice", ...
    "Trend", "TrendLow90", "TrendHigh90", ...
    "Acceleration", "AccelLow90", "AccelHigh90", ...
    "Position", "Action"]);

disp(results(end-10:end,:));

% close all %temp