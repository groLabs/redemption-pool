// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./BaseFixture.sol";
import {RedemptionErrors} from "../src/Errors.sol";

contract TestRedemptionPool is BaseFixture {
    uint256 public constant USER_COUNT = 10;
    uint256 public constant TWENTY_PRECISION = 1e20;

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
        assertEq(
            redemptionPool.getSharesAvailable(alice),
            _assetAmount,
            "User shares are off"
        );

        // Check ppfs
        uint256 expectedPpfs = (_assetAmount * 1e18) / _depositAmnt;
        assertEq(
            redemptionPool.getPricePerShare(),
            expectedPpfs,
            "Price per share is off"
        );

        // Roll to deadline and claim
        vm.warp(redemptionPool.DEADLINE() + 1);
        vm.prank(alice);
        uint256 finalClaim = uint256(
            keccak256(abi.encodePacked(block.timestamp, block.prevrandao))
        ) % _assetAmount;
        redemptionPool.claim(finalClaim);

        // Convert finalClaim from CUSDC to USDC
        uint256 USDCperCUSDC = ICERC20(CUSDC).exchangeRateStored();
        console2.log("finalClaim: %s", finalClaim);
        uint256 finalClaimUSDC = (finalClaim * USDCperCUSDC) / TWENTY_PRECISION;
        console2.log("finalClaimUSDC: %s", finalClaimUSDC);
        console2.log("USDC in alice' wallet: %s", USDC.balanceOf(alice));

        assertEq(
            USDC.balanceOf(alice),
            finalClaimUSDC,
            "User did not get correct amount of USDC"
        );
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
        assertTrue(
            CUSDC.balanceOf(address(redemptionPool)) > 0,
            "Contract has no CUSDC"
        );
        assertTrue(USDC.balanceOf(address(CUSDC)) > 0, "CUSDC has no USDC");
        console2.log(
            "USDC balance of CUSDC: %s",
            USDC.balanceOf(address(CUSDC))
        );
        console2.log(
            "CUSDC balance of RedemptionPool: %s",
            CUSDC.balanceOf(address(redemptionPool))
        );
        console2.log(
            "redemptionPool's CUSDC converted into USDC: %s",
            (CUSDC.balanceOf(address(redemptionPool)) *
                ICERC20(CUSDC).exchangeRateStored()) / TWENTY_PRECISION
        );
        console2.log(
            "_assetAmount CUSDC converted into USDC: %s",
            (_assetAmount * ICERC20(CUSDC).exchangeRateStored()) /
                TWENTY_PRECISION
        );
        console2.log(
            "alice's getSharesAvailable in redemptionpool",
            redemptionPool.getSharesAvailable(alice)
        );
        redemptionPool.claim(_assetAmount);
        assertTrue(USDC.balanceOf(alice) > 0, "Alice didn't get any USDC");
        assertTrue(
            CUSDC.balanceOf(address(redemptionPool)) == 0,
            "Contract still has CUSDC"
        );
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
        _depositAmnt = bound(_depositAmnt, 1e18, 100_000_000e18);
        _assetAmount = bound(_assetAmount, 1e8, 1_000_000_000e8);

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
        console2.log(
            "CUSDC in redemptionPool before claims: %s with %s claim amount",
            CUSDC.balanceOf(address(redemptionPool)),
            _assetAmount / USER_COUNT
        );
        console2.log(
            "redemptionPool has %s totalCUSDCDeposited",
            redemptionPool.totalCUSDCDeposited()
        );
        // Withdraw for each user:
        for (uint256 i = 0; i < USER_COUNT; i++) {
            vm.startPrank(_users[i]);
            console2.log(
                "User %s has %s shares and %s GRO balance in redemptionPool",
                i,
                redemptionPool.getSharesAvailable(_users[i]),
                redemptionPool.getUserBalance(_users[i])
            );
            redemptionPool.claim(_assetAmount / USER_COUNT);
            console2.log(
                "User %s claimed %s USDC and now has %s shares in redemptionPool",
                i,
                USDC.balanceOf(_users[i]),
                redemptionPool.getSharesAvailable(_users[i])
            );
            console2.log(
                "%s CUSDC in redemptionPool with %s outstanding claims",
                CUSDC.balanceOf(address(redemptionPool)),
                (USER_COUNT - i) * (_assetAmount / USER_COUNT)
            );
            console2.log(
                "USDC in redemptionPool: %s",
                USDC.balanceOf(address(redemptionPool))
            );
            console2.log(
                "USDC/CUSDC exchange rate %s",
                ICERC20(CUSDC).exchangeRateStored()
            );

            // Check user CUSDC balance:
            assertApproxEqAbs(
                USDC.balanceOf(_users[i]),
                ((_assetAmount / USER_COUNT) *
                    ICERC20(CUSDC).exchangeRateStored()) / TWENTY_PRECISION,
                1e1,
                "User did not get correct amount of USDC"
            );
            vm.stopPrank();
        }
        // Check that all CUSDC was claimed:
        assertApproxEqAbs(
            CUSDC.balanceOf(address(redemptionPool)),
            0,
            1e3,
            "CUSDC balance is not 0"
        );
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
                    ICERC20(CUSDC).exchangeRateStored()) / TWENTY_PRECISION,
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
        for (uint256 i = 0; i < USER_COUNT / 2; i++) {
            vm.startPrank(_users[i]);
            redemptionPool.claim(
                (_deposits[i] * _assetAmount) / redemptionPool.totalGRO()
            );
            // Check user USDC balance is proportional to the amount of GRO deposited
            assertApproxEqAbs(
                USDC.balanceOf(_users[i]),
                (((_deposits[i] * _assetAmount) / redemptionPool.totalGRO()) *
                    ICERC20(CUSDC).exchangeRateStored()) / TWENTY_PRECISION,
                1e1,
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
                ICERC20(CUSDC).exchangeRateStored()) / TWENTY_PRECISION;

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
}
