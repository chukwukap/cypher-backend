pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../src/KOLGame.sol";

// Dummy ERC20 token to simulate USDC in tests.
contract DummyERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 amount
    );

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(
            balanceOf[msg.sender] >= amount,
            "DummyERC20: transfer amount exceeds balance"
        );
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        require(
            balanceOf[from] >= amount,
            "DummyERC20: transfer amount exceeds balance"
        );
        require(
            allowance[from][msg.sender] >= amount,
            "DummyERC20: insufficient allowance"
        );
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    // Mint function for test setup convenience.
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }
}

contract KOLGameTest is Test {
    DummyERC20 token;
    KOLGame game;

    // Define addresses for players and a finalizer.
    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);
    address dave = address(0x4);
    address eve = address(0x5);
    address frank = address(0x6);
    address finalizer = address(0x9);

    uint256 constant initialBalance = 1000 * 1e6; // 1000 tokens (USDC has 6 decimals)
    uint256 constant depositAmount = 100 * 1e6; // 100 tokens deposit for each game

    function setUp() public {
        // Deploy dummy USDC token and KOLGame contract
        token = new DummyERC20("Test USDC", "USDC", 6);
        game = new KOLGame(address(token));
        // Mint initial token balances for each player
        address[6] memory players = [alice, bob, charlie, dave, eve, frank];
        for (uint256 i = 0; i < players.length; i++) {
            token.mint(players[i], initialBalance);
            // Each player approves the KOLGame contract to spend their tokens
            vm.prank(players[i]);
            token.approve(address(game), initialBalance);
        }
    }

    function testOnlyOwnerCanAddKOL() public {
        bytes32 kolHash = keccak256(abi.encodePacked("TEST_KOL"));
        // Owner (the test contract is owner because it deployed the game) can add KOL
        game.addKOL(kolHash);
        assertEq(game.kolCount(), 1);
        // Non-owner should not be able to add KOL
        vm.prank(bob);
        vm.expectRevert(KOLGame.NotOwner.selector);
        game.addKOL(kolHash);
    }

    function testNoKOLAvailableReverts() public {
        // No KOL has been added yet, startGame should revert
        vm.prank(alice);
        vm.expectRevert(KOLGame.NoKOLsAvailable.selector);
        game.startGame(depositAmount, "guess");
    }

    function testStartGameDepositZeroReverts() public {
        // Add a KOL so that NoKOLsAvailable is bypassed
        bytes32 kolHash = keccak256(abi.encodePacked("ANSWER"));
        game.addKOL(kolHash);
        // Starting the game with 0 deposit should revert with TransferFailed
        vm.prank(alice);
        vm.expectRevert(KOLGame.TransferFailed.selector);
        game.startGame(0, "ANSWER");
    }

    function testStartGameFirstGuessCorrectCompletes() public {
        // Add a known KOL hash and guess it correctly on the first try
        string memory answer = "SOLVED";
        bytes32 kolHash = keccak256(bytes(answer));
        game.addKOL(kolHash);

        // Expect GameStarted and GameCompleted events
        vm.expectEmit(true, true, false, true);
        emit KOLGame.GameStarted(0, alice, kolHash);
        vm.expectEmit(true, true, false, false);
        emit KOLGame.GameCompleted(0, alice, 0); // score checked separately
        vm.prank(alice);
        game.startGame(depositAmount, answer);

        // Verify player data after completion
        (
            KOLGame.Status status,
            bytes32 assignedHash,
            uint256 deposit,
            ,
            uint256 endTime,
            uint256 attempts,
            uint256 finalScore
        ) = game.dailyPlayerData(0, alice);
        assertTrue(status == KOLGame.Status.COMPLETED);
        assertEq(assignedHash, kolHash);
        assertEq(deposit, depositAmount);
        assertEq(attempts, 1);
        // Since guess was correct immediately, finalScore should be > 0 and endTime set
        assertTrue(finalScore > 0);
        assertTrue(endTime > 0);
    }

    function testStartGameFirstGuessWrongThenCorrect() public {
        // Add a KOL and simulate a player guessing wrong then right
        string memory answer = "WINNER";
        bytes32 kolHash = keccak256(bytes(answer));
        game.addKOL(kolHash);

        // Bob starts the game with an incorrect first guess
        vm.startPrank(bob);
        vm.expectEmit(true, true, false, true);
        emit KOLGame.GameStarted(0, bob, kolHash);
        vm.expectEmit(true, true, false, true);
        emit KOLGame.GuessSubmitted(0, bob, 1);
        game.startGame(depositAmount, "WRONG");
        // After first guess, Bob's game should be active with 1 attempt
        (KOLGame.Status status, , , , , uint256 attempts, ) = game
            .dailyPlayerData(0, bob);
        assertTrue(status == KOLGame.Status.ACTIVE);
        assertEq(attempts, 1);

        // Bob now submits the correct guess on the second attempt
        vm.expectEmit(true, true, false, false);
        emit KOLGame.GameCompleted(0, bob, 0);
        game.submitGuess(answer);
        vm.stopPrank();

        // Verify Bob's game is completed in 2 attempts
        (
            KOLGame.Status status2,
            ,
            ,
            ,
            ,
            uint256 attempts2,
            uint256 finalScore2
        ) = game.dailyPlayerData(0, bob);
        assertTrue(status2 == KOLGame.Status.COMPLETED);
        assertEq(attempts2, 2);
        assertTrue(finalScore2 > 0);

        // Bob should not be allowed to start another game on the same day
        vm.prank(bob);
        vm.expectRevert(KOLGame.AlreadyPlayedToday.selector);
        game.startGame(depositAmount, answer);
    }

    function testMaxAttemptsLeadsToFailure() public {
        // Add a KOL that the player will not guess correctly
        string memory answer = "SECRET";
        bytes32 kolHash = keccak256(bytes(answer));
        game.addKOL(kolHash);

        vm.startPrank(charlie);
        // Start the game with an incorrect guess
        vm.expectEmit(true, true, false, true);
        emit KOLGame.GameStarted(0, charlie, kolHash);
        vm.expectEmit(true, true, false, true);
        emit KOLGame.GuessSubmitted(0, charlie, 1);
        game.startGame(depositAmount, "GUESS1");
        // Submit 7 more incorrect guesses (total 8 attempts)
        string[7] memory guesses = [
            "GUESS2",
            "GUESS3",
            "GUESS4",
            "GUESS5",
            "GUESS6",
            "GUESS7",
            "GUESS8"
        ];
        for (uint256 i = 0; i < guesses.length; i++) {
            if (i == guesses.length - 1) {
                // Last guess (8th attempt) - expect GuessSubmitted with attempts=8
                vm.expectEmit(true, true, false, true);
                emit KOLGame.GuessSubmitted(0, charlie, 8);
            } else {
                vm.expectEmit(true, true, false, true);
                emit KOLGame.GuessSubmitted(0, charlie, 2 + i);
            }
            game.submitGuess(guesses[i]);
        }
        vm.stopPrank();

        // After 8 attempts, the game should be marked as FAILED
        (
            KOLGame.Status status,
            ,
            ,
            ,
            ,
            uint256 attempts,
            uint256 finalScore
        ) = game.dailyPlayerData(0, charlie);
        assertTrue(status == KOLGame.Status.FAILED);
        assertEq(attempts, 8);
        assertEq(finalScore, 0);

        // Further guesses after failure should revert
        vm.prank(charlie);
        vm.expectRevert(KOLGame.GameNotActive.selector);
        game.submitGuess("ANY");
    }

    function testFinalizeRevertsIfInsufficientPlayers() public {
        // Add a KOL and have 4 players complete the game (less than MIN_PLAYERS)
        bytes32 kolHash = keccak256(abi.encodePacked("WORD"));
        game.addKOL(kolHash);
        address[] memory players = new address[](4);
        players[0] = alice;
        players[1] = bob;
        players[2] = charlie;
        players[3] = dave;
        for (uint256 i = 0; i < players.length; i++) {
            // Each player guesses correctly on the first attempt
            vm.prank(players[i]);
            game.startGame(depositAmount, "WORD");
        }
        // Advance time to next day (gameId 0 is now over)
        vm.warp(block.timestamp + 1 days);
        // Finalizing with less than 5 completed players should revert
        vm.prank(finalizer);
        vm.expectRevert(KOLGame.InsufficientPlayers.selector);
        game.finalizeGame(0, players);
        // Claiming reward before finalization should revert
        vm.prank(alice);
        vm.expectRevert(KOLGame.GameNotFinalized.selector);
        game.claimReward(0);
    }

    function testFinalizeAndRewardDistribution() public {
        // Add a known KOL answer for players
        string memory answer = "TARGET";
        bytes32 kolHash = keccak256(bytes(answer));
        game.addKOL(kolHash);

        // Simulate 6 players with varying outcomes:
        // Alice: 1 attempt (fastest completion)
        // Bob: 2 attempts (1 wrong, then correct)
        // Charlie: 5 attempts (correct on 5th)
        // Dave: 8 attempts (correct on last attempt)
        // Eve: 3 attempts (with delays to simulate slower solve)
        // Frank: fails (8 wrong attempts)
        vm.prank(alice);
        game.startGame(depositAmount, answer);
        vm.startPrank(bob);
        game.startGame(depositAmount, "WRONG");
        game.submitGuess(answer);
        vm.stopPrank();
        vm.startPrank(charlie);
        game.startGame(depositAmount, "X1");
        game.submitGuess("X2");
        game.submitGuess("X3");
        game.submitGuess("X4");
        game.submitGuess(answer); // correct on 5th attempt
        vm.stopPrank();
        vm.startPrank(dave);
        game.startGame(depositAmount, "A1");
        for (uint256 i = 2; i <= 7; i++) {
            game.submitGuess(string(abi.encodePacked("A", vm.toString(i))));
        }
        game.submitGuess(answer); // correct on 8th attempt
        vm.stopPrank();
        vm.prank(eve);
        game.startGame(depositAmount, "Z1");
        // Simulate delays for Eve
        vm.warp(block.timestamp + 100);
        vm.prank(eve);
        game.submitGuess("Z2");
        vm.warp(block.timestamp + 200);
        vm.prank(eve);
        game.submitGuess(answer); // correct on 3rd attempt (after delays)
        vm.startPrank(frank);
        game.startGame(depositAmount, "N1");
        for (uint256 i = 2; i <= 8; i++) {
            game.submitGuess(string(abi.encodePacked("N", vm.toString(i))));
        }
        vm.stopPrank();

        // Verify that exactly 5 players completed (Frank failed)
        uint256 completedCount;
        (KOLGame.Status sAlice, , , , , , ) = game.dailyPlayerData(0, alice);
        (KOLGame.Status sBob, , , , , , ) = game.dailyPlayerData(0, bob);
        (KOLGame.Status sCharlie, , , , , , ) = game.dailyPlayerData(
            0,
            charlie
        );
        (KOLGame.Status sDave, , , , , , ) = game.dailyPlayerData(0, dave);
        (KOLGame.Status sEve, , , , , , ) = game.dailyPlayerData(0, eve);
        (KOLGame.Status sFrank, , , , , , ) = game.dailyPlayerData(0, frank);
        if (sAlice == KOLGame.Status.COMPLETED) completedCount++;
        if (sBob == KOLGame.Status.COMPLETED) completedCount++;
        if (sCharlie == KOLGame.Status.COMPLETED) completedCount++;
        if (sDave == KOLGame.Status.COMPLETED) completedCount++;
        if (sEve == KOLGame.Status.COMPLETED) completedCount++;
        if (sFrank == KOLGame.Status.COMPLETED) completedCount++;
        assertEq(completedCount, 5);

        // Advance time to next day to enable finalization of gameId 0
        vm.warp(block.timestamp + 1 days);

        // Prepare list of all participants for finalizeGame
        address[] memory allPlayers = new address[](6);
        allPlayers[0] = alice;
        allPlayers[1] = bob;
        allPlayers[2] = charlie;
        allPlayers[3] = dave;
        allPlayers[4] = eve;
        allPlayers[5] = frank;

        // Finalize the game and expect GameFinalized event
        uint256 balanceBeforeFinalizer = token.balanceOf(finalizer);
        vm.startPrank(finalizer);
        vm.expectEmit(true, false, false, true);
        emit KOLGame.GameFinalized(0, depositAmount, finalizer);
        game.finalizeGame(0, allPlayers);
        vm.stopPrank();
        uint256 balanceAfterFinalizer = token.balanceOf(finalizer);
        // Finalizer should receive 1% of the failed player's deposit
        uint256 expectedFee = (depositAmount * game.FINALIZER_FEE_BPS()) /
            10000;
        assertEq(balanceAfterFinalizer - balanceBeforeFinalizer, expectedFee);
        // GameId 0 is marked finalized
        assertTrue(game.isFinalized(0));

        // Determine winners (top 40% of completed players => top 2 scores)
        uint256 aliceWinnings = game.dailyWinnings(0, alice);
        uint256 bobWinnings = game.dailyWinnings(0, bob);
        uint256 charlieWinnings = game.dailyWinnings(0, charlie);
        uint256 daveWinnings = game.dailyWinnings(0, dave);
        uint256 eveWinnings = game.dailyWinnings(0, eve);
        // Only Alice and Bob should have non-zero winnings
        assertTrue(aliceWinnings > 0);
        assertTrue(bobWinnings > 0);
        assertEq(charlieWinnings, 0);
        assertEq(daveWinnings, 0);
        assertEq(eveWinnings, 0);
        // The sum of Alice and Bob's winnings should equal prizePool minus finalizer fee
        uint256 prizePool = depositAmount; // Frank's deposit
        uint256 finalizerFee = expectedFee;
        uint256 winningsPool = prizePool - finalizerFee;
        assertEq(aliceWinnings + bobWinnings, winningsPool);

        // Alice claims her reward (expect RewardClaimed event)
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit KOLGame.RewardClaimed(0, alice, aliceWinnings);
        game.claimReward(0);
        uint256 aliceBalanceAfter = token.balanceOf(alice);
        assertEq(aliceBalanceAfter - aliceBalanceBefore, aliceWinnings);
        // Alice cannot claim again
        vm.prank(alice);
        vm.expectRevert(KOLGame.NoWinningsToClaim.selector);
        game.claimReward(0);

        // Bob claims his reward (expect RewardClaimed event)
        uint256 bobBalanceBefore = token.balanceOf(bob);
        vm.prank(bob);
        vm.expectEmit(true, true, false, true);
        emit KOLGame.RewardClaimed(0, bob, bobWinnings);
        game.claimReward(0);
        uint256 bobBalanceAfter = token.balanceOf(bob);
        assertEq(bobBalanceAfter - bobBalanceBefore, bobWinnings);

        // A player with no winnings (Charlie) should not be able to claim
        vm.prank(charlie);
        vm.expectRevert(KOLGame.NoWinningsToClaim.selector);
        game.claimReward(0);

        // FinalizeGame should not be callable again for the same gameId
        vm.prank(finalizer);
        vm.expectRevert(KOLGame.AlreadyFinalized.selector);
        game.finalizeGame(0, allPlayers);

        // Cannot finalize a game that is still ongoing (current day)
        uint256 currentGame = game.currentGameId();
        vm.prank(finalizer);
        vm.expectRevert(KOLGame.GameCycleNotOver.selector);
        game.finalizeGame(currentGame, allPlayers);
    }
}
