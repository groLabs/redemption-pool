// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

library RedemptionErrors {
    error DeadlineExceeded();
    error DeadlineNotExceeded();
    error UserBalanceToSmall();
    error NoUserBalance();
    error NoUserClaim();

    error NoSweepGro();
    error AmountExceedsAvailableGRO();
}
