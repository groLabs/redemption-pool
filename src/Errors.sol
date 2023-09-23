// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

library RedemptionErrors {
    error DeadlineExceeded();
    error ClaimsPeriodNotStarted();
    error NoUserBalance();
    error GreaterThanZeroOnly();

    error NoSweepGro();
    error AmountExceedsAvailableGRO();
}
