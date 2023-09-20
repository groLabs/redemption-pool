// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./BaseFixture.sol";

contract TestRedemptionPool is BaseFixture {
    function setUp() public override {
        super.setUp();
    }

    function testDummy() public {
        assertTrue(true);
    }

    /// @dev Basic test to check that the deposit function works
    function testDepositHappy(uint256 _depositAmnt) public {
        vm.assume(_depositAmnt > 1e18);
        // Give user some GRO:
        setStorage(alice, GRO.balanceOf.selector, address(GRO), _depositAmnt);
        // Approve GRO to be spent by the RedemptionPool:
        vm.prank(alice);
        GRO.approve(address(redemptionPool), _depositAmnt);

        // Deposit GRO into the RedemptionPool:
        vm.prank(alice);
        redemptionPool.deposit(_depositAmnt);
        // Checks:
        assertEq(GRO.balanceOf(address(redemptionPool)), _depositAmnt);
        assertEq(GRO.balanceOf(alice), 0);

        assertEq(redemptionPool.totalGRO(), _depositAmnt);

        assertEq(redemptionPool.getUserBalance(alice), _depositAmnt);
    }
}
