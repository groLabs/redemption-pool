// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./BaseFixture.sol";
import {RedemptionErrors} from "../src/Errors.sol";
import "../src/RedemptionPoolAlloyx.sol";

contract TestRedemptionPool is BaseFixture {
    uint256 public constant USER_COUNT = 5;
    RedemptionPoolAlloyX public redemptionPoolAlloyX;
    ERC20 public constant ALLOYX = ERC20(0x4562724cAa90d866c35855b9baF71E5125CAD5B6);

    function setUp() public override {
        super.setUp();
        redemptionPoolAlloyX = new RedemptionPoolAlloyX();
    }

    function pullAlloyx(uint256 _amount) internal {
        setStorage(DAO, ALLOYX.balanceOf.selector, address(ALLOYX), type(uint256).max);
        vm.startPrank(DAO);
        ALLOYX.approve(address(redemptionPoolAlloyX), _amount);
        redemptionPoolAlloyX.depositAlloy(_amount);
        vm.stopPrank();
    }

    /////////////////////////////////////////////////////////////////////////////
    //                              Basic functionality                        //
    /////////////////////////////////////////////////////////////////////////////
    /// @dev Basic test to check that the deposit function works
    function testDepositHappyAlloyx(uint256 _depositAmnt) public {
        _depositAmnt = bound(_depositAmnt, 1e18, 100_000e18);
        // Give user some GRO:
        setStorage(alice, GRO.balanceOf.selector, address(GRO), _depositAmnt);
        // Approve GRO to be spent by the RedemptionPool:
        vm.prank(alice);
        GRO.approve(address(redemptionPoolAlloyX), _depositAmnt);

        // Deposit GRO into the RedemptionPool:
        vm.prank(alice);
        redemptionPoolAlloyX.deposit(_depositAmnt);
        // Checks:
        assertEq(GRO.balanceOf(address(redemptionPoolAlloyX)), _depositAmnt);
        assertEq(GRO.balanceOf(alice), 0);

        assertEq(redemptionPoolAlloyX.totalGRO(), _depositAmnt);

        assertEq(redemptionPoolAlloyX.getUserBalance(alice), _depositAmnt);
    }

    /// @dev test cannot deposit after deadline
    function testDepositUnhappyDeadlineAlloyx(uint256 _depositAmnt) public {
        _depositAmnt = bound(_depositAmnt, 1e18, 100_000e18);
        setStorage(alice, GRO.balanceOf.selector, address(GRO), _depositAmnt);
        // Approve GRO to be spent by the RedemptionPool:
        vm.prank(alice);
        GRO.approve(address(redemptionPoolAlloyX), _depositAmnt);
        vm.warp(redemptionPoolAlloyX.DEADLINE() + 1);
        // Deposit GRO into the RedemptionPool:
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(RedemptionErrors.DeadlineExceeded.selector));
        redemptionPoolAlloyX.deposit(_depositAmnt);
        vm.stopPrank();
    }

    /// @dev test can withdraw after deposit
    function testWithdrawHappyAlloyx(uint256 _depositAmnt) public {
        _depositAmnt = bound(_depositAmnt, 1e18, 100_000e18);
        setStorage(alice, GRO.balanceOf.selector, address(GRO), _depositAmnt);
        // Approve GRO to be spent by the RedemptionPool:
        vm.prank(alice);
        GRO.approve(address(redemptionPoolAlloyX), _depositAmnt);

        // Deposit GRO into the RedemptionPool:
        vm.prank(alice);
        redemptionPoolAlloyX.deposit(_depositAmnt);

        // Withdraw before deadline:
        vm.prank(alice);
        redemptionPoolAlloyX.withdraw(_depositAmnt);
        // Checks:
        assertEq(GRO.balanceOf(address(redemptionPoolAlloyX)), 0);
        assertEq(GRO.balanceOf(alice), _depositAmnt);
        assertEq(redemptionPoolAlloyX.getUserBalance(alice), 0);
    }

    /// @dev test cannot withdraw after deadline
    function testWithdrawUnhappyDeadlineAlloyx(uint256 _depositAmnt) public {
        _depositAmnt = bound(_depositAmnt, 1e18, 100_000e18);
        setStorage(alice, GRO.balanceOf.selector, address(GRO), _depositAmnt);
        vm.prank(alice);
        GRO.approve(address(redemptionPoolAlloyX), _depositAmnt);

        // Deposit GRO into the RedemptionPool:
        vm.prank(alice);
        redemptionPoolAlloyX.deposit(_depositAmnt);
        vm.warp(redemptionPoolAlloyX.DEADLINE() + 1);
        // Withdraw after deadline:
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(RedemptionErrors.DeadlineExceeded.selector));
        redemptionPoolAlloyX.withdraw(_depositAmnt);
        vm.stopPrank();
    }

    function testPullAlloyx(uint256 _amount) public {
        _amount = bound(_amount, 1e18, 100_000_000e18);

        pullAlloyx(_amount);

        assertEq(ALLOYX.balanceOf(address(redemptionPoolAlloyX)), _amount);
    }

    /// @dev Test sweeping Alloyx
    function testSweepAlloyx(uint256 _amount) public {
        _amount = bound(_amount, 1e18, 100_000_000e18);

        pullAlloyx(_amount);
        // Snapshot balance
        uint256 snapshot = ALLOYX.balanceOf(address(DAO));
        // Sweep to DAO
        vm.prank(DAO);
        redemptionPoolAlloyX.sweep(address(ALLOYX));

        assertEq(ALLOYX.balanceOf(address(redemptionPoolAlloyX)), 0);
        assertEq(ALLOYX.balanceOf(DAO), snapshot + _amount);
    }

    function testCantSweepGRO() public {
        vm.prank(DAO);
        vm.expectRevert(abi.encodeWithSelector(RedemptionErrors.NoSweepGro.selector));
        redemptionPoolAlloyX.sweep(address(GRO));
    }

    /////////////////////////////////////////////////////////////////////////////
    //                              Claim flow                                 //
    /////////////////////////////////////////////////////////////////////////////
    function testSingleUserHasAllSharesAlloyx(uint256 _depositAmnt, uint256 _assetAmount) public {
        _depositAmnt = bound(_depositAmnt, 1e18, 100_000_000e18);
        _assetAmount = bound(_assetAmount, 1e18, 1_000_000_000e18);

        setStorage(alice, GRO.balanceOf.selector, address(GRO), _depositAmnt);
        // Approve GRO to be spent by the RedemptionPool:
        vm.prank(alice);
        GRO.approve(address(redemptionPoolAlloyX), _depositAmnt);

        vm.prank(alice);
        redemptionPoolAlloyX.deposit(_depositAmnt);

        // Pull assets from the DAO
        pullAlloyx(_assetAmount);

        // Test ALLOYX per GRO:
        assertEq(redemptionPoolAlloyX.getDURAPerGRO(), _assetAmount * 1e18 / _depositAmnt);
        // Check user's shares
        assertEq(redemptionPoolAlloyX.getDuraAvailable(alice), _assetAmount);

        // Check ppfs
        uint256 expectedPpfs = (_assetAmount * 1e18) / _depositAmnt;
        assertEq(redemptionPoolAlloyX.getDURAPerGRO(), expectedPpfs);

        // Roll to deadline and claim
        vm.warp(redemptionPoolAlloyX.DEADLINE() + 1);

        // Check that user shares == amount of ALLOYX in the pool
        assertEq(redemptionPoolAlloyX.getDuraAvailable(alice), _assetAmount);
        vm.startPrank(alice);
        uint256 allShares = redemptionPoolAlloyX.getDuraAvailable(alice);
        redemptionPoolAlloyX.claim(allShares);
        vm.stopPrank();

        assertApproxEqAbs(ALLOYX.balanceOf(alice), _assetAmount, 1e18);
    }

    function testCantClaimIfDidntDepositAlloyx(uint256 _depositAmnt, uint256 _assetAmount) public {
        _depositAmnt = bound(_depositAmnt, 1e18, 100_000_000e18);
        _assetAmount = bound(_assetAmount, 1e18, 1_000_000_000e18);

        setStorage(alice, GRO.balanceOf.selector, address(GRO), _depositAmnt);
        vm.prank(alice);
        GRO.approve(address(redemptionPoolAlloyX), _depositAmnt);

        // Deposit GRO into the RedemptionPool:
        vm.prank(alice);
        redemptionPoolAlloyX.deposit(_depositAmnt);
        // Pull assets from the DAO
        pullAlloyx(_assetAmount);
        vm.warp(redemptionPoolAlloyX.DEADLINE() + 1);
        // Bob should be not be able to claim
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(RedemptionErrors.InvalidClaim.selector));
        redemptionPoolAlloyX.claim(1e1);
    }

    function testCantClaimMultipleTimes(uint256 _depositAmnt, uint256 _assetAmount) public {
        _depositAmnt = bound(_depositAmnt, 1e18, 100_000_000e18);
        _assetAmount = bound(_assetAmount, 1e18, 1_000_000_000e18);

        setStorage(alice, GRO.balanceOf.selector, address(GRO), _depositAmnt);
        vm.prank(alice);
        GRO.approve(address(redemptionPoolAlloyX), _depositAmnt);

        // Deposit GRO into the RedemptionPool:
        vm.prank(alice);
        redemptionPoolAlloyX.deposit(_depositAmnt);
        // Pull assets from the DAO
        pullAlloyx(_assetAmount);
        vm.warp(redemptionPoolAlloyX.DEADLINE() + 1);
        vm.startPrank(alice);
        redemptionPoolAlloyX.claim(_assetAmount);
        assertTrue(ALLOYX.balanceOf(address(redemptionPoolAlloyX)) == 0);
        // On second claim should revert
        vm.expectRevert(abi.encodeWithSelector(RedemptionErrors.InvalidClaim.selector));
        redemptionPoolAlloyX.claim(_assetAmount);
        vm.stopPrank();
    }
    /////////////////////////////////////////////////////////////////////////////
    //                 Multiple users claiming                                 //
    /////////////////////////////////////////////////////////////////////////////

    /// @dev Advanced case scenario when there are lots of users depositing equal amounts of GRO tokens
    function testMultiUserDepositsAndClaimsNoEntropyAlloyx(uint256 _depositAmnt, uint256 _assetAmount) public {
        _depositAmnt = bound(_depositAmnt, 1e18, 100_000_000e18);
        _assetAmount = bound(_assetAmount, 1e18, 1_000_000_000e18);

        // Generate users:
        address payable[] memory _users = utils.createUsers(USER_COUNT);
        // Pull in assets from the DAO
        pullAlloyx(_assetAmount);
        // Give users some GRO:
        for (uint256 i = 0; i < USER_COUNT; i++) {
            setStorage(_users[i], GRO.balanceOf.selector, address(GRO), _depositAmnt);
            // Approve GRO to be spent by the RedemptionPool:
            vm.startPrank(_users[i]);
            GRO.approve(address(redemptionPoolAlloyX), _depositAmnt);
            // Deposit GRO into the RedemptionPool:
            redemptionPoolAlloyX.deposit(_depositAmnt);
            // Check user balance

            assertApproxEqAbs(redemptionPoolAlloyX.getUserBalance(_users[i]), _depositAmnt, 1e1);
            assertEq(
                redemptionPoolAlloyX.getDuraAvailable(_users[i]),
                (_depositAmnt * _assetAmount) / redemptionPoolAlloyX.totalGRO()
            );

            vm.stopPrank();
        }
        assertEq(GRO.balanceOf(address(redemptionPoolAlloyX)), _depositAmnt * USER_COUNT);
        assertEq(redemptionPoolAlloyX.totalGRO(), _depositAmnt * USER_COUNT);
        // Check that the total amount of CUSDC deposited is equal to the amount pulled from the DAO
        assertEq(ALLOYX.balanceOf(address(redemptionPoolAlloyX)), _assetAmount);
        assertEq(redemptionPoolAlloyX.getDURAPerGRO(), (_assetAmount * 1e18) / redemptionPoolAlloyX.totalGRO());

        // Warp to deadline
        vm.warp(redemptionPoolAlloyX.DEADLINE() + 1);
        // Withdraw for each user:
        for (uint256 i = 0; i < USER_COUNT; i++) {
            vm.startPrank(_users[i]);
            redemptionPoolAlloyX.claim(_assetAmount / USER_COUNT);
            console2.log("Asset amount", _assetAmount);
            assertEq(ALLOYX.balanceOf(_users[i]), _assetAmount / USER_COUNT);
            vm.stopPrank();
        }
        // Check that all ALLOYX was claimed:
        assertApproxEqAbs(ALLOYX.balanceOf(address(redemptionPoolAlloyX)), 0, 1e3);
    }

    /// @dev Advanced case scenario when there are lots of users depositing non-equal amounts of GRO tokens
    function testMultiUserDepositsAndClaimsEntropyAlloyx(uint256 _assetAmount) public {
        _assetAmount = bound(_assetAmount, 1e18, 1_000_000_000e18);

        // Generate users:
        address payable[] memory _users = utils.createUsers(USER_COUNT);
        // Pull in assets from the DAO
        pullAlloyx(_assetAmount);

        // For each user need to generate "random" amount of GRO to deposit
        uint256 _depositAmnt;
        uint256 _totalDepositAmnt;
        uint256[] memory _deposits = new uint256[](USER_COUNT);
        for (uint256 i = 0; i < USER_COUNT; i++) {
            _deposits[i] = uint256(keccak256(abi.encodePacked(block.timestamp, i))) % 1e25;
            _depositAmnt = _deposits[i];
            _totalDepositAmnt += _depositAmnt;
            vm.warp(block.timestamp + i);
            setStorage(_users[i], GRO.balanceOf.selector, address(GRO), _depositAmnt);

            // Approve GRO to be spent by the RedemptionPool:
            vm.startPrank(_users[i]);
            GRO.approve(address(redemptionPoolAlloyX), _depositAmnt);
            // Deposit GRO into the RedemptionPool:
            redemptionPoolAlloyX.deposit(_depositAmnt);
            // Check user balance

            assertEq(redemptionPoolAlloyX.getUserBalance(_users[i]), _depositAmnt);
            assertEq(
                redemptionPoolAlloyX.getDuraAvailable(_users[i]),
                (_depositAmnt * _assetAmount) / redemptionPoolAlloyX.totalGRO()
            );
            vm.stopPrank();
        }
        // Check that Alloy amount shares are proportional to the amount of GRO deposited
        for (uint256 i = 0; i < USER_COUNT; i++) {
            uint256 approxAlloy = (_deposits[i] * _assetAmount) / _totalDepositAmnt;
            assertEq(redemptionPoolAlloyX.getDuraAvailable(_users[i]), approxAlloy);
        }
        assertEq(GRO.balanceOf(address(redemptionPoolAlloyX)), _totalDepositAmnt, "Incorrect total GRO in contract");
        assertEq(redemptionPoolAlloyX.totalGRO(), _totalDepositAmnt, "Incorrect total GRO in _totalDepositAmnt");
        assertEq(
            redemptionPoolAlloyX.getDURAPerGRO(),
            (_assetAmount * 1e18) / redemptionPoolAlloyX.totalGRO(),
            "Incorrect price per share"
        );

        // Warp to deadline
        vm.warp(redemptionPoolAlloyX.DEADLINE() + 1);

        // Withdraw for each user:
        for (uint256 i = 0; i < USER_COUNT; i++) {
            vm.startPrank(_users[i]);
            redemptionPoolAlloyX.claim((_deposits[i] * _assetAmount) / redemptionPoolAlloyX.totalGRO());
            // Check user GRO balance is proportional to the amount of GRO deposited
            assertApproxEqAbs(
                ALLOYX.balanceOf(_users[i]), (_deposits[i] * _assetAmount) / redemptionPoolAlloyX.totalGRO(), 1e1
            );

            vm.stopPrank();
        }

        // Check that all Alloyx was claimed:
        assertApproxEqAbs(ALLOYX.balanceOf(address(redemptionPoolAlloyX)), 0, 1e18, "CUSDC balance is not 0");
    }
}
