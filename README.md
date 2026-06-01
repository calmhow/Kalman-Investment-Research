# Kalman Filter Investment Research Project

This project researches Kalman filter and Extended Kalman filter methods for investment trend analysis. The goal is not to predict exact stock prices, but to estimate hidden trend, trend acceleration, uncertainty, and market regime behavior from price data.

## Current Model

The current model uses a linear Kalman filter with the state:

```matlab
x = [log_price; trend; acceleration]
```

The filter estimates:

- Smoothed log price
- Hidden price trend
- Hidden trend acceleration
- Covariance-based confidence intervals
- Buy/sell/hold signals based on trend confidence

## Current Baseline Parameters

Current shared ETF baseline:

```matlab
q_jerk = 1e-7;
r_meas = 5e-4;

buySignal  = trend_est > 0;
sellSignal = trend_high < 0;

buyConfirmDays  = 5;
sellConfirmDays = 8;

transactionCost = 0.001;
```

The verified SPY tuning period is:

```text
2015-01-01 to 2026-05-29
```

## Main MATLAB Function

The main reusable function is:

```matlab
[results, summary, figs] = runKalmanTrendModel(filename, params);
```

Basic use:

```matlab
[results, summary, figs] = runKalmanTrendModel("data/SPY.csv");
```

Quiet batch use:

```matlab
params = struct();
params.makePlots = false;
params.printSummary = false;

[results, summary] = runKalmanTrendModel("data/SPY.csv", params);
```

## Current Findings

The current baseline works best on broad ETF/index-style assets such as SPY and SPYG. QQQ may prefer slightly different measurement noise. Individual stocks such as MSFT and NVDA do not generalize as well under the same ETF-tuned settings and may require separate or adaptive logic.

Current interpretation:

- Strongest fit: SPY, SPYG
- Mixed fit: QQQ
- Weak fit under current ETF settings: MSFT, NVDA

## Important Research Principles

- Avoid look-ahead bias.
- Avoid survivorship bias when possible.
- Include transaction costs and slippage.
- Do not judge the model only by visual fit.
- Compare against buy-and-hold, moving averages, and momentum baselines.
- Evaluate total return, max drawdown, Sharpe ratio, trade count, and time in market.
- Treat the Kalman filter as a trend and uncertainty estimator, not a guaranteed price predictor.

## Next Steps

1. Use the reusable function for batch testing.
2. Add walk-forward validation.
3. Compare against simple moving-average and momentum baselines.
4. Add ETF/index regime filters.
5. Later, explore adaptive Kalman tuning using innovation error.
6. Only after simple models are validated, consider neural networks for adaptive parameter control.
