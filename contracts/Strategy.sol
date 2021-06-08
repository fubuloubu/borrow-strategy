// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {
    BaseStrategy,
    StrategyAPI,
    StrategyParams
} from "@yearnvaults/contracts/BaseStrategy.sol";

import {
    SafeERC20,
    SafeMath,
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

interface BorrowingStrategyAPI is StrategyAPI {
    // NOTE: Implementing strategy must return the amount it has borrowed from this strat
    function totalBorrowed() external view returns (uint256);

    function reclaim(uint256 _amountNeeded) external returns (uint256 _loss);

    function reclaimAll() external;

    function setLender(address _newLender) external;
}

contract LendingStrategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    // NOTE: `borrowingStrategy.reclaim` must allow clawback via `BaseStrategy.liquidatePosition`
    BorrowingStrategyAPI public borrowingStrategy;

    constructor(address _vault) public BaseStrategy(_vault) {}

    function name() external view override returns (string memory) {
        return "LendingStrategy";
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        // NOTE: total want balance of this accounts for `totalProfit`
        return
            want.balanceOf(address(this)).add(
                borrowingStrategy.totalBorrowed()
            );
    }

    function borrow(uint256 _amountRequested)
        external
        returns (uint256 _amountLent)
    {
        require(msg.sender == address(borrowingStrategy));

        uint256 totalAssets = want.balanceOf(address(this));
        if (totalAssets > _amountRequested) {
            want.transfer(msg.sender, _amountRequested);
        } else {
            want.transfer(msg.sender, totalAssets);
        }
    }

    function setBorrower(address _newBorrower) external onlyGovernance {
        uint256 totalBorrowed = 0;
        if (address(borrowingStrategy) != address(0)) {
            totalBorrowed = borrowingStrategy.totalBorrowed();
        }

        // NOTE: Cannot lose track of the borrowed amount when changing/migrating upstream
        // NOTE: When first set, this amount should be 0, making the check work
        require(
            totalBorrowed == BorrowingStrategyAPI(_newBorrower).totalBorrowed()
        );

        borrowingStrategy = BorrowingStrategyAPI(_newBorrower);
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        uint256 totalAssets = want.balanceOf(address(this));
        if (totalAssets < _debtOutstanding) {
            _loss = borrowingStrategy.reclaim(
                _debtOutstanding.sub(totalAssets)
            );
            totalAssets = want.balanceOf(address(this));
        }

        if (totalAssets > _debtOutstanding) {
            _debtPayment = totalAssets.sub(_debtOutstanding);
            _profit = totalAssets.sub(_debtPayment);
        }
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {}

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        uint256 totalAssets = want.balanceOf(address(this));
        if (totalAssets < _amountNeeded) {
            _loss = borrowingStrategy.reclaim(_amountNeeded.sub(totalAssets));
            totalAssets = want.balanceOf(address(this));
        }

        // NOTE: Maintain invariant `want.balanceOf(this) >= _liquidatedAmount`
        // NOTE: Maintain invariant `_liquidatedAmount + _loss <= _amountNeeded`
        if (totalAssets < _amountNeeded) {
            _liquidatedAmount = totalAssets;
            _loss = _loss.add(_amountNeeded.sub(totalAssets));
        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        borrowingStrategy.reclaimAll();
        return want.balanceOf(address(this));
    }

    function prepareMigration(address _newStrategy) internal override {
        borrowingStrategy.setLender(_newStrategy);
    }

    function protectedTokens()
        internal
        view
        virtual
        override
        returns (address[] memory tokens)
    {}

    /**
     * @notice
     *  Provide an accurate conversion from `_amtInWei` (denominated in wei)
     *  to `want` (using the native decimal characteristics of `want`).
     * @dev
     *  Care must be taken when working with decimals to assure that the conversion
     *  is compatible. As an example:
     *
     *      given 1e17 wei (0.1 ETH) as input, and want is USDC (6 decimals),
     *      with USDC/ETH = 1800, this should give back 1800000000 (180 USDC)
     *
     * @param _amtInWei The amount (in wei/1e-18 ETH) to convert to `want`
     * @return The amount in `want` of `_amtInEth` converted to `want`
     **/
    function ethToWant(uint256 _amtInWei)
        public
        view
        virtual
        override
        returns (uint256)
    {
        // TODO create an accurate price oracle
        return _amtInWei;
    }
}
