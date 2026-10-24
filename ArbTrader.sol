// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.2 <=0.8.34.0;

import "@openzeppelin/contracts@4.9.3/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts@4.9.3/security/ReentrancyGuard.sol";

// Interface provided in the H6 handout
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

/// Buys a token on `buyPool` with FAKEETH and sells it on `sellPool`, all in one
/// transaction. If the round trip is not profitable the whole tx reverts, so a
/// competing trade landing first costs you only gas.
contract ArbTrader is ReentrancyGuard {
    address public immutable owner;
    int256 private constant BAD = type(int256).min / 2;

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    // Pools pay out ETH to this contract, and you fund it by sending ETH here.
    receive() external payable {}

    // ---------------------------------------------------------------- views

    /// Raw reserves of a pool: (ETH, token). Spot price = eth / token.
    function reserves(address pool, address token) external view returns (uint eth, uint tok) {
        return (pool.balance, IERC20(token).balanceOf(pool));
    }

    /// Profit (in wei, can be negative) of: ethIn -> token on buyPool -> ETH on sellPool.
    /// Reverts in a pool are reported as a hugely negative profit instead of reverting.
    function quoteProfit(address buyPool, address sellPool, uint ethIn) public view returns (int256) {
        if (ethIn == 0) return BAD;
        uint tokens;
        try testExchange(buyPool).estimateSwapForERC20Token(ethIn) returns (uint t) {
            tokens = t;
        } catch {
            return BAD;
        }
        if (tokens == 0) return BAD;
        try testExchange(sellPool).estimateSwapForEth(tokens) returns (uint back) {
            return int256(back) - int256(ethIn);
        } catch {
            return BAD;
        }
    }

    /// Ternary search for the profit-maximizing ETH input in [1, maxEth].
    /// Profit is concave in the input for constant-product pools, so this works.
    /// Only meaningful for two DIFFERENT pools (a same-pool quote ignores that the
    /// first leg moves the pool before the second leg).
    function bestAmount(address buyPool, address sellPool, uint maxEth)
        external
        view
        returns (uint bestIn, int256 bestProfit)
    {
        uint lo = 1;
        uint hi = maxEth;
        for (uint i = 0; i < 200 && hi - lo > 2; i++) {
            uint m1 = lo + (hi - lo) / 3;
            uint m2 = hi - (hi - lo) / 3;
            if (quoteProfit(buyPool, sellPool, m1) < quoteProfit(buyPool, sellPool, m2)) {
                lo = m1;
            } else {
                hi = m2;
            }
        }
        bestProfit = BAD;
        for (uint e = lo; e <= hi; e++) {
            int256 p = quoteProfit(buyPool, sellPool, e);
            if (p > bestProfit) {
                bestProfit = p;
                bestIn = e;
            }
        }
    }

    // --------------------------------------------------------------- trading

    /// Spend `ethIn` from this contract's balance. Reverts unless the contract's
    /// ETH balance ends at least `minProfit` higher than it started.
    /// buyPool == sellPool is allowed (for exploiting a pool with a stale/odd K).
    function arb(
        address buyPool,
        address sellPool,
        address token,
        uint ethIn,
        uint minProfit
    ) external onlyOwner nonReentrant {
        require(address(this).balance >= ethIn, "fund contract first");
        uint ethBefore = address(this).balance;
        uint tokBefore = IERC20(token).balanceOf(address(this));

        testExchange(buyPool).swapForERC20Token{value: ethIn}();

        // Trust balances, not return values (pools are untrusted code).
        uint got = IERC20(token).balanceOf(address(this)) - tokBefore;
        require(got > 0, "no tokens received");

        require(IERC20(token).approve(sellPool, got), "approve failed");
        testExchange(sellPool).swapForEth(got);
        IERC20(token).approve(sellPool, 0); // don't leave an allowance to untrusted code

        require(address(this).balance >= ethBefore + minProfit, "unprofitable");
    }

    // -------------------------------------------------------------- housekeeping

    function withdrawEth(uint amount) external onlyOwner {
        (bool ok, ) = payable(owner).call{value: amount}("");
        require(ok, "ETH send failed");
    }

    function withdrawToken(address token, uint amount) external onlyOwner {
        require(IERC20(token).transfer(owner, amount), "token send failed");
    }
}