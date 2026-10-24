// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.2 <=0.8.34.0;

interface testExchange {
    function provideLiquidity(uint _amountERC20Token) external payable returns (uint);
    function estimateEthToProvide(uint _amountERC20Token) external view returns (uint);
    function estimateERC20TokenToProvide(uint _amountEth) external view returns (uint);
    function getMyLiquidityPositions() external view returns (uint);
    function withdrawLiquidity(uint _liquidityPositionsToBurn) external returns (uint, uint);
    function swapForEth(uint _amountERC20Token) external returns (uint);
    function estimateSwapForEth(uint _amountERC20Token) external view returns (uint);
    function swapForERC20Token() external payable returns (uint);
    function estimateSwapForERC20Token(uint _amountEth) external view returns (uint);
}