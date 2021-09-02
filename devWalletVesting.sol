// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

import "./Ownable.sol";
import "./SafeMath.sol";
import "./Address.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./RainbowToken.sol";

contract devWalletVesting is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public devWallet;
    uint256 public vestingStart; //vesting start, if provided vestingstart is lower than block timestamp then it will use block timestamp as vesting start.
    uint256 public interval; //min interval between vesting, in seconds, token vested would be token * (interval / total duration)
    uint256 public vestingEnd; // when final vesting should end
    IERC20 public token;
    uint256 public lastVestedOn;
    uint256 public nextVestingOn;
    
    constructor(address _wallet,uint256 _interval,uint256 _vestingEnd,uint256 _vestingStart,IERC20 _token) public {
        devWallet = _wallet;
        if (_vestingStart > block.timestamp){
            vestingStart = _vestingStart;
        }
        else{
            vestingStart = block.timestamp;
        }
        interval = _interval;
        vestingEnd = _vestingEnd;
        token = _token;
        lastVestedOn = _vestingStart;
        nextVestingOn = _vestingStart + _interval;
    }
    
    event TokensReleased(address token, uint256 amount);
    event DevWalletChanged(address wallet);
    
    function release() public {
        require(block.timestamp >= nextVestingOn, "INFO::Vesting:Cannot release before next vesting period.");
        require(token.balanceOf(address(this)) > 0 , "INFO::Balance:Nothing to release");
        uint256 releaseFactor = (block.timestamp - nextVestingOn).div(vestingEnd - nextVestingOn);
        if (releaseFactor > 1){
            releaseFactor = 1;
        }
        uint256 amountToRelease = token.balanceOf(address(this)).mul(releaseFactor);
        lastVestedOn = block.timestamp;
        nextVestingOn = lastVestedOn + interval;
        token.safeTransfer(devWallet,amountToRelease);
        emit TokensReleased(address(token), amountToRelease);
    }
    
    function devWalletUpdate(address _wallet) external onlyOwner {
        devWallet = _wallet;
        emit DevWalletChanged(_wallet);
    }
}