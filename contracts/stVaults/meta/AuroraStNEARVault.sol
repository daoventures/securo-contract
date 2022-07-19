//SPDX-License-Identifier: MIT
//
///@notice The AuroraStNEARVault contract stakes wNEAR tokens into stNEAR on Aurora.
///@dev https://metapool.gitbook.io/master/developers-1/contract-adresses
///@dev https://metapool.app/dapp/mainnet/metapool-aurora/
//
pragma solidity  0.8.9;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import "../BasicStVault.sol";
import "../../bni/constant/AuroraConstant.sol";

interface IMetaPool {
    function swapwNEARForstNEAR(uint _amount) external;
    function swapstNEARForwNEAR(uint _amount) external;
    ///@dev price of stNEAR in wNEAR.
    function stNearPrice() external view returns (uint);
}

contract AuroraStNEARVault is BasicStVault {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IMetaPool constant metaPool = IMetaPool(0x534BACf1126f60EA513F796a3377ff432BE62cf9);

    function initialize(
        address _treasury, address _admin,
        address _priceOracle
    ) public initializer {
        super.initialize(
            "STI L2 stNEAR", "stiL2StNEAR",
            _treasury, _admin,
            _priceOracle,
            AuroraConstant.WNEAR,
            AuroraConstant.stNEAR
        );

        unbondingPeriod = 3 days;
        // The stNEAR buffer is replenished automatically every 5 minutes.
        investInterval = 5 minutes;
        // The wNEAR buffer is replenished automatically every 5 minutes.
        redeemInterval = 5 minutes;

        token.safeApprove(address(metaPool), type(uint).max);
        stToken.safeApprove(address(metaPool), type(uint).max);
    }

    function _invest(uint _amount) internal override returns (uint _invested) {
        uint stBuffer = stToken.balanceOf(address(metaPool));
        if (stBuffer > 0) {
            uint stNearAmount = getStTokenByPooledToken(_amount);
            if (stBuffer < stNearAmount) {
                _invested = _amount * stBuffer / stNearAmount;
            } else {
                _invested = _amount;
            }
            metaPool.swapwNEARForstNEAR(_invested);
        }
    }

    function _redeem(uint _pendingRedeems) internal override returns (uint _redeemed) {
        uint buffer = token.balanceOf(address(metaPool));
        if (buffer > 0) {
            uint wNearAmount = getPooledTokenByStToken(_pendingRedeems);
            if (buffer < wNearAmount) {
                _redeemed = _pendingRedeems * buffer / wNearAmount;
            } else {
                _redeemed = _pendingRedeems;
            }
            metaPool.swapstNEARForwNEAR(_redeemed);
        }
    }

    function _emergencyWithdraw(uint _pendingRedeems) internal override returns (uint _redeemed) {
        uint stBalance = stToken.balanceOf(address(this));
        if (stBalance >= minRedeemAmount) {
            emergencyUnbondings = (stBalance - _pendingRedeems);
            _redeemed = stBalance;
        }
    }

    ///@param _amount Amount of tokens
    function getStTokenByPooledToken(uint _amount) public override view returns(uint) {
        return _amount * oneStToken / metaPool.stNearPrice();
    }

    ///@param _stAmount Amount of stTokens
    function getPooledTokenByStToken(uint _stAmount) public override view returns(uint) {
        return _stAmount * metaPool.stNearPrice() / oneStToken;
    }

}
