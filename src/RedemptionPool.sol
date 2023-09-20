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
    uint256 public constant BIPS = 10_000;
    ERC20 public constant GRO = ERC20(address(0x3Ec8798B81485A254928B70CDA1cf0A2BB0B74D7));
    // CUSDC
    ERC20 public constant ASSET = ERC20(address(0x39AA39c021dfbaE8faC545936693aC917d5E7563));
    /////////////////////////////////////////////////////////////////////////////
    //                                  Storage                                //
    /////////////////////////////////////////////////////////////////////////////
    uint256 public immutable deadline;
    mapping(address => uint256) private _balances;
    uint256 public totalDeposited;
    uint256 public totalAssets;
    /////////////////////////////////////////////////////////////////////////////
    //                                  Events                                 //
    /////////////////////////////////////////////////////////////////////////////

    event Deposit(address indexed user, uint256 amount);
    event AssetWithdrawal(address indexed user, uint256 amount);
    event AssetsPulled(uint256 amount);

    constructor() Ownable() {
        _transferOwnership(OWNER);
        // Sets the deadline to 30 days from now
        deadline = block.timestamp + DURATION;
    }

    /////////////////////////////////////////////////////////////////////////////
    //                                  CORE                                   //
    /////////////////////////////////////////////////////////////////////////////
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

    /// @notice Allow to withdraw cUSDC based on amount of GRO tokens deposited per user
    function withdraw() external {
        // Checks that the deadline has passed
        if (block.timestamp <= deadline) {
            revert RedemptionErrors.DeadlineNotExceeded();
        }
        // Gets the amount of GRO tokens deposited by the user
        uint256 amount = _balances[msg.sender];
        // Checks that the user has deposited GRO tokens
        if (amount == 0) {
            revert RedemptionErrors.NoDeposits();
        }
        // Calculate user's share from totalDeposited
        uint256 userShare = amount * BIPS / totalDeposited;
        // Calculate the amount of cUSDC to withdraw
        uint256 withdrawAmount = totalAssets * userShare / BIPS;
        // Decreases the balance of the user by the amount
        _balances[msg.sender] -= amount;
        // Send the cUSDC to the user
        ASSET.safeTransfer(msg.sender, withdrawAmount);
        // Emits the Withdraw event
        emit AssetWithdrawal(msg.sender, withdrawAmount);
    }

    /////////////////////////////////////////////////////////////////////////////
    //                              Permissioned funcs                         //
    /////////////////////////////////////////////////////////////////////////////
    function sweep(address _token) external onlyOwner {
        // Transfers the tokens to the owner
        ERC20(_token).safeTransfer(OWNER, ERC20(_token).balanceOf(address(this)));
    }

    /// @notice Pulls assets from the msig
    function pullAssets(uint256 _amount) external onlyOwner {
        ASSET.safeTransferFrom(owner(), address(this), _amount);
        totalAssets += ASSET.balanceOf(address(this));
        emit AssetsPulled(_amount);
    }
}
