// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../src/Cypher.sol";

// Simple mock ERC20 token for testing transfer and approval.
contract MockERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public override totalSupply;
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(
        address to,
        uint256 amount
    ) external override returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(
        address spender,
        uint256 amount
    ) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external override returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowed >= amount, "Allowance exceeded");
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

contract CypherTest is Test {
    Cypher private cypher;
    MockERC20 private usdc;
    address private player;
    uint256 private depositAmount;

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        cypher = new Cypher(address(usdc));
        player = address(0xBEEF);
        depositAmount = 100 * 10 ** 6; // 100 USDC with 6 decimals

        // Mint USDC to player and approve Cypher contract
        usdc.mint(player, depositAmount);
        vm.prank(player);
        usdc.approve(address(cypher), depositAmount);
    }

    function testStartGameInitializesCorrectly() public {
        // Add a KOL so the game can start
        bytes32 kolHash = keccak256(abi.encodePacked("ANSWER"));
        cypher.addKOL(kolHash);

        // Start the game
        vm.prank(player);
        cypher.startGame(depositAmount);

        uint256 gameId = cypher.currentGameId();
        (
            Cypher.Status status,
            bytes32 assignedHash,
            uint256 depAmount,
            uint256 startTime,
            uint256 endTime,
            uint256 attempts,
            uint256 finalScore
        ) = cypher.dailyPlayerData(gameId, player);

        // After starting, status ACTIVE, attempts 0, deposit recorded
        assertEq(uint256(status), uint256(Cypher.Status.ACTIVE));
        assertEq(depAmount, depositAmount);
        assertEq(attempts, 0);
        assertEq(assignedHash, kolHash);
    }

    function testFirstGuessCorrectCompletesGame() public {
        // Prepare a known KOL
        bytes32 answerHash = keccak256(abi.encodePacked("SECRET"));
        cypher.addKOL(answerHash);

        // Start game and then guess correctly
        vm.prank(player);
        cypher.startGame(depositAmount);
        vm.prank(player);
        cypher.submitGuess(keccak256(bytes("SECRET")));

        uint256 gameId = cypher.currentGameId();
        (
            Cypher.Status status,
            bytes32 assignedHash,
            uint256 depAmount,
            uint256 startTime,
            uint256 endTime,
            uint256 attempts,
            uint256 finalScore
        ) = cypher.dailyPlayerData(gameId, player);

        // Game should be completed in 1 attempt
        assertEq(uint256(status), uint256(Cypher.Status.COMPLETED));
        assertEq(attempts, 1);
        assertGt(finalScore, 0);
    }

    function testGuessIncrementsAttemptsAndEmitsEvent() public {
        bytes32 answerHash = keccak256(abi.encodePacked("HELLO"));
        cypher.addKOL(answerHash);

        vm.prank(player);
        cypher.startGame(depositAmount);

        // Wrong guess should emit GuessSubmitted
        uint256 gameId = cypher.currentGameId();
        vm.prank(player);
        vm.expectEmit(true, true, true, true);
        emit Cypher.GuessSubmitted(gameId, player, 1);
        cypher.submitGuess(keccak256(bytes("WORLD")));

        (
            Cypher.Status status,
            bytes32 assignedHash,
            uint256 depAmount,
            uint256 startTime,
            uint256 endTime,
            uint256 attempts,
            uint256 finalScore
        ) = cypher.dailyPlayerData(gameId, player);
        assertEq(uint256(status), uint256(Cypher.Status.ACTIVE));
        assertEq(attempts, 1);

        // Another wrong guess increases attempts
        vm.prank(player);
        cypher.submitGuess(keccak256(bytes("TEST")));
        uint256 attempts2;
        uint256 dummyFinal;
        (, , , , , attempts2, dummyFinal) = cypher.dailyPlayerData(
            gameId,
            player
        );
        assertEq(attempts2, 2);
    }

    function testMaxAttemptsLeadsToFail() public {
        bytes32 answerHash = keccak256(abi.encodePacked("CODE"));
        cypher.addKOL(answerHash);
        vm.prank(player);
        cypher.startGame(depositAmount);

        // Make MAX_ATTEMPTS wrong guesses
        for (uint256 i = 0; i < cypher.MAX_ATTEMPTS(); ++i) {
            vm.prank(player);
            cypher.submitGuess(keccak256(bytes("WRONG")));
        }

        uint256 gameId = cypher.currentGameId();
        (
            Cypher.Status status,
            bytes32 assignedHash,
            uint256 depAmount,
            uint256 startTime,
            uint256 endTime,
            uint256 attempts,
            uint256 finalScore
        ) = cypher.dailyPlayerData(gameId, player);
        assertEq(uint256(status), uint256(Cypher.Status.FAILED));
        assertEq(attempts, cypher.MAX_ATTEMPTS());

        // Further guesses should revert
        vm.prank(player);
        vm.expectRevert(Cypher.GameNotActive.selector);
        cypher.submitGuess(keccak256(bytes("ANY")));
    }
}
