// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./SushiToken.sol";

interface IMigratorChef {
    // LP = liquidity pool
    // Perform LP token migration from legacy UniswapV2 to SushiSwap.
    // Take the current LP token address and return the new LP token address.
    // Migrator should have full access to the caller's LP token.
    // Return the new LP token address.
    //
    // XXX Migrator must have allowance access to UniswapV2 LP tokens.
    // SushiSwap must mint EXACTLY the same amount of SushiSwap LP tokens or
    // else something bad will happen. Traditional UniswapV2 does not
    // do that so be careful!
    function migrate(IERC20 token) external returns (IERC20);
}

// MasterChef is the master of Sushi. He can make Sushi and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once SUSHI is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debited ? debitable, helps in reward calculation. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of SUSHIs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accSushiPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accSushiPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. SUSHIs to distribute per block.
        uint256 lastRewardBlock; // Last block number that SUSHIs distribution occurs.
        uint256 accSushiPerShare; // Reward (in shushi) per LP token staked. Accumulated SUSHIs per share, times 1e12. See below.
    }

    // The SUSHI TOKEN! instance of sushi contract
    SushiToken public sushi;

    // Dev address.
    address public devaddr;

    // Block number when bonus SUSHI period ends.
    uint256 public bonusEndBlock;

    // SUSHI tokens created per block. fixed number.
    uint256 public sushiPerBlock;

    // Bonus muliplier for early sushi makers.
    uint256 public constant BONUS_MULTIPLIER = 10;

    // The migrator contract. It has a lot of power. Can only be set through governance (owner).
    IMigratorChef public migrator;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    // The block number when SUSHI mining starts.
    uint256 public startBlock;

    //events
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    constructor(
        SushiToken _sushi,
        address _devaddr,
        uint256 _sushiPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock
    ) public {
        sushi = _sushi;
        devaddr = _devaddr;
        sushiPerBlock = _sushiPerBlock;
        bonusEndBlock = _bonusEndBlock;
        startBlock = _startBlock;
    }

    //number of LP pools
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    /**
     * @param _allocPoint -
     * @param _lpToken - address of the LP token, note that it is the responsibility of the owner to keep LP tokens unique for all different pools. Else there will be issue with rewards calculation.
     * @param _withUpdate - This means it will update all liquidity pools, then a higher gas fees has to be paid.
     *
     * @dev - Add a new lp to the pool. Can only be called by the owner.
     *
     * @notice - XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
     */
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock
            ? block.number
            : startBlock;

        //update the allocation point
        totalAllocPoint = totalAllocPoint.add(_allocPoint);

        //whenever we add liquidity we add new pool in poolInfo, as compared to updating the existing lp tokne pool
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accSushiPerShare: 0
            })
        );
    }

    // Update the given pool's SUSHI allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    // for updating changes in "lpSupply" or "accShushiPerShare" "blocks count since last reward block" or "poolAllocation" or "totalAllocation
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];

        //check if update reward is already run on the block
        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        //get the current LP tokens supply
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));

        //if no LP tokens, then do nothing.
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        //calculate the reward multiplier at this instant (block.number). The unit of this multiplier is per block.
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);

        //reward = multiplier x sushiPerBlock x (pool.allocationCount / sum of all allocationCount of all pools)
        uint256 sushiReward = multiplier
            .mul(sushiPerBlock)
            .mul(pool.allocPoint)
            .div(totalAllocPoint);

        sushi.mint(devaddr, sushiReward.div(10)); //10% of rewards will go to devAddress
        sushi.mint(address(this), sushiReward);

        //update the accumulated Sushi Per Share value.
        pool.accSushiPerShare = pool.accSushiPerShare.add(
            sushiReward.mul(1e12).div(lpSupply)
        );

        //update the lastRewardBlock
        pool.lastRewardBlock = block.number;
    }

    // Set the migrator contract. Can only be called by the owner.
    function setMigrator(IMigratorChef _migrator) public onlyOwner {
        migrator = _migrator;
    }

    // Migrate lp token to another lp contract. Can be called by anyone. We trust that migrator contract is good.
    function migrate(uint256 _pid) public {
        require(address(migrator) != address(0), "migrate: no migrator");
        PoolInfo storage pool = poolInfo[_pid];
        IERC20 lpToken = pool.lpToken;
        uint256 bal = lpToken.balanceOf(address(this));
        lpToken.safeApprove(address(migrator), bal);
        IERC20 newLpToken = migrator.migrate(lpToken);
        require(bal == newLpToken.balanceOf(address(this)), "migrate: bad");
        pool.lpToken = newLpToken;
    }

    /**
     * @param _from - from block number
     * @param _to - to block number
     *
     * @dev - Baiscally, this is used for ICO purposes.
     *        Return reward multiplier over the given _from to _to block. Bonus is applicable only till the bonuseEndBlock
     *        if thant what is bonusEndBlock is stacked, then no bonus reward should be multiplied.
     *
     * @notice - What if _to < _from < bonusEndBlock
     */
    function getMultiplier(
        uint256 _from,
        uint256 _to
    ) public view returns (uint256) {
        if (_to <= bonusEndBlock) {
            //when bonus is applicable.
            return _to.sub(_from).mul(BONUS_MULTIPLIER);
        } else if (_from >= bonusEndBlock) {
            //basically no bonus action
            return _to.sub(_from);
        } else {
            //for all cases where from <= bonusEndBlock < _to
            //bonus will only be applicalbe until the bonusEndBlock is reached.
            //applicable bonus = BONUS_MULTIPLIER
            return
                bonusEndBlock.sub(_from).mul(BONUS_MULTIPLIER).add(
                    _to.sub(bonusEndBlock)
                );
        }
    }

    // pending reward for that particular user, but first, the pools rewards is updated.
    // View function to see pending SUSHIs on frontend. What is the pending reward for that user.
    ///@notice - The value `accSushiPerShare` will not be updated here, firstly because it is a `view` function and secondly, stroage value is not changed.
    function pendingSushi(
        uint256 _pid,
        address _user
    ) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accSushiPerShare = pool.accSushiPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));

        //if reward is not already calculated and there is something in pool to reward (extra check for emergencies).
        //update the total rewards in the pool
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardBlock,
                block.number
            );

            //sushi reward = multiplier x sushiPerBlock x ( pool.allocationPoint / sum of all allocationPoints of all pools)
            uint256 sushiReward = multiplier
                .mul(sushiPerBlock)
                .mul(pool.allocPoint)
                .div(totalAllocPoint);

            //update accSushiPerShare at that instant for that "particular pool", this value will be used for reward calculation.
            //sushiReward = rewards for that particular pool
            //lpSupply = total number of LP tokens for that particular pool
            accSushiPerShare = accSushiPerShare.add(
                sushiReward.mul(1e12).div(lpSupply)
            );
        }
        return user.amount.mul(accSushiPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Safe sushi transfer function, just in case if rounding error causes pool to not have enough SUSHIs.
    function safeSushiTransfer(address _to, uint256 _amount) internal {
        uint256 sushiBal = sushi.balanceOf(address(this));
        if (_amount > sushiBal) {
            sushi.transfer(_to, sushiBal);
        } else {
            sushi.transfer(_to, _amount);
        }
    }

    // Deposit LP tokens to MasterChef for SUSHI allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid]; //that pool details
        UserInfo storage user = userInfo[_pid][msg.sender]; //user details for that pool

        //step 1
        updatePool(_pid);

        // step 2
        //if user has deposited some LP tokens, then transfers the rewards first
        //@audit - Why is this needed?
        if (user.amount > 0) {
            //calculate the pending reward that the user will receive. and transfer the rewards.
            // pending = amount x pool.accSushiPerShare - rewardDebt
            uint256 pending = user
                .amount
                .mul(pool.accSushiPerShare)
                .div(1e12)
                .sub(user.rewardDebt);

            //transfer pending rewards (in form of sushi) from MasterChef.sol to msg.sender
            safeSushiTransfer(msg.sender, pending);
        }

        //unitl now the `_amount` is  not used or updated.

        //step 3
        //transfer the promised LP tokens from uesr to LP pool
        pool.lpToken.safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );

        //update user data
        user.amount = user.amount.add(_amount);
        // rewardDebt = amount x pool.accSushiPerShare (updated when you are calling update pools)
        user.rewardDebt = user.amount.mul(pool.accSushiPerShare).div(1e12); //update the rewardDebt

        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accSushiPerShare).div(1e12).sub(
            user.rewardDebt
        );
        safeSushiTransfer(msg.sender, pending);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accSushiPerShare).div(1e12);
        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }
}
