// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPolinePurchase {
    function buyTokens(uint256 amount) external payable;

    function calculateCost(uint256 amount) external view returns (uint256 cost);

    function calculateTokens(
        uint256 maticAmount
    ) external view returns (uint256 amount);

    function pricePerToken() external view returns (uint256);

    function minimumPurchase() external view returns (uint256);

    function maximumPurchase() external view returns (uint256);

    function totalCollected() external view returns (uint256);

    function totalSold() external view returns (uint256);
}
