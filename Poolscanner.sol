// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.2 <=0.8.34.0; // compile with 0.8.19 (EVM version paris)

interface IPool {
    function estimateSwapForERC20Token(uint _amountEth) external view returns (uint);
    function estimateSwapForEth(uint _amountERC20Token) external view returns (uint);
}

interface IERC20Min {
    function balanceOf(address account) external view returns (uint);
}

/// Read-only helper: pulls reserves and quotes from many pools in one call.
/// It never sends or receives anything, so calling it is free.
contract PoolScanner {
    // Gas cap per external quote so a hostile pool cannot hang the scan.
    uint private constant QUOTE_GAS = 300000;

    /// One call for a whole list of pools that trade the same token.
    /// For pool i: FakeETH balance, token balance, tokens received for `ethProbe`
    /// wei of FakeETH, and FakeETH received for selling `tokenProbe` raw tokens.
    /// A pool whose quote reverts reports 0 for that quote.
    function scan(
        address[] calldata pools,
        address token,
        uint ethProbe,
        uint tokenProbe
    )
        external
        view
        returns (
            uint[] memory ethBal,
            uint[] memory tokBal,
            uint[] memory buyQuote,
            uint[] memory sellQuote
        )
    {
        uint n = pools.length;
        ethBal = new uint[](n);
        tokBal = new uint[](n);
        buyQuote = new uint[](n);
        sellQuote = new uint[](n);
        for (uint i = 0; i < n; i++) {
            ethBal[i] = pools[i].balance;
            tokBal[i] = IERC20Min(token).balanceOf(pools[i]);
            try IPool(pools[i]).estimateSwapForERC20Token{gas: QUOTE_GAS}(ethProbe) returns (uint t) {
                buyQuote[i] = t;
            } catch {}
            try IPool(pools[i]).estimateSwapForEth{gas: QUOTE_GAS}(tokenProbe) returns (uint e) {
                sellQuote[i] = e;
            } catch {}
        }
    }

    /// Quotes for one pool at several sizes, to check how its price curve behaves
    /// (for example, whether it charges a fee).
    function buyCurve(address pool, uint[] calldata ethSizes) external view returns (uint[] memory out) {
        out = new uint[](ethSizes.length);
        for (uint i = 0; i < ethSizes.length; i++) {
            try IPool(pool).estimateSwapForERC20Token{gas: QUOTE_GAS}(ethSizes[i]) returns (uint t) {
                out[i] = t;
            } catch {}
        }
    }

    function sellCurve(address pool, uint[] calldata tokenSizes) external view returns (uint[] memory out) {
        out = new uint[](tokenSizes.length);
        for (uint i = 0; i < tokenSizes.length; i++) {
            try IPool(pool).estimateSwapForEth{gas: QUOTE_GAS}(tokenSizes[i]) returns (uint e) {
                out[i] = e;
            } catch {}
        }
    }
}
