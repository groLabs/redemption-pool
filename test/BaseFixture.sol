// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import "./utils.sol";
import "../src/RedemptionPool.sol";

contract BaseFixture is Test {
    using stdStorage for StdStorage;

    ERC20 public constant GRO =
        ERC20(0x3Ec8798B81485A254928B70CDA1cf0A2BB0B74D7);
    ICERC20 public constant CUSDC =
        ICERC20(0x39AA39c021dfbaE8faC545936693aC917d5E7563);
    ERC20 public constant USDC =
        ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address public constant DAO =
        address(0x359F4fe841f246a095a82cb26F5819E10a91fe0d);

    Utils internal utils;

    address payable[] internal users;
    address internal alice;
    address internal bob;

    RedemptionPool public redemptionPool;

    function setUp() public virtual {
        vm.createSelectFork("mainnet", 18177216);
        utils = new Utils();
        users = utils.createUsers(10);

        alice = users[0];
        vm.label(alice, "Alice");
        bob = users[1];
        vm.label(bob, "Bob");

        redemptionPool = new RedemptionPool();
    }

    function setStorage(
        address _user,
        bytes4 _selector,
        address _contract,
        uint256 value
    ) public {
        uint256 slot = stdstore
            .target(_contract)
            .sig(_selector)
            .with_key(_user)
            .find();
        vm.store(_contract, bytes32(slot), bytes32(value));
    }

    /// @dev Helper function to
    function pullCUSDC(uint256 amount) public {
        setStorage(
            DAO,
            CUSDC.balanceOf.selector,
            address(CUSDC),
            type(uint96).max
        );
        vm.startPrank(DAO);
        CUSDC.approve(address(redemptionPool), amount);
        redemptionPool.depositCUSDC(amount);
        vm.stopPrank();
    }
}
