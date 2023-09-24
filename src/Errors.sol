// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

library RedemptionErrors {
    error DeadlineExceeded();
    error ClaimsPeriodNotStarted();
    error GreaterThanZeroOnly();
    error InsufficientBalance();
    error USDCRedeemFailed(uint256 redeemResult);

    error NoSweepGro();
    error NoUserBalance();
}
