// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./SwapRouterHelper.sol";

contract LiqFunGameManager is SwapRouterHelper, Ownable {
    struct Game {
        bytes32 gameHash;
        uint256 startBlock;
        uint256 endBlock;
        uint256 token1Amount;
        uint256 token2Amount;
        uint8 token1PoolVersion;
        uint8 token2PoolVersion;
        uint24 token1PoolFee;
        uint24 token2PoolFee;
        bool hasCompleted;
    }

    struct GameResult {
        address winningTeam;
        uint256 endBlock;
        uint256 winningTokenAmount;
        uint256 newTokenAmount;
        bool dnf;
        bool tie;
        address losingTeam;
        uint256 losingTokenAmount;
    }

    error GameIsActive();
    error GameIsNotActive();
    error GameHasNotCompletedOrDoesntExist();
    error NothingToClaim();
    error InvalidCreationFee();
    error GameHasAlreadyBeenCompleted();

    event GameStarted(
        address indexed team1,
        address indexed team2,
        bytes32 indexed gameHash
    );

    event GameComplete(
        address indexed winner,
        address indexed loser,
        bytes32 indexed gameHash,
        bool dnf,
        bool tie
    );

    event StakeSubmitted(
        address indexed staker,
        bytes32 indexed game,
        address indexed token,
        uint256 amount
    );

    event StakeReclaimed(
        address indexed staker,
        bytes32 indexed game,
        address indexed token,
        uint256 amount
    );

    mapping(address team1 => mapping(address team2 => Game game)) public games;
    mapping(address staker => mapping(bytes32 gameHash => mapping(address team => uint256 amount)))
        public stakes;
    mapping(bytes32 gameHash => GameResult result) public results;

    address gameSigner;

    uint256 public LIQUIDATION_FEE = 5;
    uint256 public CREATION_FEE = 0.005 * 1 ether;

    constructor(
        address _gameSigner,
        address _router02,
        address _universalRouter,
        address _quoter,
        address _factoryV2
    )
        SwapRouterHelper(_router02, _universalRouter, _quoter, _factoryV2)
        Ownable(msg.sender)
    {
        gameSigner = _gameSigner;
    }

    function createGame(
        address team1,
        address team2,
        uint8 token1PoolVersion,
        uint8 token2PoolVersion,
        uint24 token1PoolFee,
        uint24 token2PoolFee,
        uint256 startBlock
    ) public payable {
        // if (msg.value != CREATION_FEE) {
        //     revert InvalidCreationFee();
        // }
        address t1 = team1 < team2 ? team1 : team2;
        address t2 = team1 == t1 ? team2 : team1;
        Game memory existingGame = games[t1][t2];
        if (
            existingGame.startBlock != 0 &&
            existingGame.endBlock > block.number &&
            !existingGame.hasCompleted
        ) {
            revert GameIsActive();
        }
        if (
            existingGame.startBlock != 0 &&
            existingGame.endBlock < block.number &&
            !existingGame.hasCompleted
        ) {
            _completeGame(t1, t2);
        }

        uint8 t1PoolVersion = t1 == team1
            ? token1PoolVersion
            : token2PoolVersion;
        uint8 t2PoolVersion = t1PoolVersion == token1PoolVersion
            ? token2PoolVersion
            : token1PoolVersion;

        uint24 t1Fee = t1 == team1 ? token1PoolFee : token2PoolFee;
        uint24 t2Fee = t1Fee == token1PoolFee ? token2PoolFee : token1PoolFee;

        games[t1][t2] = Game({
            gameHash: keccak256(abi.encodePacked(t1, t2, startBlock)),
            startBlock: startBlock,
            endBlock: startBlock + 3 minutes,
            token1Amount: 0,
            token2Amount: 0,
            token1PoolVersion: t1PoolVersion,
            token2PoolVersion: t2PoolVersion,
            token1PoolFee: t1Fee,
            token2PoolFee: t2Fee,
            hasCompleted: false
        });

        emit GameStarted(t1, t2, games[t1][t2].gameHash);
    }

    function stakeInGame(
        address team1,
        address team2,
        uint256 tokenAmount,
        address token
    ) public {
        address t1 = team1 < team2 ? team1 : team2;
        address t2 = team1 == t1 ? team2 : team1;

        Game storage game = games[t1][t2];
        if (
            game.startBlock == 0 ||
            game.endBlock < block.number ||
            game.hasCompleted
        ) {
            revert GameIsNotActive();
        }

        IERC20(token).transferFrom(msg.sender, address(this), tokenAmount);

        if (token == t1) {
            game.token1Amount += tokenAmount;
        } else if (token == t2) {
            game.token2Amount += tokenAmount;
        } else {
            revert("Invalid token");
        }

        stakes[msg.sender][game.gameHash][token] += tokenAmount;

        emit StakeSubmitted(msg.sender, game.gameHash, token, tokenAmount);
    }

    function reclaimStake(bytes32 gameHash) public {
        GameResult memory gameResult = results[gameHash];

        if (gameResult.winningTeam == address(0)) {
            revert GameHasNotCompletedOrDoesntExist();
        }

        // Assume losing team tokens have been liquidated so nothing to reclaim from there
        uint256 stake = stakes[msg.sender][gameHash][gameResult.winningTeam];

        if (stake > 0) {
            uint256 bonusAmount;

            // Calculate Share of Amount post-Liquidation to be sent to staker
            if (!gameResult.dnf && !gameResult.tie) {
                bonusAmount = _calculateNewTokenAmount(stake, gameResult);
            }

            uint256 totalAmount = stake + bonusAmount;

            IERC20(gameResult.winningTeam).transfer(msg.sender, totalAmount);
            stakes[msg.sender][gameHash][gameResult.winningTeam] = 0;
            emit StakeReclaimed(
                msg.sender,
                gameHash,
                gameResult.winningTeam,
                totalAmount
            );
        }

        // Handle DNF and Tie Cases
        if (gameResult.dnf || gameResult.tie) {
            uint256 otherStake = stakes[msg.sender][gameHash][
                gameResult.losingTeam
            ];
            if (otherStake > 0) {
                IERC20(gameResult.losingTeam).transfer(msg.sender, otherStake);
                stakes[msg.sender][gameHash][gameResult.losingTeam] = 0;

                emit StakeReclaimed(
                    msg.sender,
                    gameHash,
                    gameResult.losingTeam,
                    otherStake
                );
            }
        }
    }

    function completeGame(address team1, address team2) external {
        address t1 = team1 < team2 ? team1 : team2;
        address t2 = team1 == t1 ? team2 : team1;
        Game storage game = games[t1][t2];

        if (game.startBlock == 0 && game.endBlock == 0) {
            revert GameIsNotActive();
        }

        if (
            game.startBlock > 0 &&
            game.endBlock > block.number &&
            !game.hasCompleted
        ) {
            revert GameIsActive();
        }

        if (game.hasCompleted) {
            revert GameHasAlreadyBeenCompleted();
        }

        _completeGame(t1, t2);
    }

    function _completeGame(address team1, address team2) internal {
        address t1 = team1 < team2 ? team1 : team2;
        address t2 = team1 == t1 ? team2 : team1;
        Game storage game = games[t1][t2];

        uint256 token1TVL;
        uint256 token2TVL;

        if (game.token1Amount > 0) {
            if (game.token1PoolVersion == 2) {
                token1TVL = _quoteTokensToETHV2(t1, game.token1Amount);
            } else {
                token1TVL = _quoteTokensToETHV3(
                    t1,
                    game.token1PoolFee,
                    game.token1Amount
                );
            }
        }

        if (game.token2Amount > 0) {
            if (game.token2PoolVersion == 2) {
                token2TVL = _quoteTokensToETHV2(t2, game.token2Amount);
            } else {
                token2TVL = _quoteTokensToETHV3(
                    t2,
                    game.token2PoolFee,
                    game.token2Amount
                );
            }
        }

        bool team1Won = false;
        bool tie = false;
        bool dnf = false;

        if (token1TVL > 0 && token2TVL > 0 && token1TVL > token2TVL) {
            team1Won = true;
        } else if (token1TVL > 0 && token2TVL > 0 && token1TVL == token2TVL) {
            tie = true;
        } else if (token1TVL == 0 || token2TVL == 0) {
            dnf = true;
        }

        if (tie || dnf) {
            results[game.gameHash] = GameResult({
                winningTeam: t1,
                endBlock: block.number,
                winningTokenAmount: game.token1Amount,
                newTokenAmount: 0,
                dnf: dnf,
                tie: tie,
                losingTeam: t2,
                losingTokenAmount: game.token2Amount
            });

            game.token1Amount = 0;
            game.token2Amount = 0;
            game.startBlock = 0;
            game.endBlock = 0;
            game.hasCompleted = true;

            emit GameComplete(t1, t2, game.gameHash, dnf, tie);
            return;
        }

        address winningTeam = team1Won ? t1 : t2;
        address losingTeam = team1Won ? t2 : t1;

        uint256 losingAmount = team1Won ? game.token2Amount : game.token1Amount;

        bool winningIsV2 = winningTeam == t1
            ? game.token1PoolVersion == 2
            : game.token2PoolVersion == 2;
        bool losingIsV2 = losingTeam == t1
            ? game.token1PoolVersion == 2
            : game.token2PoolVersion == 2;
        uint256 ethOut = _swapAndLiquify(
            losingTeam,
            losingAmount,
            losingIsV2 ? 0 : game.token2PoolFee,
            losingIsV2
        );
        uint256 tokensOut = _swapForTokens(
            winningTeam,
            ethOut,
            winningIsV2 ? 0 : game.token1PoolFee,
            winningIsV2
        );

        results[game.gameHash] = GameResult({
            winningTeam: winningTeam,
            endBlock: block.number,
            winningTokenAmount: team1Won
                ? game.token1Amount
                : game.token2Amount,
            newTokenAmount: tokensOut,
            dnf: false,
            tie: false,
            losingTeam: losingTeam,
            losingTokenAmount: losingAmount
        });

        game.token1Amount = 0;
        game.token2Amount = 0;
        game.startBlock = 0;
        game.endBlock = 0;
        game.hasCompleted = true;

        emit GameComplete(t1, t2, game.gameHash, false, false);
    }

    function _calculateNewTokenAmount(
        uint256 userStakedAmount,
        GameResult memory gameResult
    ) internal pure returns (uint256) {
        require(
            gameResult.winningTokenAmount > 0,
            "Winning token amount must be greater than zero"
        );

        uint256 userPercentage = (userStakedAmount * 1e18) /
            gameResult.winningTokenAmount;
        uint256 userNewTokenAmount = (userPercentage *
            gameResult.newTokenAmount) / 1e18;

        return userNewTokenAmount;
    }

    function _swapAndLiquify(
        address losingToken,
        uint256 amountIn,
        uint24 v3Fee,
        bool useV2Router
    ) internal returns (uint256 ethOut) {
        if (useV2Router) {
            uint256 amountOutMin = _quoteTokensToETHV2(losingToken, amountIn);
            ethOut = _swapTokensForETHV2(losingToken, amountIn, amountOutMin);
        } else {
            uint256 amountOutMin = _quoteTokensToETHV3(
                losingToken,
                v3Fee,
                amountIn
            );
            ethOut = _swapTokensForETHV3(
                losingToken,
                amountIn,
                amountOutMin,
                v3Fee
            );
        }
        ethOut = (ethOut * (100 - LIQUIDATION_FEE)) / 100;
    }

    function _swapForTokens(
        address winningToken,
        uint256 ethIn,
        uint24 v3Fee,
        bool useV2Router
    ) internal returns (uint256 tokensOut) {
        if (useV2Router) {
            uint256 amountTokensMin = _quoteETHToTokensV2(winningToken, ethIn);
            tokensOut = _swapETHForTokensV2(
                winningToken,
                ethIn,
                amountTokensMin
            );
        } else {
            uint256 amountTokensMin = _quoteTokensToETHV3(
                winningToken,
                v3Fee,
                ethIn
            );
            tokensOut = _swapETHForTokensV3(
                winningToken,
                ethIn,
                amountTokensMin,
                v3Fee
            );
        }
    }

    function recoverTokens(address token) public onlyOwner {
        IERC20(token).transfer(
            msg.sender,
            IERC20(token).balanceOf(address(this))
        );
    }

    function recoverETH() public onlyOwner {
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success, "Transfer failed.");
    }

    function setGameSigner(address _gameSigner) public onlyOwner {
        gameSigner = _gameSigner;
    }

    function setLiquidationFee(uint256 _fee) public onlyOwner {
        LIQUIDATION_FEE = _fee;
    }

    function setCreationFee(uint256 _fee) public onlyOwner {
        CREATION_FEE = _fee;
    }
}
