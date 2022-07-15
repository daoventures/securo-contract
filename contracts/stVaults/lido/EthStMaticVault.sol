//SPDX-License-Identifier: MIT
pragma solidity  0.8.9;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import "../BasicStVault.sol";

interface IStakeManager {
    function epoch() external view returns (uint);
}

interface IPoLidoNFT {
    function getOwnedTokens(address _address) external view returns (uint[] memory);
    function tokenIdIndex() external view returns (uint);
}

struct StMATIC_RequestWithdraw {
    uint amount2WithdrawFromStMATIC;
    uint validatorNonce;
    uint requestEpoch;
    address validatorAddress;
}

interface IStMATIC {
    function token2WithdrawRequest(uint _tokenId) external view returns (StMATIC_RequestWithdraw memory);
    function stakeManager() external view returns (IStakeManager);
    function poLidoNFT() external view returns (IPoLidoNFT);
    function convertMaticToStMatic(uint _balance) external view returns (uint);
    function getMaticFromTokenId(uint _tokenId) external view returns (uint);

    function submit(uint _amount) external returns (uint);
    function requestWithdraw(uint _amount) external;
    function claimTokens(uint _tokenId) external;
}

contract EthStMaticVault is BasicStVault {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    mapping(uint => uint) public tokenIds;
    uint public first = 1;
    uint public last = 0;

    function initialize(
        address _treasury, address _admin,
        address _priceOracle
    ) public initializer {
        super.initialize(
            "STI L2 stMATIC", "stiL2StMATIC",
            _treasury, _admin,
            _priceOracle,
            0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0,
            0x9ee91F9f426fA633d227f7a9b000E28b9dfd8599
        );

        token.safeApprove(address(stToken), type(uint).max);
    }

    function _enqueue(uint _tokenId) private {
        last += 1;
        tokenIds[last] = _tokenId;
    }

    function _dequeue() private returns (uint _tokenId) {
        require(last >= first);  // non-empty queue
        _tokenId = tokenIds[first];
        delete tokenIds[first];
        first += 1;
    }

    function _invest(uint _amount) internal override {
        IStMATIC(address(stToken)).submit(_amount);

        IPoLidoNFT poLidoNFT = IStMATIC(address(stToken)).poLidoNFT();
        _enqueue(poLidoNFT.tokenIdIndex());
    }

    function _redeem(uint _pendingRedeems) internal override {
        IStMATIC(address(stToken)).requestWithdraw(_pendingRedeems);
    }

    function _claimUnbonded() internal override {
        IStakeManager stakeManager = IStMATIC(address(stToken)).stakeManager();
        uint epoch = stakeManager.epoch();
        uint balanceBefore = token.balanceOf(address(this));

        while (first <= last) {
            StMATIC_RequestWithdraw memory request = IStMATIC(address(stToken)).token2WithdrawRequest(tokenIds[first]);
            if (epoch < request.requestEpoch) {
                // Not able to claim yet
                break;
            }
            IStMATIC(address(stToken)).claimTokens(_dequeue());
        }

        uint _bufferedWithdrawals = bufferedWithdrawals + (token.balanceOf(address(this)) - balanceBefore);
        uint _pendingWithdrawals = pendingWithdrawals;
        bufferedWithdrawals = MathUpgradeable.min(_bufferedWithdrawals, _pendingWithdrawals);

        if (last < first && paused()) {
            // The tokens according to the emergency redeem has been claimed
            emergencyRedeems = 0;
        }
    }

    function _emergencyWithdraw(uint _pendingRedeems) internal override {
        uint stBalance = stToken.balanceOf(address(this));
        if (stBalance >= minRedeemAmount) {
            IStMATIC(address(stToken)).requestWithdraw(stBalance);
            emergencyRedeems = (stBalance - _pendingRedeems);
        }
    }

    function _yield() internal override {}

    ///@param _amount Amount of tokens
    function getStTokenByToken(uint _amount) public override view returns(uint) {
        return IStMATIC(address(stToken)).convertMaticToStMatic(_amount);
    }

    ///@notice Returns the pending rewards in USD.
    function getPendingRewards() public override view returns (uint) {
        return 0;
    }

    function getAPR() public override view returns (uint) {
        return 0;
    }

    function getUnbondedToken() public override view returns (uint _amount) {
        IStakeManager stakeManager = IStMATIC(address(stToken)).stakeManager();
        uint epoch = stakeManager.epoch();

        for (uint i = first; i <= last; i ++) {
            uint tokenId = tokenIds[i];
            StMATIC_RequestWithdraw memory request = IStMATIC(address(stToken)).token2WithdrawRequest(tokenId);
            if (epoch < request.requestEpoch) {
                // Not able to claim yet
                break;
            }
            _amount += IStMATIC(address(stToken)).getMaticFromTokenId(tokenId);
        }
    }
}
