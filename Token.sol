// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.2 <0.9.0;

interface IToken {
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}