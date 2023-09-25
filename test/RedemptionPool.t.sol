// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./BaseFixture.sol";
import {RedemptionErrors} from "../src/Errors.sol";

contract TestRedemptionPool is BaseFixture {
    uint256 public constant USER_COUNT = 100;

    function setUp() public override {
        super.setUp();
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
        vm.expectRevert(
            abi.encodeWithSelector(RedemptionErrors.DeadlineExceeded.selector)
        );
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
        vm.expectRevert(
            abi.encodeWithSelector(RedemptionErrors.DeadlineExceeded.selector)
        );
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
        vm.expectRevert(
            abi.encodeWithSelector(RedemptionErrors.NoSweepGro.selector)
        );
        redemptionPool.sweep(address(GRO));
    }

    /////////////////////////////////////////////////////////////////////////////
    //                              Claim flow                                 //
    /////////////////////////////////////////////////////////////////////////////

    function testSingleUserHasAllShares(
        uint256 _depositAmnt,
        uint256 _assetAmount
    ) public {
        _depositAmnt = bound(_depositAmnt, 1e18, 100_000_000e18);
        _assetAmount = bound(_assetAmount, 1e8, 1_000_000_000e8);

        setStorage(alice, GRO.balanceOf.selector, address(GRO), _depositAmnt);
        // Approve GRO to be spent by the RedemptionPool:
        vm.prank(alice);
        GRO.approve(address(redemptionPool), _depositAmnt);

        // Deposit GRO into the RedemptionPool:
        vm.prank(alice);
        redemptionPool.deposit(_depositAmnt);

        // Pull assets from the DAO
        pullCUSDC(_assetAmount);

        // Check user's shares
        assertEq(redemptionPool.getSharesAvailable(alice), _assetAmount);

        // Check ppfs
        uint256 expectedPpfs = (_assetAmount * 1e18) / _depositAmnt;
        assertEq(redemptionPool.getPricePerShare(), expectedPpfs);

        // Roll to deadline and claim
        vm.warp(redemptionPool.DEADLINE() + 1);
        vm.startPrank(alice);
        uint256 allShares = redemptionPool.getSharesAvailable(alice);
        redemptionPool.claim(allShares);
        vm.stopPrank();
        // Convert finalClaim from CUSDC to USDC
        uint256 USDCperCUSDC = ICERC20(CUSDC).exchangeRateStored();
        uint256 finalClaimUSDC = (allShares * USDCperCUSDC) / 1e18;

        assertApproxEqAbs(USDC.balanceOf(alice), finalClaimUSDC, 1e1);
    }

    function testCantClaimIfDidntDeposit(
        uint256 _depositAmnt,
        uint256 _assetAmount
    ) public {
        _depositAmnt = bound(_depositAmnt, 1e18, 100_000_000e18);
        _assetAmount = bound(_assetAmount, 1e8, 1_000_000_000e8);

        setStorage(alice, GRO.balanceOf.selector, address(GRO), _depositAmnt);
        // Approve GRO to be spent by the RedemptionPool:
        vm.prank(alice);
        GRO.approve(address(redemptionPool), _depositAmnt);

        // Deposit GRO into the RedemptionPool:
        vm.prank(alice);
        redemptionPool.deposit(_depositAmnt);
        // Pull assets from the DAO
        pullCUSDC(_assetAmount);
        vm.warp(redemptionPool.DEADLINE() + 1);
        // Bob should be not be able to claim
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(RedemptionErrors.InvalidClaim.selector)
        );
        redemptionPool.claim(1e8);
    }

    function testCantClaimMultipleTimes(
        uint256 _depositAmnt,
        uint256 _assetAmount
    ) public {
        _depositAmnt = bound(_depositAmnt, 1e18, 100_000_000e18);
        _assetAmount = bound(_assetAmount, 1e8, 1_000_000_000e8);

        setStorage(alice, GRO.balanceOf.selector, address(GRO), _depositAmnt);
        // Approve GRO to be spent by the RedemptionPool:
        vm.prank(alice);
        GRO.approve(address(redemptionPool), _depositAmnt);

        // Deposit GRO into the RedemptionPool:
        vm.prank(alice);
        redemptionPool.deposit(_depositAmnt);
        // Pull assets from the DAO
        pullCUSDC(_assetAmount);
        vm.warp(redemptionPool.DEADLINE() + 1);
        vm.startPrank(alice);
        assertTrue(CUSDC.balanceOf(address(redemptionPool)) > 0);
        assertTrue(USDC.balanceOf(address(CUSDC)) > 0);
        redemptionPool.claim(_assetAmount);
        assertTrue(USDC.balanceOf(alice) > 0);
        assertTrue(CUSDC.balanceOf(address(redemptionPool)) == 0);
        // On second claim should revert
        vm.expectRevert(
            abi.encodeWithSelector(RedemptionErrors.InvalidClaim.selector)
        );
        redemptionPool.claim(_assetAmount);
        vm.stopPrank();
    }

    /////////////////////////////////////////////////////////////////////////////
    //                 Multiple users claiming                                 //
    /////////////////////////////////////////////////////////////////////////////

    /// @dev Advanced case scenario when there are lots of users depositing equal amounts of GRO tokens
    function testMultiUserDepositsAndClaimsNoEntropy(
        uint256 _depositAmnt,
        uint256 _assetAmount
    ) public {
        _depositAmnt = bound(_depositAmnt, 1e18, 100_000_000e18);
        _assetAmount = bound(_assetAmount, 1e8, 1_000_000_000e6);

        // Generate users:
        address payable[] memory _users = utils.createUsers(USER_COUNT);
        // Pull in assets from the DAO
        pullCUSDC(_assetAmount);
        // Give users some GRO:
        for (uint256 i = 0; i < USER_COUNT; i++) {
            setStorage(
                _users[i],
                GRO.balanceOf.selector,
                address(GRO),
                _depositAmnt
            );
            // Approve GRO to be spent by the RedemptionPool:
            vm.startPrank(_users[i]);
            GRO.approve(address(redemptionPool), _depositAmnt);
            // Deposit GRO into the RedemptionPool:
            redemptionPool.deposit(_depositAmnt);
            // Check user balance

            assertEq(
                redemptionPool.getUserBalance(_users[0]),
                _depositAmnt,
                "User Balance is off"
            );
            assertEq(
                redemptionPool.getSharesAvailable(_users[0]),
                (_depositAmnt * _assetAmount) / redemptionPool.totalGRO(),
                "Shares available is off"
            );
            vm.stopPrank();
        }

        // Checks:

        assertEq(
            GRO.balanceOf(address(redemptionPool)),
            _depositAmnt * USER_COUNT
        );
        assertEq(redemptionPool.totalGRO(), _depositAmnt * USER_COUNT);
        // Check that the total amount of CUSDC deposited is equal to the amount pulled from the DAO
        assertEq(CUSDC.balanceOf(address(redemptionPool)), _assetAmount);
        assertEq(
            redemptionPool.getPricePerShare(),
            (_assetAmount * 1e18) / redemptionPool.totalGRO()
        );

        // Warp to deadline
        vm.warp(redemptionPool.DEADLINE() + 1);
        // Withdraw for each user:
        for (uint256 i = 0; i < USER_COUNT; i++) {
            vm.startPrank(_users[i]);
            redemptionPool.claim(_assetAmount / USER_COUNT);
            assertEq(
                USDC.balanceOf(_users[i]),
                ((_assetAmount / USER_COUNT) *
                    ICERC20(CUSDC).exchangeRateStored()) / 1e18
            );
            vm.stopPrank();
        }
        // Check that all CUSDC was claimed:
        assertApproxEqAbs(CUSDC.balanceOf(address(redemptionPool)), 0, 1e3);
    }

    /// @dev Advanced case scenario when there are lots of users depositing non-equal amounts of GRO tokens
    function testMultiUserDepositsAndClaimsEntropy(
        uint256 _assetAmount
    ) public {
        _assetAmount = bound(_assetAmount, 1e8, 1_000_000_000e8);

        // Generate users:
        address payable[] memory _users = utils.createUsers(USER_COUNT);
        // Pull in assets from the DAO
        pullCUSDC(_assetAmount);

        // For each user need to generate "random" amount of GRO to deposit
        uint256 _depositAmnt;
        uint256 _totalDepositAmnt;
        uint256[] memory _deposits = new uint256[](USER_COUNT);
        for (uint256 i = 0; i < USER_COUNT; i++) {
            _deposits[i] =
                uint256(keccak256(abi.encodePacked(block.timestamp, i))) %
                1e25;
            _depositAmnt = _deposits[i];
            _totalDepositAmnt += _depositAmnt;
            vm.warp(block.timestamp + i);
            setStorage(
                _users[i],
                GRO.balanceOf.selector,
                address(GRO),
                _depositAmnt
            );

            // Approve GRO to be spent by the RedemptionPool:
            vm.startPrank(_users[i]);
            GRO.approve(address(redemptionPool), _depositAmnt);
            // Deposit GRO into the RedemptionPool:
            redemptionPool.deposit(_depositAmnt);
            // Check user balance

            assertEq(
                redemptionPool.getUserBalance(_users[i]),
                _depositAmnt,
                "User Balance is off"
            );
            assertEq(
                redemptionPool.getSharesAvailable(_users[i]),
                (_depositAmnt * _assetAmount) / redemptionPool.totalGRO(),
                "Shares available is off"
            );
            vm.stopPrank();
        }

        assertEq(
            GRO.balanceOf(address(redemptionPool)),
            _totalDepositAmnt,
            "Incorrect total GRO in contract"
        );
        assertEq(
            redemptionPool.totalGRO(),
            _totalDepositAmnt,
            "Incorrect total GRO in _totalDepositAmnt"
        );
        assertEq(
            redemptionPool.getPricePerShare(),
            (_assetAmount * 1e18) / redemptionPool.totalGRO(),
            "Incorrect price per share"
        );

        // Warp to deadline
        vm.warp(redemptionPool.DEADLINE() + 1);

        // Withdraw for each user:
        for (uint256 i = 0; i < USER_COUNT; i++) {
            vm.startPrank(_users[i]);
            redemptionPool.claim(
                (_deposits[i] * _assetAmount) / redemptionPool.totalGRO()
            );
            // Check user USDC balance is proportional to the amount of GRO deposited
            assertApproxEqAbs(
                USDC.balanceOf(_users[i]),
                (((_deposits[i] * _assetAmount) / redemptionPool.totalGRO()) *
                    ICERC20(CUSDC).exchangeRateStored()) / 1e18,
                1e1,
                "User did not get correct amount of USDC"
            );

            vm.stopPrank();
        }

        // Check that all CUSDC was claimed:
        assertApproxEqAbs(
            CUSDC.balanceOf(address(redemptionPool)),
            0,
            1e8,
            "CUSDC balance is not 0"
        );
    }

    /// @dev Advanced case scenario when there are lots of users depositing non-equal amounts of GRO tokens
    function testMultiUserDepositsAndClaimsEntropyWithDAOTopUps(
        uint256 _assetAmount
    ) public {
        _assetAmount = bound(_assetAmount, 1e8, 1_000_000_000e8);

        // Generate users:
        address payable[] memory _users = utils.createUsers(USER_COUNT);

        // Pull in assets from the DAO
        pullCUSDC(_assetAmount);

        // For each user need to generate "random" amount of GRO to deposit
        uint256 _depositAmnt;
        uint256 _totalDepositAmnt;
        uint256[] memory _deposits = new uint256[](USER_COUNT);
        for (uint256 i = 0; i < USER_COUNT; i++) {
            _deposits[i] =
                uint256(keccak256(abi.encodePacked(block.timestamp, i))) %
                1e25;
            _depositAmnt = _deposits[i];
            _totalDepositAmnt += _depositAmnt;
            vm.warp(block.timestamp + i);
            setStorage(
                _users[i],
                GRO.balanceOf.selector,
                address(GRO),
                _depositAmnt
            );
            // Approve GRO to be spent by the RedemptionPool:
            vm.startPrank(_users[i]);
            GRO.approve(address(redemptionPool), _depositAmnt);
            // Deposit GRO into the RedemptionPool:
            redemptionPool.deposit(_depositAmnt);
            // Check user balance
            assertEq(
                redemptionPool.getUserBalance(_users[i]),
                _depositAmnt,
                "User Balance is off"
            );
            assertEq(
                redemptionPool.getSharesAvailable(_users[i]),
                (_depositAmnt * _assetAmount) / redemptionPool.totalGRO(),
                "Shares available is off"
            );
            vm.stopPrank();
        }

        assertEq(GRO.balanceOf(address(redemptionPool)), _totalDepositAmnt);
        assertEq(redemptionPool.totalGRO(), _totalDepositAmnt);
        assertEq(
            redemptionPool.getPricePerShare(),
            (_assetAmount * 1e18) / redemptionPool.totalGRO()
        );
        // Warp to deadline
        vm.warp(redemptionPool.DEADLINE() + 1);

        // Withdraw for each user:
        for (uint256 i = 0; i < USER_COUNT / 2; i++) {
            vm.startPrank(_users[i]);
            redemptionPool.claim(
                (_deposits[i] * _assetAmount) / redemptionPool.totalGRO()
            );
            // Check user USDC balance is proportional to the amount of GRO deposited
            assertApproxEqAbs(
                USDC.balanceOf(_users[i]),
                (((_deposits[i] * _assetAmount) / redemptionPool.totalGRO()) *
                    ICERC20(CUSDC).exchangeRateStored()) / 1e18,
                1e2,
                "User did not get correct amount of USDC in first claim"
            );

            vm.stopPrank();
        }
        // DAO adds more CUSDC after users claim
        pullCUSDC(_assetAmount);
        // Withdraw for each user:
        for (uint256 i = 0; i < USER_COUNT; i++) {
            vm.startPrank(_users[i]);
            redemptionPool.claim(redemptionPool.getSharesAvailable(_users[i]));

            // Add the first round claims to the calculated claims for this round
            uint256 totalExpectedUSDC = (((_deposits[i] * _assetAmount * 2) /
                redemptionPool.totalGRO()) *
                ICERC20(CUSDC).exchangeRateStored()) / 1e18;

            // Check user USDC balance is proportional to the amount of GRO deposited
            assertApproxEqAbs(
                USDC.balanceOf(_users[i]),
                totalExpectedUSDC,
                1e8,
                "User did not get correct amount of USDC in second claim"
            );
            vm.stopPrank();
        }
        // Check that all CUSDC was claimed:
        assertApproxEqAbs(
            CUSDC.balanceOf(address(redemptionPool)),
            0,
            1e8,
            "CUSDC balance is not 0"
        );
    }
    /////////////////////////////////////////////////////////////////////////////
    //                 Transfer position tests                                 //
    /////////////////////////////////////////////////////////////////////////////

    function testTransferPosition(uint256 _depositAmnt, uint256 _assetAmount) public {
        _depositAmnt = bound(_depositAmnt, 1e18, 100_000_000e18);
        _assetAmount = bound(_assetAmount, 1e8, 1_000_000_000e8);

        // Pull in assets from the DAO
        pullCUSDC(_assetAmount);

        // Give user some GRO:
        setStorage(alice, GRO.balanceOf.selector, address(GRO), _depositAmnt);

        // Approve GRO to be spent by the RedemptionPool:
        vm.prank(alice);
        GRO.approve(address(redemptionPool), _depositAmnt);

        // Deposit GRO into the RedemptionPool:
        vm.prank(alice);
        redemptionPool.deposit(_depositAmnt);

        // Check user balance
        uint256 aliceBalance = redemptionPool.getUserBalance(alice);
        assertEq(aliceBalance, _depositAmnt);

        // Now, alice wants to transfer her position to bob
        vm.prank(alice);
        redemptionPool.transferPosition(bob, aliceBalance);

        // Make sure alice has no balance
        assertEq(redemptionPool.getUserBalance(alice), 0);
        // Make sure bob has the balance
        assertEq(redemptionPool.getUserBalance(bob), aliceBalance);
    }

    function testTransferPositionUnhappy(uint256 _depositAmnt, uint256 _assetAmount) public {
        _depositAmnt = bound(_depositAmnt, 1e18, 100_000_000e18);
        _assetAmount = bound(_assetAmount, 1e8, 1_000_000_000e8);

        // Pull in assets from the DAO
        pullCUSDC(_assetAmount);

        // Give user some GRO:
        setStorage(alice, GRO.balanceOf.selector, address(GRO), _depositAmnt);

        // Approve GRO to be spent by the RedemptionPool:
        vm.prank(alice);
        GRO.approve(address(redemptionPool), _depositAmnt);

        // Deposit GRO into the RedemptionPool:
        vm.prank(alice);
        redemptionPool.deposit(_depositAmnt);

        // Alice tries to transfer more than she has
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(RedemptionErrors.InsufficientBalance.selector));
        redemptionPool.transferPosition(bob, _depositAmnt + 1);
        vm.stopPrank();
    }
}
