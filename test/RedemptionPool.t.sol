// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./BaseFixture.sol";
import {RedemptionErrors} from "../src/Errors.sol";

contract TestRedemptionPool is BaseFixture {
    uint256 public constant USER_COUNT = 10;

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
        vm.assume(_depositAmnt > 1e18);
        vm.assume(_depositAmnt < 100_000_000_000e18);
        vm.assume(_assetAmount > 1e8);
        vm.assume(_assetAmount < 100_000_000e8);

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
        vm.prank(alice);
        uint256 finalClaim = uint256(
            keccak256(abi.encodePacked(block.timestamp, block.prevrandao))
        ) % _assetAmount;
        redemptionPool.claim(finalClaim);

        // Convert finalClaim from CUSDC to USDC
        uint256 USDCperCUSDC = ICERC20(CUSDC).exchangeRateStored();
        uint256 finalClaimUSDC = (finalClaim * USDCperCUSDC) / 1e8;

        assertEq(USDC.balanceOf(alice), finalClaimUSDC);
    }

    function testCantClaimIfDidntDeposit(
        uint256 _depositAmnt,
        uint256 _assetAmount
    ) public {
        vm.assume(_depositAmnt > 1e18);
        vm.assume(_depositAmnt < 100_000_000_000e18);
        vm.assume(_assetAmount > 1e8);
        vm.assume(_assetAmount < 100_000_000e8);
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
            abi.encodeWithSelector(
                RedemptionErrors.InsufficientBalance.selector
            )
        );
        redemptionPool.claim(1e8);
    }

    function testCantClaimMultipleTimes(
        uint256 _depositAmnt,
        uint256 _assetAmount
    ) public {
        vm.assume(_depositAmnt > 1e18);
        vm.assume(_depositAmnt < 100_000_000_000e18);
        vm.assume(_assetAmount > 1e8);
        vm.assume(_assetAmount < 100_000_000e8);
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
        assertTrue(
            CUSDC.balanceOf(address(redemptionPool)) > 0,
            "Contract has no CUSDC"
        );
        assertTrue(USDC.balanceOf(address(CUSDC)) > 0, "CUSDC has no USDC");
        console.log(
            "USDC balance of CUSDC: %s",
            USDC.balanceOf(address(CUSDC))
        );
        console.log(
            "CUSDC balance of RedemptionPool: %s",
            CUSDC.balanceOf(address(redemptionPool))
        );
        console.log(
            "redemptionPool's CUSDC converted into USDC: %s",
            (CUSDC.balanceOf(address(redemptionPool)) *
                ICERC20(CUSDC).exchangeRateStored()) / 1e20
        );
        console.log(
            "_assetAmount CUSDC converted into USDC: %s",
            (_assetAmount * ICERC20(CUSDC).exchangeRateStored()) / 1e20
        );
        console.log(
            "alice's getSharesAvailable in redemptionpool",
            redemptionPool.getSharesAvailable(alice)
        );
        redemptionPool.claim(_assetAmount);
        assertTrue(USDC.balanceOf(alice) > 0, "Alice didn't get any USDC");
        // On second claim should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                RedemptionErrors.InsufficientBalance.selector
            )
        );
        redemptionPool.claim(_assetAmount);
        vm.stopPrank();
    }

    /////////////////////////////////////////////////////////////////////////////
    //                 Multiple users claiming                                 //
    /////////////////////////////////////////////////////////////////////////////

    /// @dev Advanced case scenario when there are lots of users depositing equal amounts of GRO tokens
    function testMultiUserDepositsAndClaims(
        uint256 _depositAmnt,
        uint256 _assetAmount
    ) public {
        vm.assume(_depositAmnt > 1e18);
        vm.assume(_depositAmnt < 100_000_000_000e18);
        vm.assume(_assetAmount > 1e8);
        vm.assume(_assetAmount < 100_000_000_000e8);

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
            _depositAmnt * USER_COUNT,
            "Incorrect total GRO in contract"
        );
        assertEq(
            redemptionPool.totalGRO(),
            _depositAmnt * USER_COUNT,
            "Incorrect total GRO in totalGRO variable"
        );
        // Check that the total amount of CUSDC deposited is equal to the amount pulled from the DAO
        assertEq(
            CUSDC.balanceOf(address(redemptionPool)),
            _assetAmount,
            "Incorrect total CUSDC amounts"
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
            console.log("User %s", _users[i]);
            redemptionPool.claim(_assetAmount / USER_COUNT);
            // Check user CUSDC balance:
            assertEq(
                USDC.balanceOf(_users[i]),
                ((_assetAmount / USER_COUNT) *
                    ICERC20(CUSDC).exchangeRateStored()) / 1e20
            );
            vm.stopPrank();
        }
        // Check that all CUSDC was claimed:
        assertApproxEqAbs(
            CUSDC.balanceOf(address(redemptionPool)),
            0,
            1e1,
            "CUSDC balance is not 0"
        );
    }

    /// @dev Advanced case scenario when there are lots of users depositing non-equal amounts of GRO tokens
    function testMultiUserDepositsAndClaimsEntropy(
        uint256 _assetAmount
    ) public {
        vm.assume(_assetAmount > 1e8);
        vm.assume(_assetAmount < 100_000_000e8);

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
            assertEq(redemptionPool.getUserBalance(_users[i]), _depositAmnt);
            assertEq(
                redemptionPool.getSharesAvailable(_users[i]),
                (_depositAmnt * _assetAmount) / redemptionPool.totalGRO()
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
        for (uint256 i = 0; i < USER_COUNT; i++) {
            vm.startPrank(_users[i]);
            redemptionPool.claim(
                (_deposits[i] * _assetAmount) / redemptionPool.totalGRO()
            );
            // Check user CUSDC balance is proportional to the amount of GRO deposited
            assertEq(
                CUSDC.balanceOf(_users[i]),
                (_deposits[i] * _assetAmount) / redemptionPool.totalGRO()
            );
            vm.stopPrank();
        }

        // Check that all CUSDC was claimed:
        assertApproxEqAbs(CUSDC.balanceOf(address(redemptionPool)), 0, 1e1);
    }
}
