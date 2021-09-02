// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

import "./Ownable.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";

import "./RainbowToken.sol";
import "./RNBORewardToken.sol";
// MasterChef is the master of Fish. He can make Fish and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once Fish is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        uint256 lastDepositTimestamp;
        uint256 userWeight;
        //
        // We do some fancy math here. Basically, any point in time, the amount of FISHes
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accFishPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accFishPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. FISHes to distribute per block.
        uint256 lastRewardBlock;  // Last block number that FISHes distribution occurs.
        uint256 accRNBOPerShare;   // Accumulated FISHes per share, times 1e18. See below.
        uint256 totalWeight;
        uint256 poolWithdrawFee;
    }

    RainbowToken public RNBO;

    StakedRNBO public stkRNBO;

    address public devAddress;

    address public feeAddress;

    uint256 public rnboPerBlock = 4*(10**18);

    PoolInfo[] public poolInfo;

    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    uint256 public totalAllocPoint = 0;

    uint256 public startBlock;

    uint256 public maxWithdrawFee = 300;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event SetDevAddress(address indexed user, address indexed newAddress);
    event SetVaultAddress(address indexed user, address indexed newAddress);
    event UpdateEmissionRate(address indexed user, uint256 fishPerBlock);
    event Debug(address indexed user,string valuetype,uint256 value);

    constructor(
        RainbowToken _RNBO,
        StakedRNBO _stkRNBO,
        uint256 _startBlock,
        address _devAddress,
        address _feeAddress
    ) public {
        RNBO = _RNBO;
        stkRNBO = _stkRNBO;
        if (_startBlock == 0){
            startBlock = block.number;
        }
        else{
            startBlock = _startBlock;
        }
        devAddress = _devAddress;
        feeAddress = _feeAddress;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    mapping(IERC20 => bool) public poolExistence;
    modifier nonDuplicated(IERC20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }
    
    function getwithdrawFee(address _user) public view returns (uint256){
        uint256 v_withdrawFee = 0;
        uint256 basebp = 10000;
        if (stkRNBO.balanceOf(_user) > 0){
            v_withdrawFee = basebp.div((stkRNBO.totalSupply()).mul(100).div(stkRNBO.balanceOf(_user)));
        }
        return v_withdrawFee;
    }

    function setMaxWithdrawFee(uint256 _fee) public onlyOwner returns (bool){
        require(_fee <= 400 ,"ERROR:Fee:Withdarw Fee cannot be higher than 4%");
        maxWithdrawFee = _fee;
        return true;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IERC20 _lpToken,uint256 _poolWithdrawFee) external onlyOwner nonDuplicated(_lpToken) {
        require(poolExistence[_lpToken] == false, "ERR::Pool:Pool Exist");
        require(_poolWithdrawFee < 1000, "ERR:Fees:Max Fee 10% (will be used only for native single stake pool");
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolExistence[_lpToken] = true;
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accRNBOPerShare: 0,
            totalWeight:0,
            poolWithdrawFee:_poolWithdrawFee
        }));
    }

    // Update the given pool's FISH allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint256 _poolWithdrawFee) external onlyOwner {
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].poolWithdrawFee = _poolWithdrawFee;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from);
    }

    function pendingRNBO(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRNBOPerShare = pool.accRNBOPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        uint256 v_totalWeight = pool.totalWeight;
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 RNBOReward = multiplier.mul(rnboPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            if(v_totalWeight > 0){
            accRNBOPerShare = accRNBOPerShare.add(RNBOReward.mul(1e18).div(v_totalWeight));
            }
        }
        return user.userWeight.mul(accRNBOPerShare).div(1e18).sub(user.rewardDebt);
    }

    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }
    
    function userPoolWeight(uint256 _pid) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 v_userWeight = user.userWeight;
        uint256 v_totalWeight = pool.totalWeight;
        uint256 v_poolweight = 0;
        if (v_totalWeight > 0){
            v_poolweight = 100+v_userWeight.mul(100).div(v_totalWeight);
        }
        return v_poolweight;
    }

    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][tx.origin];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        uint256 v_totalWeight = pool.totalWeight;
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 RNBOReward = multiplier.mul(rnboPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        RNBO.mint(devAddress, RNBOReward.div(20));
        RNBO.mint(address(this), RNBOReward);
        if(v_totalWeight > 0){
        pool.accRNBOPerShare = pool.accRNBOPerShare.add(RNBOReward.mul(10**18).div(v_totalWeight));
        }
        pool.lastRewardBlock = block.number;
        updateWeights(tx.origin,_pid,user.amount);
    }
    

    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 _depositamount = 0 ;
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.userWeight.mul(pool.accRNBOPerShare).div(1e18).sub(user.rewardDebt);
            if (pending > 0) {
                safeRNBOTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            uint256 _amountbefore = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            uint256 _amountafter = pool.lpToken.balanceOf(address(this));
            _depositamount = _amountafter.sub(_amountbefore);
            user.amount = user.amount.add(_depositamount);
            user.lastDepositTimestamp = block.timestamp;
            if (pool.lpToken ==  RNBO){
                stkRNBO.mint(msg.sender,_depositamount);
            }
        }
        user.rewardDebt = user.userWeight.mul(pool.accRNBOPerShare).div(1e18);
        updateWeights(msg.sender,_pid,user.amount);
        emit Deposit(msg.sender, _pid, _amount);
    }
    
    function updateWeights(address _user,uint256 _pid,uint256 _depositamount) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 v_new = 0;
        uint256 v_old = 0;
        v_old    = user.userWeight;
        if (pool.lpToken ==  RNBO){
            v_new = _depositamount*100;
        }
        else {
            if(stkRNBO.totalSupply() > 0) {
            v_new = _depositamount.mul(100+stkRNBO.balanceOf(_user).mul(100).div(stkRNBO.totalSupply())).div(100);
            }
            else {
                v_new = _depositamount*100;
            }
        }
        user.userWeight = v_new;
        if (pool.totalWeight > 0){
            pool.totalWeight = pool.totalWeight.sub(v_old);
        }
        pool.totalWeight = pool.totalWeight.add(user.userWeight);
    }
    
    function getActualWithdrawFeeRate(uint256 _pid) public view returns (uint256){
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 v_fees = 0;
        uint256 v_feerate = getwithdrawFee(msg.sender); 
        //v_feerate = getwithdrawFee(msg.sender);
        uint256 poolWithdrawFee = pool.poolWithdrawFee; 
		uint256 actualWithdrawFeeRate = poolWithdrawFee; 
		if(maxWithdrawFee < poolWithdrawFee && pool.lpToken != RNBO) {
			actualWithdrawFeeRate = maxWithdrawFee; 
		}
        uint256 v_feesbp = actualWithdrawFeeRate;
        if(v_feerate > 50){
            v_feesbp = 0;
        }
        else if(v_feerate < 50 && user.amount > 0){
         v_feesbp = actualWithdrawFeeRate.sub(actualWithdrawFeeRate.mul(v_feerate).mul(2).div(100));
         uint256 daysfromlastdeposit = ((((block.timestamp - user.lastDepositTimestamp)/60)/60)/24);
         if(daysfromlastdeposit > 90){
                v_feesbp = v_feesbp.div(2);
            }
        }
        if(pool.lpToken == RNBO && user.amount > 0)
        {
            uint256 daysfromlastdeposit = ((((block.timestamp - user.lastDepositTimestamp)/60)/60)/24);
            if(daysfromlastdeposit > 90){
                v_feesbp = 0;
            }
            else if(daysfromlastdeposit > 45){
                v_feesbp = pool.poolWithdrawFee.div(2);
            }
            else{
                v_feesbp = pool.poolWithdrawFee;
            }
        }
        return v_feesbp;
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 v_fees = 0;
        uint256 v_feerate = 0;
        require(user.amount >= _amount, "Error::withdraw: Withdrawing more than balance");
        updatePool(_pid);
        uint256 pending = user.userWeight.mul(pool.accRNBOPerShare).div(1e18).sub(user.rewardDebt);
        if (pending > 0) {
            safeRNBOTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            uint256 v_feesbp = getActualWithdrawFeeRate(_pid);
            v_fees = _amount.mul(v_feesbp).div(10000);
            user.amount = user.amount.sub(_amount);
            uint256 v_withdrawAmount = _amount.sub(v_fees);
            pool.lpToken.safeTransfer(address(msg.sender),v_withdrawAmount);
            pool.lpToken.safeTransfer(address(feeAddress),v_fees);
        }
        user.rewardDebt = user.userWeight.mul(pool.accRNBOPerShare).div(1e18);
        require(user.userWeight > 0 && pool.totalWeight > 0 , "ERROR:RNBOWeight:System Malfunction, withdrawing more than staked");
        if (pool.lpToken ==  RNBO){
            stkRNBO.burn(msg.sender,_amount);
        }
        updateWeights(msg.sender,_pid,user.amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }
    
    /**
    function withdrawAll(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount > 0, "Error::withdraw: Withdrawing more than balance");

        uint256 v_fees = 0;
        uint256 v_feerate =0;
        updatePool(_pid);
        uint256 pending = user.userWeight.mul(pool.accRNBOPerShare).div(1e18).sub(user.rewardDebt);
        if (pending > 0) {
            safeRNBOTransfer(msg.sender, pending);
        }
        v_feerate = getwithdrawFee(msg.sender);
        uint256 poolWithdrawFee = pool.poolWithdrawFee;
			uint256 actualWithdrawFeeRate = poolWithdrawFee;
			if(maxWithdrawFee < poolWithdrawFee) {
				actualWithdrawFeeRate = maxWithdrawFee;
			}
        uint256 v_feesbp = 0;
        if(v_feerate < 50){
         v_feesbp = actualWithdrawFeeRate.sub(poolWithdrawFee.mul(v_feerate).mul(2).div(100));
        }
        if(pool.lpToken == RNBO)
        {
            v_feesbp = pool.poolWithdrawFee;
        }
        v_fees = user.amount.mul(v_feesbp).div(10000);

        uint256 v_withdrawAmount = user.amount.sub(v_fees);
        user.amount = user.amount.sub(user.amount);

        if (v_fees > 0)
        {
            pool.lpToken.safeTransfer(address(feeAddress),v_fees);
        }
        pool.lpToken.safeTransfer(msg.sender,v_withdrawAmount);

        user.rewardDebt = user.userWeight.mul(pool.accRNBOPerShare).div(1e18);

        if (pool.lpToken ==  RNBO){
            stkRNBO.burn(msg.sender,stkRNBO.balanceOf(msg.sender));
        }
        updateWeights(msg.sender,_pid,user.amount);
        emit Withdraw(msg.sender, _pid, v_withdrawAmount);
        emit Withdraw(feeAddress, _pid, v_fees);
    }
    */

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe fish transfer function, just in case if rounding error causes pool to not have enough FISH.
    function safeRNBOTransfer(address _to, uint256 _amount) internal {
        uint256 RNBOBal = RNBO.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > RNBOBal) {
            transferSuccess = RNBO.transfer(_to, RNBOBal);
        } else {
            transferSuccess = RNBO.transfer(_to, _amount);
        }
        require(transferSuccess, "safeRNBOTransfer: Transfer failed");
    }

    // Update dev address by the previous dev.
    function setDevAddress(address _devAddress) external onlyOwner {
        require(_devAddress != address(0),"Error::AddressChange:Dev Address cannot be 0");
        devAddress = _devAddress;
        emit SetDevAddress(msg.sender, _devAddress);
    }

    function setFeeAddress(address _feeAddress) external onlyOwner {
        require(_feeAddress != address(0),"Error::AddressChange:Fee Address cannot be 0");
        feeAddress = _feeAddress;
        emit SetFeeAddress(msg.sender, _feeAddress);
    }

    function updateEmissionRate(uint256 _rnboPerBlock) external onlyOwner {
        massUpdatePools();
        require(rnboPerBlock > _rnboPerBlock*(10**18),"Error:Emmission: New Emission Rate need to be lower than existing");
        rnboPerBlock = _rnboPerBlock*(10**18);
        emit UpdateEmissionRate(msg.sender, _rnboPerBlock);
    }

    // Only update before start of farm
    function updateStartBlock(uint256 _startBlock) external onlyOwner {
	    require(startBlock > block.number, "Farm already started");
        startBlock = _startBlock;
    }
}