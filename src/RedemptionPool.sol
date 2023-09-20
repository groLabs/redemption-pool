// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {RedemptionErrors} from "./Errors.sol";

contract RedemptionPool is Ownable {
    using SafeERC20 for ERC20;
    /////////////////////////////////////////////////////////////////////////////
    //                                  Constants                              //
    /////////////////////////////////////////////////////////////////////////////

    address public constant OWNER = address(1337);
    uint256 public constant DURATION = 30 days;
    ERC20 public constant GRO = ERC20(address(0x3Ec8798B81485A254928B70CDA1cf0A2BB0B74D7));
    /////////////////////////////////////////////////////////////////////////////
    //                                  Storage                                //
    /////////////////////////////////////////////////////////////////////////////
    uint256 public immutable deadline;
    mapping(address => uint256) private _balances;
    uint256 public totalDeposited;

    /////////////////////////////////////////////////////////////////////////////
    //                                  Events                                 //
    /////////////////////////////////////////////////////////////////////////////
    event Deposit(address indexed user, uint256 amount);

    constructor() Ownable() {
        _transferOwnership(OWNER);
        // Sets the deadline to 30 days from now
        deadline = block.timestamp + DURATION;
    }

    function deposit(uint256 _amount) external {
        // Checks that the deadline has not passed
        if (block.timestamp > deadline) {
            revert RedemptionErrors.DeadlineExceeded();
        }
        // Transfers the GRO tokens from the sender to this contract
        GRO.safeTransferFrom(msg.sender, address(this), _amount);
        // Increases the balance of the sender by the amount
        _balances[msg.sender] += _amount;
        // Increases the total deposited by the amount
        totalDeposited += _amount;
        // Emits the Deposit event
        emit Deposit(msg.sender, _amount);
    }
}
