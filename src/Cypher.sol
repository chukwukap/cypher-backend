// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// ──────────────────────────────────────────────────────────────────────────────
// Imports (as specified)
// ──────────────────────────────────────────────────────────────────────────────
import {Ownable} from "solady/auth/Ownable.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {MinHeapLib} from "solady/utils/MinHeapLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

/// @title Cypher - The Onchain Gauntlet
/// @notice Hyper-optimized, secure, fully onchain daily guessing game.
/// @dev Blueprint v2.3 (No-OZ, Solady Optimized). Target Solidity ^0.8.23.
contract Cypher is Ownable, ReentrancyGuard {
    using MinHeapLib for *;

    // ──────────────────────────────────────────────────────────────────────────
    // Errors (as specified)
    // ──────────────────────────────────────────────────────────────────────────
    error NotOwner();
    error NoKOLsAvailable();
    error AlreadyPlayedToday();
    error GameNotActive();
    error GameCycleNotOver();
    error AlreadyFinalized();
    error NoWinningsToClaim();
    error GameNotFinalized();
    error TransferFailed();
    error InsufficientPlayers();

    // ──────────────────────────────────────────────────────────────────────────
    // Types & Storage
    // ──────────────────────────────────────────────────────────────────────────

    enum Status {
        EMPTY,
        ACTIVE,
        COMPLETED,
        FAILED
    }

    struct PlayerData {
        Status status;
        bytes32 assignedKOLHash;
        uint256 depositAmount;
        uint256 startTime;
        uint256 endTime;
        uint256 attempts;
        uint256 finalScore; // 18 decimals
    }

    /// @notice USDC token (immutable as specified).
    IERC20 public immutable USDC_TOKEN;

    /// @notice Master list of all possible KOL answer hashes.
    bytes32[] public kolHashes;

    /// @notice Guess limit (8).
    uint256 public constant MAX_ATTEMPTS = 8;

    /// @notice Minimum number of players required to activate the prize pool.
    uint256 public constant MIN_PLAYERS = 5;

    /// @notice Finalizer incentive fee (100 bps = 1%).
    uint256 public constant FINALIZER_FEE_BPS = 100;

    /// @notice Per-day player data: gameId => player => data.
    mapping(uint256 => mapping(address => PlayerData)) public dailyPlayerData;

    /// @notice Per-day winnings: gameId => player => amount.
    mapping(uint256 => mapping(address => uint256)) public dailyWinnings;

    /// @notice List of all completed players per day (for scoring and payouts).
    mapping(uint256 => address[]) public completedPlayers;

    /// @notice Whether a given gameId has been finalized.
    mapping(uint256 => bool) public isFinalized;

    // ──────────────────────────────────────────────────────────────────────────
    // Events (as specified)
    // ──────────────────────────────────────────────────────────────────────────
    event GameStarted(
        uint256 indexed gameId,
        address indexed player,
        bytes32 assignedKOLHash
    );
    event GuessSubmitted(
        uint256 indexed gameId,
        address indexed player,
        uint256 attempts
    );
    event GameCompleted(
        uint256 indexed gameId,
        address indexed player,
        uint256 score
    );
    event GameFinalized(
        uint256 indexed gameId,
        uint256 prizePool,
        address finalizer
    );
    event RewardClaimed(
        uint256 indexed gameId,
        address indexed player,
        uint256 amount
    );

    // ──────────────────────────────────────────────────────────────────────────
    // Constructor & Owner Init (Solady Ownable)
    // ──────────────────────────────────────────────────────────────────────────
    constructor(address usdc) {
        if (usdc == address(0)) revert TransferFailed();
        USDC_TOKEN = IERC20(usdc);
        _initializeOwner(msg.sender);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Admin
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice Push a new KOL hash to the master list.
    /// @dev Uses custom error `NotOwner()` instead of Solady's `Unauthorized()`.
    function addKOL(bytes32 _kolHash) external {
        if (msg.sender != owner()) revert NotOwner();
        kolHashes.push(_kolHash);
    }

    /// @notice Clear all KOL hashes from the master list.
    /// @dev Restricted to owner, reverts with `NotOwner()` if unauthorized.
    function clearKOLs() external {
        if (msg.sender != owner()) revert NotOwner();
        delete kolHashes;
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Gameplay
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice Start the game for the current 24h cycle with an initial guess.
    /// @param _usdcAmount Amount of USDC to deposit.
    /// @param _firstGuess The player's first guess (string), checked immediately.
    function startGame(
        uint256 _usdcAmount,
        string calldata _firstGuess
    ) external nonReentrant {
        uint256 gameId = _currentGameId();

        PlayerData storage p = dailyPlayerData[gameId][msg.sender];
        if (p.status != Status.EMPTY) revert AlreadyPlayedToday();
        if (kolHashes.length == 0) revert NoKOLsAvailable();
        if (_usdcAmount == 0) revert TransferFailed();

        // Pseudo-random selection of KOL hash (prototype use only).
        bytes32 assigned = _randomAssignedHash(msg.sender);

        // Initialize player state.
        p.status = Status.ACTIVE;
        p.assignedKOLHash = assigned;
        p.depositAmount = _usdcAmount;
        p.startTime = block.timestamp;

        emit GameStarted(gameId, msg.sender, assigned);

        // Pull the deposit in USDC.
        bool ok = USDC_TOKEN.transferFrom(
            msg.sender,
            address(this),
            _usdcAmount
        );
        if (!ok) revert TransferFailed();

        // If their first guess is immediately correct, complete.
        if (_isCorrectGuess(assigned, _firstGuess)) {
            p.attempts = 1;
            _completeGame(gameId, msg.sender);
        } else {
            p.attempts = 1;
            emit GuessSubmitted(gameId, msg.sender, p.attempts);
        }
    }

    /// @notice Submit a guess for the current day after starting the game.
    /// @param _guess The guess to check.
    function submitGuess(string calldata _guess) external {
        uint256 gameId = _currentGameId();

        PlayerData storage p = dailyPlayerData[gameId][msg.sender];
        if (p.status != Status.ACTIVE) revert GameNotActive();

        unchecked {
            p.attempts += 1;
        }

        if (_isCorrectGuess(p.assignedKOLHash, _guess)) {
            _completeGame(gameId, msg.sender);
        } else {
            if (p.attempts >= MAX_ATTEMPTS) {
                p.status = Status.FAILED;
            }
            emit GuessSubmitted(gameId, msg.sender, p.attempts);
        }
    }

    /// @dev Private helper to complete the game, compute score, and emit event.
    function _completeGame(uint256 gameId, address playerAddress) private {
        PlayerData storage p = dailyPlayerData[gameId][playerAddress];

        if (p.status != Status.ACTIVE) revert GameNotActive();

        p.status = Status.COMPLETED;
        p.endTime = block.timestamp;

        uint256 timeTaken = p.endTime - p.startTime;
        uint256 attempts = p.attempts;
        if (attempts == 0) attempts = 1;

        // finalScore = 10_000_000e18 * 1e18 / (attempts * (timeTaken + 5))
        uint256 denom = attempts * (timeTaken + 5);
        p.finalScore = FixedPointMathLib.mulDiv(10_000_000 * 1e18, 1e18, denom);

        completedPlayers[gameId].push(playerAddress);

        emit GameCompleted(gameId, playerAddress, p.finalScore);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Finalization & Rewards
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice Finalize a past gameId (yesterday or earlier), compute winners & payouts.
    /// @dev Caller provides `allPlayers` to avoid onchain looping over unknown player set.
    ///      Uses Min-Heap to find the cutoff score for the top 40% without fully sorting.
    /// @param gameId The gameId to finalize.
    /// @param allPlayers A list of players who participated (ACTIVE/COMPLETED/FAILED).
    function finalizeGame(
        uint256 gameId,
        address[] calldata allPlayers
    ) external {
        if (_currentGameId() <= gameId) revert GameCycleNotOver();
        if (isFinalized[gameId]) revert AlreadyFinalized();

        address[] storage completed = completedPlayers[gameId];
        uint256 nCompleted = completed.length;
        if (nCompleted < MIN_PLAYERS) revert InsufficientPlayers();

        isFinalized[gameId] = true; // lock

        // 1) Determine top 40% cutoff via min-heap of size K = ceil(0.4 * nCompleted).
        uint256 K = (nCompleted * 40 + 99) / 100; // ceil
        if (K == 0) K = 1;

        MinHeapLib.MemHeap memory heap; // zero-init; no init() required

        // Seed with first K (or nCompleted if smaller).
        uint256 seed = K < nCompleted ? K : nCompleted;
        for (uint256 i = 0; i < seed; ) {
            address a = completed[i];
            uint256 s = dailyPlayerData[gameId][a].finalScore;
            MinHeapLib.push(heap, s);
            unchecked {
                ++i;
            }
        }

        // Keep only top-K largest values; root holds smallest among current top-K.
        for (uint256 i = seed; i < nCompleted; ) {
            address a = completed[i];
            uint256 s = dailyPlayerData[gameId][a].finalScore;

            if (MinHeapLib.length(heap) < K) {
                MinHeapLib.push(heap, s);
            } else {
                uint256 r = MinHeapLib.root(heap);
                if (s > r) {
                    // Prefer replaceRoot if present, else emulate via pop()+push().
                    // If your Solady version lacks `replaceRoot`, uncomment the 2 lines below
                    // and comment `replaceRoot`.
                    // heap.pop();
                    // heap.push(s);
                    MinHeapLib.replace(heap, s);
                }
            }
            unchecked {
                ++i;
            }
        }

        uint256 cutoffScore = MinHeapLib.root(heap);

        // 2) Build prizePool from FAILED players' deposits provided in `allPlayers`.
        uint256 prizePool;
        {
            uint256 len = allPlayers.length;
            for (uint256 i = 0; i < len; ) {
                PlayerData storage pd = dailyPlayerData[gameId][allPlayers[i]];
                if (pd.status == Status.FAILED) {
                    prizePool += pd.depositAmount;
                }
                unchecked {
                    ++i;
                }
            }
        }

        // 3) Finalizer fee
        uint256 finalizerFee = FixedPointMathLib.mulDiv(
            prizePool,
            FINALIZER_FEE_BPS,
            10_000
        );
        if (finalizerFee != 0) {
            bool okFee = USDC_TOKEN.transfer(msg.sender, finalizerFee);
            if (!okFee) revert TransferFailed();
        }

        // 4) Winners: score >= cutoffScore. Sum totalWeightedScore, then distribute.
        uint256 winningsPool = prizePool - finalizerFee;
        uint256 totalWeightedScore;

        for (uint256 i = 0; i < nCompleted; ) {
            address a = completed[i];
            uint256 s = dailyPlayerData[gameId][a].finalScore;
            if (s >= cutoffScore) {
                totalWeightedScore += s;
            }
            unchecked {
                ++i;
            }
        }

        if (totalWeightedScore == 0 || winningsPool == 0) {
            emit GameFinalized(gameId, prizePool, msg.sender);
            return;
        }

        for (uint256 i = 0; i < nCompleted; ) {
            address a = completed[i];
            uint256 s = dailyPlayerData[gameId][a].finalScore;
            if (s >= cutoffScore) {
                uint256 share = FixedPointMathLib.mulDiv(
                    winningsPool,
                    s,
                    totalWeightedScore
                );
                dailyWinnings[gameId][a] = share;
            }
            unchecked {
                ++i;
            }
        }

        emit GameFinalized(gameId, prizePool, msg.sender);
    }

    /// @notice Claim winnings after a gameId is finalized.
    /// @param gameId The gameId to claim from.
    function claimReward(uint256 gameId) external nonReentrant {
        if (!isFinalized[gameId]) revert GameNotFinalized();

        uint256 amt = dailyWinnings[gameId][msg.sender];
        if (amt == 0) revert NoWinningsToClaim();

        dailyWinnings[gameId][msg.sender] = 0;

        bool ok = USDC_TOKEN.transfer(msg.sender, amt);
        if (!ok) revert TransferFailed();

        emit RewardClaimed(gameId, msg.sender, amt);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // View / Helpers
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice Compute the current gameId based on 24h cycles.
    /// @dev gameId = block.timestamp / 86400
    function currentGameId() external view returns (uint256) {
        return _currentGameId();
    }

    /// @notice Return total KOL hashes available.
    function kolCount() external view returns (uint256) {
        return kolHashes.length;
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Internal Utilities
    // ──────────────────────────────────────────────────────────────────────────

    function _currentGameId() internal view returns (uint256) {
        return block.timestamp / 86400;
    }

    function _isCorrectGuess(
        bytes32 targetHash,
        string calldata guess
    ) internal pure returns (bool) {
        return keccak256(bytes(guess)) == targetHash;
    }

    function _randomAssignedHash(
        address player
    ) internal view returns (bytes32) {
        uint256 rnd = uint256(
            keccak256(
                abi.encodePacked(block.timestamp, block.prevrandao, player)
            )
        );
        uint256 idx = kolHashes.length == 0 ? 0 : rnd % kolHashes.length;
        return kolHashes[idx];
    }
}
