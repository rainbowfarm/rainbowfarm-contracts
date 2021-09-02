// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

import "./Ownable.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";

import "./RainbowToken.sol";
import "./RNBORewardToken.sol";
import "./MinterRole.sol";

contract lockRNBO is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    RainbowToken public RNBO;

    StakedRNBO public stkRNBO;

    struct lockedtoken{
        uint256 amount;
        uint256 timestamp;
        uint256 duration;
        uint256 releaseTimestamp;
        bool released;
    }

    mapping(address => mapping(uint256 => lockedtoken)) public lockedTokens;
    mapping(address => uint256) public lockedTimes;

    constructor(RainbowToken _RNBO,StakedRNBO _stkRNBO) public
    {
        RNBO = _RNBO;
        stkRNBO = _stkRNBO;
    }

    function lock(address _sender,uint256 _amount,uint256 _duration) public {
        uint256 v_lockedtimes = lockedTimes[_sender] + 1;
        lockedtoken storage v_lock = lockedTokens[_sender][v_lockedtimes];
        
        require(_amount > 0)

        uint256 v_amountbefore = RNBO.balanceOf(address(this));
        RNBO.transferFrom(address(msg.sender),address(this),_amount);
        uint256 v_amountAfter = RNBO.balanceOf(address(this));
        uint256 v_depositedAmount = v_amountAfter.sub(v_amountbefore);
        v_lock.amount = v_depositedAmount;
        v_lock.timestamp = block.timestamp;
        v_lock.duration = _duration;
        v_lock.releaseTimestamp = block.timestamp + _duration;
        v_lock.released = false;
        stkRNBO.mint(address(msg.sender),v_depositedAmount);
    }
}