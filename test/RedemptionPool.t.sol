// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./BaseFixture.sol";
import {RedemptionErrors} from "../src/Errors.sol";

contract TestRedemptionPool is BaseFixture {
    function setUp() public override {
        super.setUp();
    }

    function testDummy() public {
        assertTrue(true);
    }

    /////////////////////////////////////////////////////////////////////////////
    //                              Basic functionality                        //
    /////////////////////////////////////////////////////////////////////////////
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

    /// @dev test cannot deposit after deadline
    function testDepositUnhappyDeadline(uint256 _depositAmnt) public {
        vm.assume(_depositAmnt > 1e18);
        // Give user some GRO:
        setStorage(alice, GRO.balanceOf.selector, address(GRO), _depositAmnt);
        // Approve GRO to be spent by the RedemptionPool:
        vm.prank(alice);
        GRO.approve(address(redemptionPool), _depositAmnt);
        vm.warp(redemptionPool.DEADLINE() + 1);
        // Deposit GRO into the RedemptionPool:
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(RedemptionErrors.DeadlineExceeded.selector));
        redemptionPool.deposit(_depositAmnt);
        vm.stopPrank();
    }

    /// @dev test can withdraw after deposit
    function testWithdrawHappy(uint256 _depositAmnt) public {
        vm.assume(_depositAmnt > 1e18);
        // Give user some GRO:
        setStorage(alice, GRO.balanceOf.selector, address(GRO), _depositAmnt);
        // Approve GRO to be spent by the RedemptionPool:
        vm.prank(alice);
        GRO.approve(address(redemptionPool), _depositAmnt);

        // Deposit GRO into the RedemptionPool:
        vm.prank(alice);
        redemptionPool.deposit(_depositAmnt);

        // Withdraw before deadline:
        vm.prank(alice);
        redemptionPool.withdraw(_depositAmnt);
        // Checks:
        assertEq(GRO.balanceOf(address(redemptionPool)), 0);
        assertEq(GRO.balanceOf(alice), _depositAmnt);
        assertEq(redemptionPool.getUserBalance(alice), 0);
    }

    /// @dev test cannot withdraw after deadline
    function testWithdrawUnhappyDeadline(uint256 _depositAmnt) public {
        vm.assume(_depositAmnt > 1e18);
        // Give user some GRO:
        setStorage(alice, GRO.balanceOf.selector, address(GRO), _depositAmnt);
        // Approve GRO to be spent by the RedemptionPool:
        vm.prank(alice);
        GRO.approve(address(redemptionPool), _depositAmnt);

        // Deposit GRO into the RedemptionPool:
        vm.prank(alice);
        redemptionPool.deposit(_depositAmnt);
        vm.warp(redemptionPool.DEADLINE() + 1);
        // Withdraw after deadline:
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(RedemptionErrors.DeadlineExceeded.selector));
        redemptionPool.withdraw(_depositAmnt);
        vm.stopPrank();
    }

    /// @dev Test for pulling in assets from the DAO
    function testPullCUSDC(uint96 _amount) public {
        vm.assume(_amount > 1e6);
        vm.assume(_amount < 100_000_000e6);

        pullCUSDC(_amount);

        assertEq(CUSDC.balanceOf(address(redemptionPool)), _amount);
    }

    /// @dev Test sweeping CUSDC
    function testSweep(uint96 _amount) public {
        vm.assume(_amount > 1e6);
        vm.assume(_amount < 100_000_000e6);

        pullCUSDC(_amount);
        // Snapshot balance
        uint256 snapshot = CUSDC.balanceOf(address(DAO));
        // Sweep CUSDC to the DAO
        vm.prank(DAO);
        redemptionPool.sweep(address(CUSDC));

        assertEq(CUSDC.balanceOf(address(redemptionPool)), 0);
        assertEq(CUSDC.balanceOf(DAO), snapshot + _amount);
    }

    function testCantSweepGRO() public {
        vm.prank(DAO);
        vm.expectRevert(abi.encodeWithSelector(RedemptionErrors.NoSweepGro.selector));
        redemptionPool.sweep(address(GRO));
    }

    /////////////////////////////////////////////////////////////////////////////
    //                              Full flow                                  //
    /////////////////////////////////////////////////////////////////////////////
}
