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

%% ---------------- Improved Signal Logic ----------------
% 1 = long
% 0 = cash
%
% Requires trend confidence to stay positive/negative for several days
% before changing position.

position = zeros(N,1);

confirmDays = 5;   % Require 5 consecutive days before switching

longSignal = trend_low > 0;
cashSignal = trend_high < 0;

longCount = 0;
cashCount = 0;

for k = 2:N

    if longSignal(k)
        longCount = longCount + 1;
    else
        longCount = 0;
    end

    if cashSignal(k)
        cashCount = cashCount + 1;
    else
        cashCount = 0;
    end

    % Default: hold previous position
    position(k) = position(k-1);

    % Switch only after confirmation
    if longCount >= confirmDays
        position(k) = 1;
    elseif cashCount >= confirmDays
        position(k) = 0;
    end
end

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

%% ---------------- Plot 2: Trend Estimate ----------------
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

%% ---------------- Plot 3: Acceleration Estimate ----------------
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

%% ---------------- Plot 4: Position Signal ----------------
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

%% ---------------- Output Summary ----------------
results = table(dates, price, price_est, trend_est, trend_low, trend_high, ...
    accel_est, accel_low, accel_high, position, ...
    'VariableNames', ["Date", "Price", "FilteredPrice", ...
    "Trend", "TrendLow90", "TrendHigh90", ...
    "Acceleration", "AccelLow90", "AccelHigh90", "Position"]);

disp(results(end-10:end,:));