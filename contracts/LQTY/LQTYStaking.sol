// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../Dependencies/BaseMath.sol";
import "../Dependencies/SafeMath.sol";
import "../Dependencies/Ownable.sol";
import "../Dependencies/CheckContract.sol";
import "../Dependencies/console.sol";
import "../Interfaces/ILQTYToken.sol";
import "../Interfaces/ILQTYStaking.sol";
import "../Dependencies/LiquityMath.sol";
import "../Interfaces/ILUSDToken.sol";

contract LQTYStaking is ILQTYStaking, Ownable, CheckContract, BaseMath {
    using SafeMath for uint;

    // --- Data ---
    string constant public NAME = "LQTYStaking";

    mapping( address => uint) public stakes;
    uint public totalLQTYStaked;

    uint public F_ETH;  // Running sum of ETH fees per-LQTY-staked
    uint public F_LUSD; // Running sum of LQTY fees per-LQTY-staked

    // User snapshots of F_ETH and F_LUSD, taken at the point at which their latest deposit was made
    mapping (address => Snapshot) public snapshots;

    struct Snapshot {
        uint F_ETH_Snapshot;
        uint F_LUSD_Snapshot;
    }

    mapping (address => LockedBalance[]) private userEarnings;

    struct LockedBalance {
        uint amount;
        uint unlockTime;
    }

    // Duration that rewards are streamed over
    uint public constant REWARDS_DURATION = 86400 * 7;
    // Duration of lock/earned penalty period
    uint public constant LOCK_DURATION = REWARDS_DURATION * 13;

    mapping (address => Balances) private userBalances;

    struct Balances {
        uint earned;
    }

    // Total penalty
    uint public totalBurned = 0;

    ILQTYToken public lqtyToken;
    ILUSDToken public lusdToken;

    address public troveManagerAddress;
    address public borrowerOperationsAddress;
    address public activePoolAddress;

    // --- Events ---

    event LQTYTokenAddressSet(address _lqtyTokenAddress);
    event LUSDTokenAddressSet(address _lusdTokenAddress);
    event TroveManagerAddressSet(address _troveManager);
    event BorrowerOperationsAddressSet(address _borrowerOperationsAddress);
    event ActivePoolAddressSet(address _activePoolAddress);

    event StakeChanged(address indexed staker, uint newStake);
    event StakingGainsWithdrawn(address indexed staker, uint LUSDGain, uint ETHGain);
    event F_ETHUpdated(uint _F_ETH);
    event F_LUSDUpdated(uint _F_LUSD);
    event TotalLQTYStakedUpdated(uint _totalLQTYStaked);
    event EtherSent(address _account, uint _amount);
    event StakerSnapshotsUpdated(address _staker, uint _F_ETH, uint _F_LUSD);

    event EarningAdd(address indexed user, uint amount);
    event EarningWithdraw(address indexed user, uint amount, uint penaltyAmount, uint totalBurned);

    // --- Functions ---

    function setAddresses
    (
        address _lqtyTokenAddress,
        address _lusdTokenAddress,
        address _troveManagerAddress,
        address _borrowerOperationsAddress,
        address _activePoolAddress
    )
        external
        onlyOwner
        override
    {
        checkContract(_lqtyTokenAddress);
        checkContract(_lusdTokenAddress);
        checkContract(_troveManagerAddress);
        checkContract(_borrowerOperationsAddress);
        checkContract(_activePoolAddress);

        lqtyToken = ILQTYToken(_lqtyTokenAddress);
        lusdToken = ILUSDToken(_lusdTokenAddress);
        troveManagerAddress = _troveManagerAddress;
        borrowerOperationsAddress = _borrowerOperationsAddress;
        activePoolAddress = _activePoolAddress;

        emit LQTYTokenAddressSet(_lqtyTokenAddress);
        emit LQTYTokenAddressSet(_lusdTokenAddress);
        emit TroveManagerAddressSet(_troveManagerAddress);
        emit BorrowerOperationsAddressSet(_borrowerOperationsAddress);
        emit ActivePoolAddressSet(_activePoolAddress);

        _renounceOwnership();
    }

    // If caller has a pre-existing stake, send any accumulated ETH and LUSD gains to them.
    function stake(uint _LQTYamount) external override {
        _requireNonZeroAmount(_LQTYamount);

        uint currentStake = stakes[msg.sender];

        uint ETHGain;
        uint LUSDGain;
        // Grab any accumulated ETH and LUSD gains from the current stake
        if (currentStake != 0) {
            ETHGain = _getPendingETHGain(msg.sender);
            LUSDGain = _getPendingLUSDGain(msg.sender);
        }

       _updateUserSnapshots(msg.sender);

        uint newStake = currentStake.add(_LQTYamount);

        // Increase user’s stake and total LQTY staked
        stakes[msg.sender] = newStake;
        totalLQTYStaked = totalLQTYStaked.add(_LQTYamount);
        emit TotalLQTYStakedUpdated(totalLQTYStaked);

        // Transfer LQTY from caller to this contract
        lqtyToken.sendToLQTYStaking(msg.sender, _LQTYamount);

        emit StakeChanged(msg.sender, newStake);
        emit StakingGainsWithdrawn(msg.sender, LUSDGain, ETHGain);

         // Send accumulated LUSD and ETH gains to the caller
        if (currentStake != 0) {
            lusdToken.transfer(msg.sender, LUSDGain);
            _sendETHGainToUser(ETHGain);
        }
    }

    // Unstake the LQTY and send the it back to the caller, along with their accumulated LUSD & ETH gains.
    // If requested amount > stake, send their entire stake.
    function unstake(uint _LQTYamount) external override {
        uint currentStake = stakes[msg.sender];
        _requireUserHasStake(currentStake);

        // Grab any accumulated ETH and LUSD gains from the current stake
        uint ETHGain = _getPendingETHGain(msg.sender);
        uint LUSDGain = _getPendingLUSDGain(msg.sender);

        _updateUserSnapshots(msg.sender);

        if (_LQTYamount > 0) {
            uint LQTYToWithdraw = LiquityMath._min(_LQTYamount, currentStake);

            uint newStake = currentStake.sub(LQTYToWithdraw);

            // Decrease user's stake and total LQTY staked
            stakes[msg.sender] = newStake;
            totalLQTYStaked = totalLQTYStaked.sub(LQTYToWithdraw);
            emit TotalLQTYStakedUpdated(totalLQTYStaked);

            // Transfer unstaked LQTY to user
            lqtyToken.transfer(msg.sender, LQTYToWithdraw);

            emit StakeChanged(msg.sender, newStake);
        }

        emit StakingGainsWithdrawn(msg.sender, LUSDGain, ETHGain);

        // Send accumulated LUSD and ETH gains to the caller
        lusdToken.transfer(msg.sender, LUSDGain);
        _sendETHGainToUser(ETHGain);
    }

    // --- Reward-per-unit-staked increase functions. Called by Liquity core contracts ---

    function increaseF_ETH(uint _ETHFee) external override {
        _requireCallerIsTroveManager();
        uint ETHFeePerLQTYStaked;

        if (totalLQTYStaked > 0) {ETHFeePerLQTYStaked = _ETHFee.mul(DECIMAL_PRECISION).div(totalLQTYStaked);}

        F_ETH = F_ETH.add(ETHFeePerLQTYStaked);
        emit F_ETHUpdated(F_ETH);
    }

    function increaseF_LUSD(uint _LUSDFee) external override {
        _requireCallerIsBorrowerOperations();
        uint LUSDFeePerLQTYStaked;

        if (totalLQTYStaked > 0) {LUSDFeePerLQTYStaked = _LUSDFee.mul(DECIMAL_PRECISION).div(totalLQTYStaked);}

        F_LUSD = F_LUSD.add(LUSDFeePerLQTYStaked);
        emit F_LUSDUpdated(F_LUSD);
    }

    // --- Pending reward functions ---

    function getPendingETHGain(address _user) external view override returns (uint) {
        return _getPendingETHGain(_user);
    }

    function _getPendingETHGain(address _user) internal view returns (uint) {
        uint F_ETH_Snapshot = snapshots[_user].F_ETH_Snapshot;
        uint ETHGain = stakes[_user].mul(F_ETH.sub(F_ETH_Snapshot)).div(DECIMAL_PRECISION);
        return ETHGain;
    }

    function getPendingLUSDGain(address _user) external view override returns (uint) {
        return _getPendingLUSDGain(_user);
    }

    function _getPendingLUSDGain(address _user) internal view returns (uint) {
        uint F_LUSD_Snapshot = snapshots[_user].F_LUSD_Snapshot;
        uint LUSDGain = stakes[_user].mul(F_LUSD.sub(F_LUSD_Snapshot)).div(DECIMAL_PRECISION);
        return LUSDGain;
    }

    // --- Internal helper functions ---

    function _updateUserSnapshots(address _user) internal {
        snapshots[_user].F_ETH_Snapshot = F_ETH;
        snapshots[_user].F_LUSD_Snapshot = F_LUSD;
        emit StakerSnapshotsUpdated(_user, F_ETH, F_LUSD);
    }

    function _sendETHGainToUser(uint ETHGain) internal {
        emit EtherSent(msg.sender, ETHGain);
        (bool success, ) = msg.sender.call{value: ETHGain}("");
        require(success, "LQTYStaking: Failed to send accumulated ETHGain");
    }

    // --- 'require' functions ---

    function _requireCallerIsTroveManager() internal view {
        require(msg.sender == troveManagerAddress, "LQTYStaking: caller is not TroveM");
    }

    function _requireCallerIsBorrowerOperations() internal view {
        require(msg.sender == borrowerOperationsAddress, "LQTYStaking: caller is not BorrowerOps");
    }

     function _requireCallerIsActivePool() internal view {
        require(msg.sender == activePoolAddress, "LQTYStaking: caller is not ActivePool");
    }

    function _requireUserHasStake(uint currentStake) internal pure {
        require(currentStake > 0, 'LQTYStaking: User must have a non-zero stake');
    }

    function _requireNonZeroAmount(uint _amount) internal pure {
        require(_amount > 0, 'LQTYStaking: Amount must be non-zero');
    }

    receive() external payable {
        _requireCallerIsActivePool();
    }

    // --- Earning-related functions ---

    /*
     * Add earning from other accounts, which will be locked for 3 months.
     * Early exit is allowed, by 50% will be penalized.
     */
    function addEarning(address _user, uint _amount) external override {
        Balances storage bal = userBalances[_user];
        bal.earned = bal.earned.add(_amount);

        uint unlockTime = block.timestamp.div(REWARDS_DURATION).mul(REWARDS_DURATION).add(LOCK_DURATION);
        LockedBalance[] storage earnings = userEarnings[_user];
        uint idx = earnings.length;

        if (idx == 0 || earnings[idx-1].unlockTime < unlockTime) {
            earnings.push(LockedBalance({amount: _amount, unlockTime: unlockTime}));
        } else {
            earnings[idx-1].amount = earnings[idx-1].amount.add(_amount);
        }

        // Actually transfer LQTY earnings to this contract
        lqtyToken.transferFrom(msg.sender, address(this), _amount);
    }

    /*
     * Withdraw staked tokens. First withdraws unlocked tokens, then earned tokens. Withdrawing
     * earned tokens before lock expiry will incur a 50% penalty to be burned.
     */
    function withdrawEarning(uint _amount) external override {
        require(_amount > 0, "Cannot withdraw 0");
        Balances storage bal = userBalances[msg.sender];
        uint penaltyAmount = 0;

        uint remaining = _amount;
        bal.earned = bal.earned.sub(remaining);
        for (uint i = 0; ; i++) {
            uint earnedAmount = userEarnings[msg.sender][i].amount;
            if (earnedAmount == 0) {
                continue;
            }
            if (penaltyAmount == 0 && userEarnings[msg.sender][i].unlockTime > block.timestamp) {
                penaltyAmount = remaining;
                totalBurned = totalBurned.add(penaltyAmount);
                require(bal.earned >= remaining, "Insufficient balance after penalty");
                bal.earned = bal.earned.sub(remaining);
                if (bal.earned == 0) {
                    delete userEarnings[msg.sender];
                    break;
                }
                remaining = remaining.mul(2);
            }
            if (remaining <= earnedAmount) {
                userEarnings[msg.sender][i].amount = earnedAmount.sub(remaining);
                break;
            } else {
                delete userEarnings[msg.sender][i];
                remaining = remaining.sub(earnedAmount);
            }
        }

        lqtyToken.transfer(msg.sender, _amount);
        emit EarningWithdraw(msg.sender, _amount, penaltyAmount, totalBurned);
    }

    // Final balance received and penalty balance paid by user upon exit
    function withdrawableEarning
    (
        address _user
    )
        external
        view
        override
        returns (uint withdrawableTotal, uint penalty, uint withdrawableNoPenalty)
    {
        Balances storage bal = userBalances[_user];
        if (bal.earned > 0) {
            uint length = userEarnings[_user].length;
            for (uint i = 0; i < length; i++) {
                uint earnedAmount = userEarnings[_user][i].amount;
                if (earnedAmount == 0) {
                    continue;
                }
                if (userEarnings[_user][i].unlockTime > block.timestamp) {
                    break;
                }
                withdrawableNoPenalty = withdrawableNoPenalty.add(earnedAmount);
            }

            penalty = bal.earned.sub(withdrawableNoPenalty).div(2);
        }
        withdrawableTotal = bal.earned.sub(penalty);
        return (withdrawableTotal, penalty, withdrawableNoPenalty);
    }

    // Information on the "earned" balances of a user
    // Earned balances may be withdrawn immediately for a 50% penalty
    function earnedBalances
    (
        address _user
    )
        view
        external
        override
        returns (uint total, uint[2][] memory earningsData)
    {
        LockedBalance[] storage earnings = userEarnings[_user];
        uint idx;
        for (uint i = 0; i < earnings.length; i++) {
            if (earnings[i].unlockTime > block.timestamp) {
                if (idx == 0) {
                    earningsData = new uint[2][](earnings.length - i);
                }
                earningsData[idx][0] = earnings[i].amount;
                earningsData[idx][1] = earnings[i].unlockTime;
                idx++;
                total = total.add(earnings[i].amount);
            }
        }
        return (total, earningsData);
    }
}
