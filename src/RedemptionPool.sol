// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {RedemptionErrors} from "./Errors.sol";

contract RedemptionPool is Ownable {
    using SafeERC20 for IERC20;

    /////////////////////////////////////////////////////////////////////////////
    //                                  Constants                              //
    /////////////////////////////////////////////////////////////////////////////

    uint256 public constant DURATION = 28 days;
    uint256 public immutable DEADLINE;

    uint256 internal constant BIPS = 10_000;
    uint256 internal constant PRECISION = 1e18;
    uint256 internal constant CUSDC_PRECISION = 1e6;

    address internal constant DAO =
        address(0x359F4fe841f246a095a82cb26F5819E10a91fe0d);
    address internal constant UNIV3ROUTER =
        address(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    // TOKENS
    IERC20 public constant GRO =
        IERC20(0x3Ec8798B81485A254928B70CDA1cf0A2BB0B74D7);
    IERC20 public constant CUSDC =
        IERC20(0xc3d688B66703497DAA19211EEdff47f25384cdc3);

    address internal constant USDC =
        address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address internal constant COMP =
        address(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    address internal constant WETH9 =
        address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    /////////////////////////////////////////////////////////////////////////////
    //                                  Storage                                //
    /////////////////////////////////////////////////////////////////////////////

    mapping(address => uint256) private _userGROBalance;
    mapping(address => uint256) private _userClaims;
    uint256 public totalGRO;
    uint256 public totalCUSDCDeposited;
    uint256 public interestAccrued;
    uint256 public totalClaims;

    /////////////////////////////////////////////////////////////////////////////
    //                                  Events                                 //
    /////////////////////////////////////////////////////////////////////////////

    event Deposit(address indexed user, uint256 amount);
    //    event Withdraw(address indexed user, uint256 amount);
    event Claim(address indexed user, uint256 amount);
    event CUSDCDeposit(uint256 amount);
    event PositionTransferred(
        address indexed from,
        address indexed to,
        uint256 amount
    );

    /////////////////////////////////////////////////////////////////////////////
    //                                  CONSTRUCTOR                            //
    /////////////////////////////////////////////////////////////////////////////

    constructor() {
        transferOwnership(DAO);
        // Sets the DEADLINE to 28 days from now
        DEADLINE = block.timestamp + DURATION;
    }

    /////////////////////////////////////////////////////////////////////////////
    //                                   VIEWS                                 //
    /////////////////////////////////////////////////////////////////////////////

    /// @notice Returns the price per share of the pool
    function getPricePerShare() public view returns (uint256) {
        return (_calcTotalWithinterest() * PRECISION) / totalGRO;
    }

    /// @notice Returns the amount of cUSDC available for a user
    /// @param user address of the user
    function getSharesAvailable(address user) public view returns (uint256) {
        return
            (_userGROBalance[user] * _calcTotalWithinterest()) /
            totalGRO -
            _userClaims[user];
    }

    /// @notice Returns the amount of GRO user has deposited
    /// @param user address of the user
    function getUserBalance(address user) external view returns (uint256) {
        return _userGROBalance[user];
    }

    /// @notice Returns claimed cUSDC for a user
    /// @param user address of the user
    function getUserClaim(address user) external view returns (uint256) {
        return _userClaims[user];
    }

    /// @notice Returns the deadline of the redemption pool
    function getDeadline() external view returns (uint256) {
        return DEADLINE;
    }

    function _calcTotalWithinterest() internal view returns (uint256) {
        return totalCUSDCDeposited + _interestAccrued();
    }

    function _interestAccrued() internal view returns (uint256) {
        return interestAccrued + (CUSDC.balanceOf(address(this)) - (totalCUSDCDeposited + interestAccrued - totalClaims));
    }

    /////////////////////////////////////////////////////////////////////////////
    //                                  CORE                                   //
    /////////////////////////////////////////////////////////////////////////////

    /// @notice deposit GRO tokens to the pool before the deadline
    /// @param _amount amount of GRO tokens to deposit
    function deposit(uint256 _amount) external {
        // Checks that the DEADLINE has not passed
        if (block.timestamp > DEADLINE) {
            revert RedemptionErrors.DeadlineExceeded();
        }
        // Transfers the GRO tokens from the sender to this contract
        GRO.safeTransferFrom(msg.sender, address(this), _amount);
        // Increases the balance of the sender by the amount
        _userGROBalance[msg.sender] += _amount;
        // Increases the total deposited by the amount
        totalGRO += _amount;
        // Emits the Deposit event
        emit Deposit(msg.sender, _amount);
    }

    /* WELCOME TO HOTEL CALIFORNIA
    /// @notice withdraw deposited GRO tokens before the deadline
    /// @param _amount amount of GRO tokens to withdraw
    function withdraw(uint256 _amount) external {
        if (block.timestamp > DEADLINE) {
            revert RedemptionErrors.DeadlineExceeded();
        }
        if (_userGROBalance[msg.sender] < _amount) {
            revert RedemptionErrors.UserBalanceToSmall();
        }
        _userGROBalance[msg.sender] -= _amount;
        totalGRO -= _amount;
        GRO.safeTransfer(msg.sender, _amount);
        emit Withdraw(msg.sender, _amount);
    }
    */

    /// @notice Allow to withdraw cUSDC based on amount of GRO tokens deposited per user
    function claim() external {
        if (block.timestamp <= DEADLINE) {
            revert RedemptionErrors.DeadlineNotExceeded();
        }
        if (_userGROBalance[msg.sender] <= 0) {
            revert RedemptionErrors.NoUserBalance();
        }
        uint256 userClaim = getSharesAvailable(msg.sender);
        if (userClaim == 0) {
            revert RedemptionErrors.NoUserClaim();
        }
        _userClaims[msg.sender] += userClaim;
        interestAccrued = _interestAccrued();
        totalClaims += userClaim;
        IERC20(CUSDC).transfer(msg.sender, userClaim);
        emit Claim(msg.sender, userClaim);
    }

    /////////////////////////////////////////////////////////////////////////////
    //                              Permissioned funcs                         //
    /////////////////////////////////////////////////////////////////////////////

    /// @notice Pulls assets from the msig
    /// @param amount amount of cUSDC to pull
    function depositCUSDC(uint256 amount) external onlyOwner {
        require(amount > 0, "amount must be greater than 0");
        require(
            IERC20(CUSDC).transferFrom(msg.sender, address(this), amount),
            "transfer failed"
        );
        totalCUSDCDeposited += amount;
        interestAccrued = _interestAccrued();
        emit CUSDCDeposit(totalCUSDCDeposited);
    }

    /// @notice Allow to withdraw any tokens except GRO back to the owner
    /// @param _token address of the token to sweep
    function sweep(address _token) external onlyOwner {
        // Do not allow to sweep GRO tokens
        if (_token == address(GRO)) {
            revert RedemptionErrors.NoSweepGro();
        }
        // Transfers the tokens to the owner
        IERC20(_token).safeTransfer(
            owner(),
            IERC20(_token).balanceOf(address(this))
        );
    }

    // @notice Transfers a portion or all of a user's redeemable GRO position to a new address.
    // @param to The address to which the GRO position will be transferred.
    // @param amount The amount of GRO to transfer.
    function transferPosition(address to, uint256 amount) public {
        if (amount > (_userGROBalance[msg.sender] - _userClaims[msg.sender]))
            revert RedemptionErrors.AmountExceedsAvailableGRO();

        _userGROBalance[msg.sender] -= amount;
        _userGROBalance[to] += amount;

        emit PositionTransferred(msg.sender, to, amount);
    }
}
