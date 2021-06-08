// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {IERC20, LendingStrategy, SafeERC20, SafeMath} from "../Strategy.sol";

contract TestBorrowingStrategy {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    LendingStrategy public lender;
    uint256 public totalBorrowed;

    function setLender(address _newLender) external {
        lender = LendingStrategy(_newLender);
    }

    function reclaim(uint256 _amountNeeded) external returns (uint256 _loss) {
        IERC20 token = IERC20(lender.want());
        uint256 totalAssets = token.balanceOf(address(this));

        if (_amountNeeded > totalAssets) {
            token.transfer(msg.sender, totalAssets);
            _loss = _amountNeeded.sub(totalAssets);
        } else {
            token.transfer(msg.sender, _amountNeeded);
        }
    }

    function reclaimAll() external {
        IERC20 token = IERC20(lender.want());
        uint256 totalAssets = token.balanceOf(address(this));
        token.transfer(msg.sender, totalAssets);
    }

    function borrow(uint256 _amount) external {
        totalBorrowed = totalBorrowed.add(lender.borrow(_amount));
    }
}
