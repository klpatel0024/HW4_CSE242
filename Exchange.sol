// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.2 <=0.8.34.0;

import "@openzeppelin/contracts@4.9.3/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts@4.9.3/security/ReentrancyGuard.sol";

contract Exchange is ReentrancyGuard {
    ERC20 public token;
    mapping(address => uint) public liquidityPositions;
    uint public totalLiquidityPositions;
    uint public K;

    event LiquidityProvided(
        uint amountERC20TokenDeposited,
        uint amountEthDeposited,
        uint liquidityPositionsIssued
    );
    event LiquidityWithdrew(
        uint amountERC20TokenWithdrew,
        uint amountEthWithdrew,
        uint liquidityPositionsBurned
    );
    event SwapForEth(
        uint amountERC20TokenDeposited,
        uint amountEthWithdrew
    );
    event SwapForERC20Token(
        uint amountERC20TokenWithdrew,
        uint amountEthDeposited
    );

    constructor(address _token) {
        require(_token != address(0), "Invalid token");
        token = ERC20(_token);
    }

    function provideLiquidity(uint _amountERC20Token)
        external
        payable
        nonReentrant
        returns (uint)
    {
        require(_amountERC20Token > 0 && msg.value > 0, "Invalid amount");

        uint ethBalance = address(this).balance - msg.value;
        uint tokenBalance = token.balanceOf(address(this));

        uint positions;

        if (totalLiquidityPositions == 0) {
            positions = 100;
        } else {
            require(
                tokenBalance > 0 && ethBalance > 0,
                "Invalid pool"
            );
            require(
                msg.value * tokenBalance ==
                    _amountERC20Token * ethBalance,
                "Incorrect ratio"
            );

            positions =
                totalLiquidityPositions *
                _amountERC20Token /
                tokenBalance;

            require(positions > 0, "Too little liquidity");
        }

        require(
            token.transferFrom(
                msg.sender,
                address(this),
                _amountERC20Token
            ),
            "Token transfer failed"
        );

        liquidityPositions[msg.sender] += positions;
        totalLiquidityPositions += positions;
        K = (ethBalance + msg.value) *
            (tokenBalance + _amountERC20Token);

        emit LiquidityProvided(
            _amountERC20Token,
            msg.value,
            positions
        );

        return positions;
    }

    function estimateEthToProvide(uint _amountERC20Token)
        external
        view
        returns (uint)
    {
        require(_amountERC20Token > 0, "Invalid amount");

        uint tokenBalance = token.balanceOf(address(this));
        require(tokenBalance > 0, "No token liquidity");

        return address(this).balance *
            _amountERC20Token /
            tokenBalance;
    }

    function estimateERC20TokenToProvide(uint _amountEth)
        external
        view
        returns (uint)
    {
        require(_amountEth > 0, "Invalid amount");

        uint ethBalance = address(this).balance;
        require(ethBalance > 0, "No ETH liquidity");

        return token.balanceOf(address(this)) *
            _amountEth /
            ethBalance;
    }

    function getMyLiquidityPositions()
        external
        view
        returns (uint)
    {
        return liquidityPositions[msg.sender];
    }

    function withdrawLiquidity(uint _liquidityPositionsToBurn)
        external
        nonReentrant
        returns (uint, uint)
    {
        require(
            _liquidityPositionsToBurn > 0,
            "Invalid amount"
        );
        require(
            _liquidityPositionsToBurn <=
                liquidityPositions[msg.sender],
            "Not enough positions"
        );
        require(
            _liquidityPositionsToBurn <
                totalLiquidityPositions,
            "Cannot withdraw all"
        );

        uint ethBalance = address(this).balance;
        uint tokenBalance = token.balanceOf(address(this));

        uint ethToSend =
            _liquidityPositionsToBurn *
            ethBalance /
            totalLiquidityPositions;

        uint tokenToSend =
            _liquidityPositionsToBurn *
            tokenBalance /
            totalLiquidityPositions;

        require(ethToSend > 0 && tokenToSend > 0, "Invalid withdrawal");

        liquidityPositions[msg.sender] -=
            _liquidityPositionsToBurn;
        totalLiquidityPositions -=
            _liquidityPositionsToBurn;

        K = (ethBalance - ethToSend) *
            (tokenBalance - tokenToSend);

        require(
            token.transfer(msg.sender, tokenToSend),
            "Token transfer failed"
        );

        (bool success, ) =
            payable(msg.sender).call{value: ethToSend}("");
        require(success, "ETH transfer failed");

        emit LiquidityWithdrew(
            tokenToSend,
            ethToSend,
            _liquidityPositionsToBurn
        );

        return (tokenToSend, ethToSend);
    }

    function swapForEth(uint _amountERC20Token)
        external
        nonReentrant
        returns (uint)
    {
        require(_amountERC20Token > 0, "Invalid amount");

        uint ethBalance = address(this).balance;
        uint tokenBalance = token.balanceOf(address(this));

        require(
            ethBalance > 0 &&
            tokenBalance > 0 &&
            K > 0,
            "Invalid pool"
        );

        uint ethAfter =
            K /
            (tokenBalance + _amountERC20Token);

        uint ethToSend = ethBalance - ethAfter;

        require(
            ethToSend > 0 &&
            ethToSend < ethBalance,
            "Invalid swap"
        );

        require(
            token.transferFrom(
                msg.sender,
                address(this),
                _amountERC20Token
            ),
            "Token transfer failed"
        );

        (bool success, ) =
            payable(msg.sender).call{value: ethToSend}("");
        require(success, "ETH transfer failed");

        emit SwapForEth(
            _amountERC20Token,
            ethToSend
        );

        return ethToSend;
    }

    function estimateSwapForEth(uint _amountERC20Token)
        external
        view
        returns (uint)
    {
        require(_amountERC20Token > 0, "Invalid amount");

        uint ethBalance = address(this).balance;
        uint tokenBalance = token.balanceOf(address(this));

        require(
            ethBalance > 0 &&
            tokenBalance > 0 &&
            K > 0,
            "Invalid pool"
        );

        uint ethAfter =
            K /
            (tokenBalance + _amountERC20Token);

        return ethBalance - ethAfter;
    }

    function swapForERC20Token()
        external
        payable
        nonReentrant
        returns (uint)
    {
        require(msg.value > 0, "Invalid amount");

        uint ethBalance =
            address(this).balance - msg.value;
        uint tokenBalance = token.balanceOf(address(this));

        require(
            ethBalance > 0 &&
            tokenBalance > 0 &&
            K > 0,
            "Invalid pool"
        );

        uint tokenAfter =
            K /
            (ethBalance + msg.value);

        uint tokenToSend =
            tokenBalance - tokenAfter;

        require(
            tokenToSend > 0 &&
            tokenToSend < tokenBalance,
            "Invalid swap"
        );

        require(
            token.transfer(msg.sender, tokenToSend),
            "Token transfer failed"
        );

        emit SwapForERC20Token(
            tokenToSend,
            msg.value
        );

        return tokenToSend;
    }

    function estimateSwapForERC20Token(uint _amountEth)
        external
        view
        returns (uint)
    {
        require(_amountEth > 0, "Invalid amount");

        uint ethBalance = address(this).balance;
        uint tokenBalance = token.balanceOf(address(this));

        require(
            ethBalance > 0 &&
            tokenBalance > 0 &&
            K > 0,
            "Invalid pool"
        );

        uint tokenAfter =
            K /
            (ethBalance + _amountEth);

        return tokenBalance - tokenAfter;
    }
}