// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import "./utils.sol";

contract BaseFixture is Test {
    using stdStorage for StdStorage;

    ERC20 public constant GRO = ERC20(0x3Ec8798B81485A254928B70CDA1cf0A2BB0B74D7);
    ERC20 public constant CUSDC = ERC20(0x39AA39c021dfbaE8faC545936693aC917d5E7563);

    Utils internal utils;

    address payable[] internal users;
    address internal alice;
    address internal bob;

    function setUp() public virtual {
        utils = new Utils();
        users = utils.createUsers(2);

        alice = users[0];
        vm.label(alice, "Alice");
        bob = users[1];
        vm.label(bob, "Bob");
    }
}
